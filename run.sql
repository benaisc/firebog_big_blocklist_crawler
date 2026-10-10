SET http_retries = 1;
SET force_download = true;

-- ---- Discover blocklists(ticked = well maintained, mostly hassle free) -----
CREATE TABLE wally3k_ticked_blocklists AS
	SELECT DISTINCT trim(source_URL) AS url
	FROM read_csv(
		'https://v.firebog.net/hosts/csv.txt', 
		header=false, 
		all_varchar=true,
	    names=['category','ticktype','source_repo','description','source_URL']
	)
	WHERE ticktype = 'tick' AND trim(source_URL) ILIKE 'http%';

SET VARIABLE urls = (SELECT list(url) FROM wally3k_ticked_blocklists);

-- ---- Ingest: one raw line per row, tagged with its origin ----------------
-- delim='\0' + no quoting = "read whole line as-is".
-- Parse: [optional IP] domain [# comment]; hosts and domain-only.
-- NOTE: one unreachable URL aborts the run (fail fast, no silent shrink).
CREATE TABLE domains AS
SELECT 
	filename AS source,
    regexp_extract(lower(line),'^\s*(?:[0-9a-f:.]+\s+)?([a-z0-9_.-]+)\s*(?:#.*)?$', 1) AS domain
FROM read_csv(
	getvariable('urls'), 
	header=false, 
	columns={line: 'VARCHAR'},
	delim='\0', 
	quote='', 
	escape='', 
	strict_mode=false, 
	max_line_size=512,
	filename=true
)
WHERE NULLIF(domain, '') IS NOT NULL
UNION VALUES 
	('Local Network Defaults','127.0.0.1 localhost'),
	('Local Network Defaults','127.0.0.1 localhost.localdomain'),
	('Local Network Defaults','127.0.0.1 local'),
	('Local Network Defaults','255.255.255.255 broadcasthost'),
	('Local Network Defaults','::1 localhost'),
	('Local Network Defaults','::1 ip6-localhost'),
	('Local Network Defaults','::1 ip6-loopback'),
	('Local Network Defaults','ff00::0 ip6-localnet'),
	('Local Network Defaults','ff00::0 ip6-mcastprefix'),
	('Local Network Defaults','ff02::1 ip6-allnodes'),
	('Local Network Defaults','ff02::2 ip6-allrouters'),
	('Local Network Defaults','ff02::3 ip6-allhosts'),
	('Local Network Defaults','0.0.0.0 0.0.0.0');

COPY (SELECT domain FROM domains ORDER BY domain)
TO 'blocklist_ticked_all.txt' (FORMAT CSV, HEADER FALSE);

-- ======================= SCD2 DWH TABLE + MERGE ==========================
ATTACH IF NOT EXISTS 'dwh_blocklists.duckdb' AS dwh;

-- Grain: one row per (domain, source) membership interval.
CREATE TABLE IF NOT EXISTS dwh.blocklist_domain_scd2 (
	domain      VARCHAR   NOT NULL,
	source      VARCHAR   NOT NULL,
	valid_from  TIMESTAMP NOT NULL,
	valid_to    TIMESTAMP NOT NULL DEFAULT TIMESTAMP '9999-12-31',
	is_current  BOOLEAN   NOT NULL DEFAULT true
);

SET VARIABLE run_ts = (SELECT now()::TIMESTAMP);

-- 1. Close rows that disappeared from the source
UPDATE dwh.blocklist_domain_scd2 AS t
SET valid_to = getvariable('run_ts'),
    is_current = false
WHERE t.is_current
  AND NOT EXISTS (
      SELECT 1 FROM domains s
      WHERE s.domain = t.domain AND s.source = t.source
  );

-- 2. Open rows that are new
INSERT INTO dwh.blocklist_domain_scd2 (domain, source, valid_from, valid_to, is_current)
SELECT s.domain, s.source, getvariable('run_ts'), TIMESTAMP '9999-12-31', true
FROM domains s
WHERE NOT EXISTS (
    SELECT 1 FROM dwh.blocklist_domain_scd2 t
    WHERE t.is_current
      AND t.domain = s.domain AND t.source = s.source
);

-- ## QUALITY GATE
-- Tiny assertion helper: returns true or aborts the script with a message
CREATE OR REPLACE MACRO assert(ok, msg) AS
    CASE WHEN ok THEN true ELSE error(msg) END;

-- 1. Volume floor (tune the threshold to your real size)
SELECT assert(
    (SELECT count(*) FROM dwh.blocklist_domain_scd2 WHERE is_current) >= 400000,
    format('SCD2 check: only {} current domains (< 100000)',
           (SELECT count(*) FROM dwh.blocklist_domain_scd2 WHERE is_current)));

-- 2. Churn guard: the last run must not have closed more than 20% of the current set
--    (catches a truncated download that would "delete" half the list)
WITH last_close AS (
    SELECT max(valid_to) AS ts FROM dwh.blocklist_domain_scd2
    WHERE valid_to < TIMESTAMP '9999-12-31'
)
SELECT assert(
    coalesce((SELECT count(*) FROM dwh.blocklist_domain_scd2, last_close
              WHERE valid_to = last_close.ts), 0)
      <= 0.20 * (SELECT count(*) FROM dwh.blocklist_domain_scd2 WHERE is_current),
    'SCD2 check: churn > 20% in last run, suspicious partial download');

DETACH dwh;
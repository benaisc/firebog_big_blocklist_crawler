-- [CLI special commands](https://duckdb.org/docs/api/cli#special-commands-dot-commands)
.bail on

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
CREATE TABLE domains_raw AS
SELECT 
	filename AS source, 
	line, 
    regexp_extract(lower(line),'^\s*(?:[0-9a-f:.]+\s+)?([a-z0-9_.-]+)\s*(?:#.*)?$', 1) AS domain
FROM read_csv(
	getvariable('urls'), 
	header=false, 
	columns={line: 'VARCHAR'},
	delim='\0', 
	quote='', 
	escape='', 
	strict_mode=false, 
	filename=true
)
WHERE NULLIF(domain, '') IS NOT NULL
UNION VALUES
    (null,null,'127.0.0.1 localhost'),
    (null,null,'127.0.0.1 localhost.localdomain'),
    (null,null,'127.0.0.1 local'),
    (null,null,'255.255.255.255 broadcasthost'),
    (null,null,'::1 localhost'),
    (null,null,'::1 ip6-localhost'),
    (null,null,'::1 ip6-loopback'),
    (null,null,'ff00::0 ip6-localnet'),
    (null,null,'ff00::0 ip6-mcastprefix'),
    (null,null,'ff02::1 ip6-allnodes'),
    (null,null,'ff02::2 ip6-allrouters'),
    (null,null,'ff02::3 ip6-allhosts'),
    (null,null,'0.0.0.0 0.0.0.0');

COPY (SELECT domain FROM domains_raw ORDER BY domain)
TO 'blocklist_ticked_all.txt' (FORMAT CSV, HEADER FALSE);

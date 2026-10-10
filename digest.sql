ATTACH 'dwh_blocklists.duckdb' AS dwh (READ_ONLY);

CREATE TEMP VIEW cur AS
SELECT domain, source FROM dwh.blocklist_domain_scd2 WHERE is_current;
-- membership as it stood at the start of today (UTC)
CREATE TEMP VIEW prv AS
SELECT domain, source FROM dwh.blocklist_domain_scd2
WHERE valid_from < current_date AND valid_to >= current_date;

.mode markdown
.print ## Summary
SELECT
(SELECT count(DISTINCT domain) FROM cur) AS unique_domains,
(SELECT count(DISTINCT domain) FROM cur)
    - (SELECT count(DISTINCT domain) FROM prv) AS delta_vs_prev,
(SELECT count(*) FROM (SELECT domain FROM cur EXCEPT SELECT domain FROM prv)) AS new_domains,
(SELECT count(*) FROM (SELECT domain FROM prv EXCEPT SELECT domain FROM cur)) AS dropped_domains,
(SELECT count(DISTINCT source) FROM cur) AS sources;

.print
.print ## Source movers (top 10)
WITH c AS (SELECT source, count(*) n FROM cur GROUP BY 1),
    p AS (SELECT source, count(*) n FROM prv GROUP BY 1)
SELECT regexp_replace(source, '^https?://', '') AS source,
        coalesce(p.n, 0) AS prev,
        coalesce(c.n, 0) AS today,
        coalesce(c.n, 0) - coalesce(p.n, 0) AS delta,
        round(100.0 * (coalesce(c.n, 0) - coalesce(p.n, 0)) / nullif(p.n, 0), 1) AS pct,
        CASE WHEN p.n IS NULL OR c.n IS NULL
            OR abs(100.0 * (c.n - p.n) / p.n) >= 20 THEN 'CHECK' END AS flag
FROM c FULL JOIN p USING (source)
WHERE coalesce(c.n, 0) <> coalesce(p.n, 0)
ORDER BY abs(coalesce(c.n, 0) - coalesce(p.n, 0)) DESC
LIMIT 10;

.print
.print ## Overlap
SELECT count(*) FILTER (WHERE n = 1) AS single_source,
        count(*) FILTER (WHERE n >= 2) AS multi_source,
        round(100.0 * count(*) FILTER (WHERE n >= 2) / count(*), 1) AS pct_multi_source
FROM (SELECT domain, count(*) AS n FROM cur GROUP BY domain);

DETACH dwh;
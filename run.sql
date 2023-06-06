-- [CLI special commands](https://duckdb.org/docs/api/cli#special-commands-dot-commands) 
.bail on

-- [Extensions](https://duckdb.org/docs/extensions/httpfs)
INSTALL 'httpfs';
LOAD 'httpfs';

-- Download The Big Host List of lists
CREATE TABLE blocklists AS (
	select
	*
	from read_csv_auto(
		'https://v.firebog.net/hosts/csv.txt', 
		header=false, 
		all_varchar=true, 
		names=['category','ticktype','source_repo','description','source_URL']
	)
);


-- Dynamically create a SQL query, writes execution result to disk, and then execute it.
.mode list
.header off
.once excelsior.sql
SELECT 
'CREATE TABLE urls_with_filename AS (SELECT * FROM read_csv([''' || string_agg(source_URL,''',''') || '''], header=false, columns={random_text: ''VARCHAR''}, delim=''\0'', filename=true)' || ')' as query
FROM blocklists
WHERE ticktype='tick'; -- ticks only, unfortunately other lists are not well maintained
.read excelsior.sql


CREATE TABLE complete AS (
	SELECT DISTINCT ON (urls.random_text)
		blocklists.*,
		urls.random_text,
	FROM blocklists
	LEFT JOIN urls_with_filename AS urls ON blocklists.source_URL = urls.filename
	WHERE urls.random_text IS NOT NULL AND NOT starts_with(urls.random_text, '#')
);


-- All data, URLs only
COPY (SELECT trim(regexp_replace(random_text, ' #.*$', '')) FROM complete) TO 'blocklist_ticked_all.txt' (FORMAT CSV, HEADER FALSE);

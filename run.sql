-- [CLI special commands](https://duckdb.org/docs/api/cli#special-commands-dot-commands)
.bail on

-- Download The Big Host List of lists
SET force_download=true;

CREATE TABLE blocklists AS
	from read_csv(
		'https://v.firebog.net/hosts/csv.txt',
		header=false,
		all_varchar=true,
		names=['category','ticktype','source_repo','description','source_URL']
	);

-- Dynamically create a SQL query, writes execution result to disk, and then execute it.
.mode list
.header off
.once excelsior.sql
SELECT 
'CREATE TABLE the_big_blocklist AS (SELECT * FROM read_csv([''' || string_agg(source_URL,''',''') || '''], header=false, columns={random_text: ''VARCHAR''}, delim=''\0'', filename=true, strict_mode=false)' || ')' as query
FROM blocklists
WHERE ticktype='tick';-- ticked lists are well maintained and mostly hassle free
.read excelsior.sql

-- All data, URLs only
COPY (select distinct random_text from the_big_blocklist where random_text is not null and not regexp_matches(random_text, '\s*#')) TO 'blocklist_ticked_all.txt' (FORMAT CSV, HEADER FALSE);

# 🕳️ Big Blocklist

One Pi-hole blocklist, rebuilt every day, merged from all the **"ticked"** lists of [The Firebog](https://firebog.net). Duplicates removed, one domain per line.

## Use it

1. In Pi-hole, open **Adlists** (*Group Management → Adlists*).
2. Paste this address and click **Add**:

```
   https://github.com/benaisc/firebog_big_blocklist_crawler/releases/latest/download/blocklist_ticked_all.txt
```

3. Update gravity (*Tools → Update Gravity*, or `pihole -g`).

That's it. Pi-hole re-fetches the list on its regular gravity schedule, so you get each daily rebuild automatically.

## What's in the box

- **Source**: Firebog's ticked lists, discovered fresh at every run.
- **Format**: plain domains, deduplicated, sorted.
- **Daily digest**: each release's notes show list size, what was added or dropped since yesterday, and which source lists moved a lot.
- **One release only**: the latest release is the single source of truth. Older ones are deleted.

## Good to know

- Ticked lists are conservative, but any big blocklist can occasionally block something you need. Allow it in Pi-hole's **Domains** page.
- Already subscribed to some Firebog lists? Overlap is harmless, just redundant.

## How it works

A GitHub Action runs [DuckDB](https://duckdb.org) daily: it downloads the lists, merges them into one file, and keeps a change history (SCD2) used for the digest. Peek at `blocklist.sql` and `digest.sql` if you are curious, and `ATTACH 'https://github.com/benaisc/firebog_big_blocklist_crawler/releases/download/dwh/dwh_blocklists.duckdb' as dwh_blocklists` to explore !
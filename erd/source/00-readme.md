# HRango ERD source (first build)

Edit this file, then run `build.py` to regenerate `HRango - ERD.md` and `HRango - ERD.drawio`.
Column lines: `name  FK target  note`. Types are added by build.py from the column names and its override list.
A section header `## N. Title [schema]` sets the SQL Server schema for that section.

One file per module, each owned by one person or agent at a time. build.py reads them in name order.

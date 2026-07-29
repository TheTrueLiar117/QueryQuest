# QueryQuest — Quick-Commerce SQL Project

A PostgreSQL relational-database project modelling a quick-commerce platform
(users, inventory, orders, deliveries) plus three extra querying scenarios
(employees, banking, food-delivery), with analytical SQL for reporting.

## Files
| File | Purpose |
|---|---|
| `01_schema.sql` | Quick-commerce schema: tables, FK/UNIQUE/CHECK constraints, indexes |
| `02_seed.sql` | Sample data (includes deliberate edge cases) |
| `03_queries.sql` | 15 analytical queries: joins, subqueries, GROUP BY/HAVING, window fns |
| `04_scenarios.sql` | Employee, banking & food-delivery schemas + queries |
| `QueryQuest_Prep_Guide.md` | Full explanation of every design decision + interview prep |

## Run it
```bash
createdb queryquest
psql -d queryquest -f 01_schema.sql
psql -d queryquest -f 02_seed.sql
psql -d queryquest -f 03_queries.sql
psql -d queryquest -f 04_scenarios.sql
```

Requires PostgreSQL 10+ (built and tested on PostgreSQL 16).
Start with the prep guide — it explains what everything is and why.

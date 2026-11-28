-- One row per database that is not parked, for the collector's sqlquery
-- receiver: drift 1 when the collation version recorded at its creation or
-- last refresh differs from the one the server's library provides now, as
-- PostgreSQL's own connection-time check compares them, which skips a
-- database with no recorded version (postgres/postgres@REL_16_15:
-- src/backend/utils/init/postinit.c, CheckMyDatabase); template0 has none.
-- The parked names are written into the array in the WHERE clause as SQL
-- literals; with none parked it is empty and leaves out no database. A
-- missing version is '' rather than NULL, which the receiver would warn
-- about.
WITH db AS (
  SELECT datname::text AS datname,
         datcollversion AS recorded,
         pg_database_collation_actual_version(oid) AS actual
  FROM pg_database
  WHERE datname <> ALL (ARRAY[@parked@]::text[])
)
SELECT datname,
       coalesce(recorded, '') AS collversion_recorded,
       coalesce(actual, '') AS collversion_actual,
       CASE WHEN recorded IS NOT NULL AND recorded IS DISTINCT FROM actual THEN 1 ELSE 0 END AS drift
FROM db
ORDER BY datname COLLATE "C";

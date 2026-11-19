-- One node_exporter textfile line per database that is not parked: 1 when
-- the collation version recorded at its creation or last refresh differs
-- from the one the server's library provides now, as PostgreSQL's own
-- connection-time check compares them, which skips a database with no
-- recorded version (postgres/postgres@REL_16_15:
-- src/backend/utils/init/postinit.c, CheckMyDatabase); template0 has none.
-- :'parked' is a JSON array of database names the probe leaves out.
WITH db AS (
  SELECT datname,
         datcollversion AS recorded,
         pg_database_collation_actual_version(oid) AS actual
  FROM pg_database
  WHERE datname <> ALL (ARRAY(SELECT json_array_elements_text(:'parked'::json)))
)
SELECT format(
  'vanixiets_postgresql_collation_drift{datname="%s",collversion_recorded="%s",collversion_actual="%s"} %s',
  replace(regexp_replace(datname, '([\\"])', '\\\1', 'g'), E'\n', '\n'),
  replace(regexp_replace(coalesce(recorded, ''), '([\\"])', '\\\1', 'g'), E'\n', '\n'),
  replace(regexp_replace(coalesce(actual, ''), '([\\"])', '\\\1', 'g'), E'\n', '\n'),
  CASE WHEN recorded IS NOT NULL AND recorded IS DISTINCT FROM actual THEN 1 ELSE 0 END
)
FROM db
ORDER BY datname COLLATE "C";

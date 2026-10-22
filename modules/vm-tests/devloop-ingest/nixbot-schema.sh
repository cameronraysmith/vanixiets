#!/usr/bin/env bash
# Stand-in for nixbot's start in vmTests.x86_64-linux.devloop-ingest: applies
# the nixbot input's migrations to the nixbot database in lexical order, one
# transaction per file, as checks.x86_64-linux.devloop-queries does (design
# D14; Task 2's schema diff), then the test's baseline fixture rows.
# Usage: nixbot-schema.sh MIGRATIONS_DIR FIXTURES_SQL
set -euo pipefail
migrations=$1
fixtures=$2
for migration in "$migrations"/*.sql; do
  psql -X -q -v ON_ERROR_STOP=1 --single-transaction -d nixbot -f "$migration"
done
psql -X -q -v ON_ERROR_STOP=1 --single-transaction -d nixbot -f "$fixtures"

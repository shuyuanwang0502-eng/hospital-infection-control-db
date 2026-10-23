#!/usr/bin/env bash
# creates the schema, loads the data, runs the constraint tests and all queries
# connection settings come from PGHOST, PGUSER, PGPASSWORD etc.
# usage: bash scripts/run_all.sh [database_name]
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${1:-${PGDATABASE:-hospital_infection}}"
PSQL=(psql -X -v ON_ERROR_STOP=1 -d "$DB")

createdb "$DB" 2>/dev/null || true
echo "== creating schema in $DB";  "${PSQL[@]}" -q -f sql/01_schema.sql 2>&1 | grep -v NOTICE || true
echo "== loading csv data";                   "${PSQL[@]}" -q -f sql/02_load.sql
echo "== constraint tests";           "${PSQL[@]}" -q -f tests/constraint_tests.sql
echo "== queries";         "${PSQL[@]}" -f sql/03_queries.sql

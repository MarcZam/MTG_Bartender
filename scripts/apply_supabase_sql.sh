#!/usr/bin/env bash
set -euo pipefail

# apply_supabase_sql.sh
# Usage:
#   DATABASE_URL="postgres://..." ./scripts/apply_supabase_sql.sh
#
# This will run db/all.sql against the Postgres database pointed by DATABASE_URL.
# For Supabase, find the database connection string in Project Settings -> Database -> Connection string

SQL_FILE="$(dirname "$0")/../db/all.sql"

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: Please set DATABASE_URL env var to your Supabase database URL."
  echo "Get it from Supabase Project -> Settings -> Database -> Connection string (use the postgres connection)."
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "ERROR: psql is required but not installed. On macOS: brew install libpq && brew link --force libpq"
  exit 1
fi

echo "Applying SQL from $SQL_FILE to database..."

psql "$DATABASE_URL" -f "$SQL_FILE"

echo "Done."

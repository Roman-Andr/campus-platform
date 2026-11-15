#!/usr/bin/env bash
# Regenerates the API client from the server code (README, "Клиент API"):
# exports the OpenAPI schema of the FastAPI app to openapi/openapi.json and
# runs swagger_parser. Needs uv (backend/), Python and Flutter on PATH.
#
#   tool/generate_api.sh          # export the schema and generate
#   tool/generate_api.sh --check  # fail if either is out of date
set -euo pipefail

app="$(cd "$(dirname "$0")/.." && pwd)"
schema="$app/openapi/openapi.json"
generated="$app/lib/src/core/api/generated"

export_schema() {
  (cd "$app/../backend" &&
    uv run --frozen python "$app/tool/export_openapi.py" "$1")
}

accept_success_statuses() {
  python3 "$app/tool/accept_success_statuses.py" "$1" "$2"
}

cd "$app"
if [[ "${1:-}" == "--check" ]]; then
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  fresh="$work/openapi.json"
  export_schema "$fresh"
  if ! diff -q "$schema" "$fresh" >/dev/null; then
    echo "openapi/openapi.json is out of date: run tool/generate_api.sh" >&2
    exit 1
  fi
  fresh_generated="$work/generated"
  dart run swagger_parser --schema_path "$fresh" -o "$fresh_generated"
  accept_success_statuses "$fresh" "$fresh_generated"
  if ! diff -rq "$generated" "$fresh_generated" >/dev/null; then
    echo "generated API client is out of date: run tool/generate_api.sh" >&2
    diff -rq "$generated" "$fresh_generated" >&2 || true
    exit 1
  fi
else
  export_schema "$schema"
  dart run swagger_parser
  accept_success_statuses "$schema" "$generated"
fi

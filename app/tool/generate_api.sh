#!/usr/bin/env bash
# Regenerates the API client from the server code (README, "Клиент API"):
# exports the OpenAPI schema of the FastAPI app to openapi/openapi.json and
# runs swagger_parser. Needs uv (backend/) and Flutter on PATH.
#
#   tool/generate_api.sh          # export the schema and generate
#   tool/generate_api.sh --check  # fail if either is out of date
set -euo pipefail

app="$(cd "$(dirname "$0")/.." && pwd)"
schema="$app/openapi/openapi.json"

export_schema() {
  (cd "$app/../backend" &&
    uv run --frozen python "$app/tool/export_openapi.py" "$1")
}

cd "$app"
if [[ "${1:-}" == "--check" ]]; then
  fresh="$(mktemp)"
  trap 'rm -f "$fresh"' EXIT
  export_schema "$fresh"
  if ! diff -q "$schema" "$fresh" >/dev/null; then
    echo "openapi/openapi.json is out of date: run tool/generate_api.sh" >&2
    exit 1
  fi
  dart run swagger_parser --check
else
  export_schema "$schema"
  dart run swagger_parser
fi

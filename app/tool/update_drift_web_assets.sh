#!/usr/bin/env bash
# Downloads the sqlite3 WebAssembly module and the drift web worker into
# web/, matching the sqlite3 and drift versions resolved in pubspec.lock.
# Run after upgrading drift or sqlite3.
set -euo pipefail
cd "$(dirname "$0")/.."

locked_version() {
  awk -v pkg="  $1:" '$0 == pkg { found = 1 } found && /version:/ { gsub(/"/, "", $2); print $2; exit }' pubspec.lock
}

sqlite3_version="$(locked_version sqlite3)"
drift_version="$(locked_version drift)"
base="https://github.com/simolus3"

curl -fsSL -o web/sqlite3.wasm \
  "$base/sqlite3.dart/releases/download/sqlite3-$sqlite3_version/sqlite3.wasm"
curl -fsSL -o web/drift_worker.js \
  "$base/drift/releases/download/drift-$drift_version/drift_worker.js"
echo "sqlite3.wasm $sqlite3_version, drift_worker.js $drift_version"

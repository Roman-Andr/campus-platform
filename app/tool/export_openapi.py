"""Write the OpenAPI schema of the server for the client generator.

Run from backend/ in its environment (see tool/generate_api.sh):

    uv run --frozen python ../app/tool/export_openapi.py OUTPUT

The schema comes from the FastAPI application itself, not from a running
server. FastAPI describes optional values as ``anyOf: [T, {type: null}]``;
swagger_parser turns such unions into wrapper classes and skips operations
with nullable query parameters. The schema is therefore normalized:

- ``anyOf: [{type: T, ...}, {type: null}]`` becomes ``type: [T, null]``;
- ``anyOf: [{$ref: X}, {type: null}]`` becomes
  ``oneOf: [{$ref: X}, {type: null}]`` which the generator maps to ``X?``;
- query, header and cookie parameters lose ``null``: an absent parameter
  already means "no value".
"""

import json
import sys
from pathlib import Path
from typing import Any

from campus.api.app import create_app
from campus.core.config import Settings

NULL = {"type": "null"}


def _without_null(schema: dict[str, Any]) -> dict[str, Any] | None:
    """The non-null branch of ``anyOf: [T, null]``, or ``None``."""
    branches = schema.get("anyOf")
    if not isinstance(branches, list) or len(branches) != 2 or NULL not in branches:
        return None
    other = branches[0] if branches[1] == NULL else branches[1]
    return other if isinstance(other, dict) else None


def _nullable(schema: dict[str, Any]) -> dict[str, Any]:
    other = _without_null(schema)
    if other is None:
        return schema
    rest = {key: value for key, value in schema.items() if key != "anyOf"}
    if isinstance(other.get("type"), str):
        return {**other, **rest, "type": [other["type"], "null"]}
    return {**rest, "oneOf": [other, NULL]}


def _not_null(schema: dict[str, Any]) -> dict[str, Any]:
    other = _without_null(schema)
    if other is None:
        return schema
    rest = {key: value for key, value in schema.items() if key != "anyOf"}
    return {**other, **rest}


def normalize(node: Any) -> Any:
    """Return ``node`` with nullable unions rewritten, recursively."""
    if isinstance(node, list):
        return [normalize(item) for item in node]
    if not isinstance(node, dict):
        return node
    if node.get("in") in {"query", "header", "cookie"} and "schema" in node:
        node = {**node, "schema": _not_null(node["schema"])}
    else:
        node = _nullable(node)
    return {key: normalize(value) for key, value in node.items()}


def main() -> None:
    output = Path(sys.argv[1])
    # Defaults only: the schema must not depend on the local environment.
    schema = create_app(Settings(_env_file=None)).openapi()  # type: ignore[call-arg]
    text = json.dumps(normalize(schema), indent=2, ensure_ascii=False)
    output.write_text(text + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

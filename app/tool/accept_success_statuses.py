#!/usr/bin/env python3
"""Accept every declared 2xx response in the generated Dio client.

swagger_parser 2.1 supports one success payload in ``first_success`` mode and
selects the lowest exact 2xx status.  When several 2xx statuses describe the
same JSON schema, the other statuses are still successful responses and must
not become ``DioException`` values.  This script adds them to the generated
``validateStatus`` checks; it does not change payload decoding.
"""

from __future__ import annotations

import json
import re
import sys
from collections.abc import Iterator
from pathlib import Path
from typing import Any

HTTP_METHODS = {"delete", "get", "head", "options", "patch", "post", "put"}
STATUS = re.compile(r"^2\d\d$")


def json_schema(response: dict[str, Any]) -> Any:
    return response.get("content", {}).get("application/json", {}).get("schema")


def camel_case(operation_id: str) -> str:
    first, *rest = operation_id.split("_")
    return first + "".join(part[:1].upper() + part[1:] for part in rest)


def multi_success_operations(
    schema: dict[str, Any],
) -> Iterator[tuple[str, list[int]]]:
    for path_item in schema.get("paths", {}).values():
        for method, operation in path_item.items():
            if method not in HTTP_METHODS:
                continue
            responses = operation.get("responses", {})
            successes = sorted(
                (int(status), response)
                for status, response in responses.items()
                if STATUS.fullmatch(status)
            )
            if len(successes) < 2:
                continue
            first_schema = json_schema(successes[0][1])
            if first_schema is None:
                continue
            statuses = [
                status
                for status, response in successes
                if json_schema(response) == first_schema
            ]
            if len(statuses) > 1:
                yield camel_case(operation["operationId"]), statuses


def patch_client(operation: str, statuses: list[int], generated: Path) -> None:
    accepted = " || ".join(f"status == {status}" for status in statuses)
    declaration = re.compile(rf"Future<[^\n]+>\s+{re.escape(operation)}\(")
    check = re.compile(
        r"validateStatus: \(status\) => status != null && \(([^)]*)\)"
    )
    for path in generated.rglob("*.dart"):
        source = path.read_text()
        match = declaration.search(source)
        if match is None:
            continue
        end = source.find("\n  Future<", match.end())
        if end == -1:
            end = len(source)
        block = source[match.start() : end]
        existing = check.search(block)
        if existing is None:
            raise SystemExit(
                f"{path}: validateStatus not found for {operation}()"
            )
        if existing.group(1) == accepted:
            return
        replacement = (
            "validateStatus: (status) =>\n"
            f"          status != null && ({accepted})"
        )
        block = block[: existing.start()] + replacement + block[existing.end() :]
        path.write_text(source[: match.start()] + block + source[end:])
        return
    raise SystemExit(f"generated method {operation}() not found")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: accept_success_statuses.py SCHEMA GENERATED")
    schema_path, generated_path = map(Path, sys.argv[1:])
    schema = json.loads(schema_path.read_text())
    for operation, statuses in multi_success_operations(schema):
        patch_client(operation, statuses, generated_path)


if __name__ == "__main__":
    main()

"""Validate the design inventory against the current Flutter screen classes."""

import json
import re
from pathlib import Path


def main() -> None:
    design = Path(__file__).resolve().parent
    repo = design.parents[2]
    catalog = json.loads((design / "screen-catalog.json").read_text())
    snapshot = json.loads((design / "code-inventory.json").read_text())
    actual = set()
    for path in (repo / "app/lib/src/features").rglob("*.dart"):
        if not path.name.endswith(".g.dart"):
            actual.update(
                re.findall(r"^class ([A-Z]\w*Screen)\b", path.read_text(), re.MULTILINE)
            )
    mapped = set()
    ids = []
    required = [
        "id",
        "title",
        "entry",
        "layout",
        "primary",
        "secondary",
        "specialStates",
        "permissions",
        "components",
        "adaptive",
        "motion",
        "issue",
    ]
    for screen in catalog["screens"]:
        ids.append(screen["id"])
        missing = [field for field in required if not screen.get(field)]
        if missing:
            raise SystemExit(f"Incomplete screen {screen['id']}: {missing}")
        mapped.update(screen["sourceClasses"])
    if len(ids) != len(set(ids)):
        raise SystemExit("Duplicate screen IDs")
    if actual != mapped:
        raise SystemExit(
            f"Unmapped classes: {sorted(actual - mapped)}; stale mappings: {sorted(mapped - actual)}"
        )
    initial = {row["class"] for row in snapshot["publicScreenClasses"]}
    if not initial <= mapped:
        raise SystemExit(f"Missing initial classes: {sorted(initial - mapped)}")
    print(
        f"Verified {len(actual)} public screen classes across {len(ids)} design families."
    )


if __name__ == "__main__":
    main()

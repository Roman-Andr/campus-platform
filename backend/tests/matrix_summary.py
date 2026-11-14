"""Pytest acceptance report for collected role/action matrix probes."""

from collections import defaultdict

import pytest
from _pytest.terminal import TerminalReporter

from tests.role_action_matrix import COLUMNS, KNOWN_FAILURES, MATRIX, Case


def pytest_collection_modifyitems(items: list[pytest.Item]) -> None:
    for item in items:
        case = getattr(item, "callspec", None)
        if case is not None:
            value = case.params.get("case")
            if isinstance(value, Case):
                item.user_properties.append(("role_action_cell", value.cell))
                item.user_properties.append(("role_action_probe", value.probe))
                issue = value.issue or KNOWN_FAILURES.get(value.id)
                if issue:
                    item.user_properties.append(("role_action_issue", issue))


def pytest_terminal_summary(terminalreporter: TerminalReporter) -> None:
    checked: set[str] = set()
    deferred: dict[int, set[str]] = defaultdict(set)
    failed: set[str] = set()
    regressions: set[str] = set()
    for reports in terminalreporter.stats.values():
        for report in reports:
            if not isinstance(report, pytest.TestReport):
                continue
            props = dict(getattr(report, "user_properties", ()))
            cell = props.get("role_action_cell")
            if cell is None:
                continue
            if report.when == "call" and report.passed:
                checked.add(cell)
            elif report.failed:
                failed.add(cell)
            if report.skipped and getattr(report, "wasxfail", None):
                regressions.add(report.nodeid)
            if report.skipped and "role_action_issue" in props:
                deferred[int(props["role_action_issue"])].add(cell)
    if not checked and not deferred and not failed:
        return
    canonical = {cell for cell in checked if cell.split("/")[1] in COLUMNS}
    pending = set().union(*deferred.values()) if deferred else set()
    canonical_pending = {cell for cell in pending if cell.split("/")[1] in COLUMNS}
    terminalreporter.section("Role x action matrix (specification: 108 cells)")
    terminalreporter.write_line(
        f"API checked: {len(canonical)} cells; "
        f"alias cells checked: {len(checked - canonical)}; failed: {len(failed)}; "
        f"known failing probes: {len(regressions)}"
    )
    terminalreporter.write_line(
        f"Deferred: {len(canonical_pending)} cells "
        f"({len(canonical_pending & canonical)} also have API coverage)."
    )
    for action in MATRIX:
        checked_columns = sorted(
            c.split("/")[1] for c in canonical if c.startswith(action + "/")
        )
        pending_columns = sorted(
            c.split("/")[1] for c in canonical_pending if c.startswith(action + "/")
        )
        issues = sorted(
            issue
            for issue, cells in deferred.items()
            if any(c.startswith(action + "/") for c in cells)
        )
        terminalreporter.write_line(f"{action}: API [{', '.join(checked_columns)}]")
        if pending_columns or issues:
            terminalreporter.write_line(
                f"  marked [{', '.join(pending_columns)}]; "
                f"issues {', '.join(f'#{issue}' for issue in issues)}"
            )

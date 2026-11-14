"""Exercise the merge guard with real Git history and a fake GitHub CLI."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).parents[2] / ".github" / "scripts"


def run(cwd: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603
        args, cwd=cwd, capture_output=True, text=True, check=False
    )


def git(cwd: Path, *args: str) -> str:
    result = run(cwd, "git", *args)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def commit(repo: Path, path: str) -> str:
    file = repo / path
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text("change\n")
    git(repo, "add", path)
    git(repo, "commit", "-m", "test change")
    return git(repo, "rev-parse", "HEAD")


@pytest.fixture
def merge_repo(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    remote = tmp_path / "remote"
    remote.mkdir()
    git(remote, "init", "-b", "main")
    git(remote, "config", "user.name", "Test")
    git(remote, "config", "user.email", "test@example.invalid")
    commit(remote, "README.md")
    git(remote, "checkout", "-b", "feature")
    head = commit(remote, "backend/src/campus/migrations/versions/pr.py")
    git(remote, "checkout", "main")

    repo = tmp_path / "checkout"
    git(tmp_path, "clone", str(remote), str(repo))
    shutil.copytree(SCRIPTS, repo / "scripts")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    gh = bin_dir / "gh"
    gh.write_text(
        "#!/usr/bin/env bash\n"
        "set -eu\n"
        'case "$1 $2" in\n'
        '  "pr view") echo "$TEST_HEAD ${TEST_STATE:-OPEN} ${TEST_BASE:-main}" ;;\n'
        '  "repo view") echo owner/repo ;;\n'
        '  "api "*)\n'
        '    case "$2" in\n'
        '      *check_name=ci\\&*) echo "${TEST_CI:-success}" ;;\n'
        '      *check_name=pr-title\\&*) echo "${TEST_TITLE:-success}" ;;\n'
        "      *) exit 2 ;;\n"
        "    esac ;;\n"
        '  "pr merge") printf "%s\\n" "$@" > "$TEST_MERGE_LOG" ;;\n'
        "  *) exit 2 ;;\n"
        "esac\n"
    )
    gh.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")
    monkeypatch.setenv("TEST_HEAD", head)
    monkeypatch.setenv("TEST_MERGE_LOG", str(repo / "merged"))
    return repo


@pytest.mark.parametrize(
    ("main_path", "update_branch", "allowed"),
    [
        (None, False, True),
        ("docs/new.md", False, True),
        ("backend/src/campus/migrations/versions/main.py", False, False),
        ("backend/src/campus/migrations/env.py", False, False),
        ("backend/src/campus/migrations/versions/main.py", True, True),
    ],
)
def test_merge_checks_migrations_since_common_ancestor(
    merge_repo: Path,
    monkeypatch: pytest.MonkeyPatch,
    main_path: str | None,
    update_branch: bool,
    allowed: bool,
) -> None:
    remote = merge_repo.parent / "remote"
    if main_path:
        commit(remote, main_path)
    if update_branch:
        git(remote, "checkout", "feature")
        git(remote, "merge", "main", "--no-edit")
        monkeypatch.setenv("TEST_HEAD", git(remote, "rev-parse", "HEAD"))

    result = run(merge_repo, "bash", "scripts/merge-pr.sh", "206")

    assert (result.returncode == 0) == allowed, result.stdout + result.stderr
    if allowed:
        assert (merge_repo / "merged").read_text().splitlines() == [
            "pr",
            "merge",
            "206",
            "--squash",
            "--match-head-commit",
            os.environ["TEST_HEAD"],
        ]
    else:
        assert "main has migration changes missing" in result.stderr
        assert not (merge_repo / "merged").exists()


@pytest.mark.parametrize(
    ("variable", "value"),
    [
        ("TEST_CI", "failure"),
        ("TEST_CI", "in_progress"),
        ("TEST_TITLE", "failure"),
        ("TEST_TITLE", "missing"),
        ("TEST_STATE", "CLOSED"),
        ("TEST_BASE", "release"),
    ],
)
def test_merge_preserves_required_checks_and_pr_state(
    merge_repo: Path, monkeypatch: pytest.MonkeyPatch, variable: str, value: str
) -> None:
    monkeypatch.setenv(variable, value)

    result = run(merge_repo, "bash", "scripts/merge-pr.sh", "206")

    assert result.returncode != 0
    assert not (merge_repo / "merged").exists()

"""The import-linter contracts in pyproject.toml catch boundary violations."""

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

BACKEND = Path(__file__).parents[1]
LINT_IMPORTS = Path(sys.executable).with_name("lint-imports")

# An internal submodule of the points module, present in every check.
INTERNAL = {"campus/modules/points/ledger.py": '"""Internal."""\n'}


def lint_imports(
    tmp_path: Path, files: dict[str, str]
) -> subprocess.CompletedProcess[str]:
    """Run import-linter on a copy of the code with ``files`` added."""
    shutil.copytree(BACKEND / "src", tmp_path / "src")
    shutil.copy(BACKEND / "pyproject.toml", tmp_path)
    for path, code in (INTERNAL | files).items():
        (tmp_path / "src" / path).write_text(code)
    return subprocess.run(  # noqa: S603
        [LINT_IMPORTS, "--no-cache"],
        cwd=tmp_path,
        env={"PYTHONPATH": str(tmp_path / "src")},
        capture_output=True,
        text=True,
        check=False,
    )


def test_module_may_import_public_interface_of_another(tmp_path: Path) -> None:
    result = lint_imports(
        tmp_path,
        {"campus/modules/listings/rules.py": "import campus.modules.points\n"},
    )

    assert result.returncode == 0, result.stdout


@pytest.mark.parametrize(
    ("path", "code", "violation"),
    [
        pytest.param(
            "campus/modules/listings/rules.py",
            "from campus.modules.points import ledger\n",
            "campus.modules.listings.rules -> campus.modules.points.ledger",
            id="module-imports-internals-of-another",
        ),
        pytest.param(
            "campus/api/routes.py",
            "from campus.modules.points import ledger\n",
            "campus.api.routes -> campus.modules.points.ledger",
            id="process-imports-module-internals",
        ),
        pytest.param(
            "campus/core/helpers.py",
            "import campus.modules.points\n",
            "campus.core.helpers -> campus.modules.points",
            id="kernel-imports-module",
        ),
        pytest.param(
            "campus/modules/points/views.py",
            "import campus.api.app\n",
            "campus.modules.points.views -> campus.api.app",
            id="module-imports-process",
        ),
    ],
)
def test_boundary_violation_breaks_contracts(
    tmp_path: Path, path: str, code: str, violation: str
) -> None:
    result = lint_imports(tmp_path, {path: code})

    assert result.returncode != 0
    assert violation in result.stdout

from __future__ import annotations

import ast
from pathlib import Path

import notelore

CORE = Path(notelore.__file__).parent


def test_the_core_never_imports_an_app() -> None:
    """Apps import the core, never the reverse: the mobile app ships the core without the CLI."""
    offenders = []
    for source in CORE.rglob("*.py"):
        for node in ast.walk(ast.parse(source.read_text(encoding="utf-8"))):
            names = (
                [a.name for a in node.names]
                if isinstance(node, ast.Import)
                else [node.module or ""]
                if isinstance(node, ast.ImportFrom)
                else []
            )
            offenders += [f"{source.name}: {n}" for n in names if n.split(".")[0] == "notelore_cli"]
    assert offenders == []


def test_core_and_app_versions_move_together() -> None:
    import notelore_cli

    assert notelore.__version__ == notelore_cli.__version__

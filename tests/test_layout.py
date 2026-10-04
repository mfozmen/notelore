from __future__ import annotations

import ast
import re
import sys
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


# What the core may import at module level: these must install on Android and iOS
# (#48). The LLM providers speak plain HTTPS (#51); the Drive libraries are imported
# lazily inside the function that needs them and come from the core's "desktop" extra.
MOBILE_SAFE = {"yaml", "platformdirs", "certifi"}
DESKTOP_ONLY_MODULES = {"secrets.py": {"keyring"}}  # until the secrets backend lands (#52)


def test_the_core_imports_only_mobile_safe_packages_at_module_level() -> None:
    offenders = []
    for source in CORE.rglob("*.py"):
        allowed = MOBILE_SAFE | DESKTOP_ONLY_MODULES.get(source.name, set())
        for node in ast.parse(source.read_text(encoding="utf-8")).body:
            names = (
                [a.name for a in node.names]
                if isinstance(node, ast.Import)
                else [node.module or ""]
                if isinstance(node, ast.ImportFrom) and node.level == 0
                else []
            )
            for name in names:
                top = name.split(".")[0]
                if top in sys.stdlib_module_names or top in {"__future__", "notelore"}:
                    continue
                if top not in allowed:
                    offenders.append(f"{source.relative_to(CORE)}: {name}")
    assert offenders == []


def test_the_core_base_install_has_only_mobile_safe_dependencies() -> None:
    import tomllib

    project = tomllib.loads((CORE.parents[1] / "pyproject.toml").read_text(encoding="utf-8"))[
        "project"
    ]
    base = {re.split(r"[<>=~!\[ ]", dep, maxsplit=1)[0].lower() for dep in project["dependencies"]}
    assert base == {"certifi", "platformdirs", "pyyaml"}
    assert "desktop" in project["optional-dependencies"]


def test_the_mobile_app_installs_exactly_the_core_base_dependencies() -> None:
    """Briefcase ships the core as source; its requirements are listed by hand, keep them equal."""
    import tomllib

    core = tomllib.loads((CORE.parents[1] / "pyproject.toml").read_text(encoding="utf-8"))
    mobile = tomllib.loads(
        (CORE.parents[3] / "apps" / "mobile" / "pyproject.toml").read_text(encoding="utf-8")
    )
    requires = mobile["tool"]["briefcase"]["app"]["notelore-mobile"]["requires"]
    assert sorted(requires) == sorted(core["project"]["dependencies"])

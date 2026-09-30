"""Console entry point for ``notelore``."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

from notelore import __version__, update


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="notelore", description="Talk to your notes.")
    parser.add_argument("--version", action="version", version=f"notelore {__version__}")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("update", help="download and install the latest release")
    args = parser.parse_args(argv)

    if getattr(sys, "frozen", False):  # a PyInstaller build may have left its previous self behind
        update.cleanup(Path(sys.executable))
    if args.command == "update":
        return update.run_update()

    hint = update.hint()
    if hint:
        print(hint)
    from notelore import repl  # lazy: --version and update stay instant

    return repl.run()

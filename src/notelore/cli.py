"""Console entry point for ``notelore``."""

from __future__ import annotations

import argparse
from collections.abc import Sequence

from notelore import __version__


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="notelore", description="Talk to your notes.")
    parser.add_argument("--version", action="version", version=f"notelore {__version__}")
    parser.parse_args(argv)
    print("Notelore is not ready yet. See docs/PLAN.md.")
    return 0

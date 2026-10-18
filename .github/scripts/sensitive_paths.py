"""Which files of a PR call for the security pass (claude-review.yml).

The paths the security-reviewer agent covers: auth, providers, sync, the app
lock, the updater, platform manifests, dependencies, workflows and the CI
scripts that gate them. Writes `files` (one per line) and `touched` (true or
false) to GITHUB_OUTPUT.

Standard library only. Tests: .github/scripts/test_sensitive_paths.py.
"""

import os
import subprocess
import sys
from fnmatch import fnmatchcase
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from review_range import write_outputs  # noqa: E402

# fnmatch's * also crosses "/", so "*auth*.dart" matches in any folder.
PATTERNS = (
    "packages/notelore_core/lib/src/providers/*",
    "packages/notelore_core/lib/src/sync/*",
    "*/lib/src/secret.dart",
    "*/lib/src/lock*.dart",
    "*/lib/src/update.dart",
    "*/lib/*auth*.dart",
    "*/AndroidManifest.xml",
    "*/Info.plist",
    "*.entitlements",
    "pubspec.yaml",
    "*/pubspec.yaml",
    "pubspec.lock",
    ".github/workflows/*",
    ".github/scripts/*",
)


def sensitive(files):
    """The files, in order, that match a sensitive pattern."""
    return [f for f in files if any(fnmatchcase(f, pattern) for pattern in PATTERNS)]


def main():
    base = os.environ.get("BASE_REF", "origin/main")
    # NUL-separated, so a name with spaces stays one name.
    changed = subprocess.run(
        ["git", "diff", "-z", "--name-only", f"{base}...HEAD"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split("\0")
    found = sensitive([f for f in changed if f])
    print(f"{len(found)} of {len(changed) - 1} changed file(s) are sensitive")
    # review_range's writer: a random heredoc delimiter no file name can close.
    write_outputs(
        os.environ["GITHUB_OUTPUT"],
        {"files": "\n".join(found) + "\n", "touched": "true" if found else "false"},
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

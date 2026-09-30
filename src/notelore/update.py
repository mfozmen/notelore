"""Update check and self-update against GitHub Releases.

The check runs at most once a day, is cached in the state dir and never blocks or
fails startup when offline. ``notelore update`` swaps the running executable of a
PyInstaller build in place; a PyPI/uv install gets the ``uv tool upgrade`` hint.
"""

from __future__ import annotations

import contextlib
import io
import json
import platform
import sys
import time
import urllib.request
import zipfile
from collections.abc import Callable
from pathlib import Path

from notelore import __version__, paths

API = "https://api.github.com/repos/mfozmen/notelore/releases/latest"
CHECK_INTERVAL = 24 * 3600

Fetch = Callable[[str], bytes]


def _fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=3) as response:  # runs at startup: stay short
        return bytes(response.read())


def is_newer(candidate: str, current: str) -> bool:
    """Numeric compare; anything unparsable (a pre-release tag, a garbled cache) is not newer."""
    try:
        return tuple(map(int, candidate.split("."))) > tuple(map(int, current.split(".")))
    except ValueError:
        return False


def asset_name(version: str, system: str, machine: str) -> str:
    """Release asset for this OS/arch, as release.yml names them."""
    key = (system, machine.lower())
    if key == ("Windows", "amd64"):
        return f"notelore-{version}-windows-x64.zip"
    if key == ("Darwin", "arm64"):
        return f"notelore-{version}-macos-arm64.zip"
    raise ValueError(f"no prebuilt executable for {system}/{machine}")


def latest(fetch: Fetch = _fetch) -> tuple[str, dict[str, str]]:
    """Latest release version and its assets as {name: download url}."""
    data = json.loads(fetch(API))
    version = str(data["tag_name"]).removeprefix("v")
    return version, {a["name"]: a["browser_download_url"] for a in data["assets"]}


def check(cache: Path, now: float, current: str, fetch: Fetch = _fetch) -> str | None:
    """Newest version if newer than ``current``, else None. Fetches at most once a day."""
    try:
        state = json.loads(cache.read_text(encoding="utf-8"))
        version = str(state["version"])
        fresh = now - float(state["checked_at"]) < CHECK_INTERVAL
    except (OSError, ValueError, KeyError, TypeError):
        fresh = False
    if not fresh:
        try:
            version, _ = latest(fetch)
        except (OSError, ValueError, KeyError, TypeError):
            return None  # offline or a garbled response: try again next time
        try:
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_text(json.dumps({"version": version, "checked_at": now}), encoding="utf-8")
        except OSError:
            pass  # read-only or full state dir: the check just repeats next start
    return version if is_newer(version, current) else None


def hint(fetch: Fetch = _fetch) -> str | None:
    """One-line startup hint when a newer release exists."""
    newer = check(paths.state_dir() / "update-check.json", time.time(), __version__, fetch)
    if newer is None:
        return None
    return f"Notelore {newer} is available (you have {__version__}). Run: notelore update"


def apply(exe: Path, system: str, machine: str, fetch: Fetch = _fetch) -> str | None:
    """Replace ``exe`` with the latest release build; the new version, or None if current."""
    version, assets = latest(fetch)
    if not is_newer(version, __version__):
        return None
    archive = zipfile.ZipFile(io.BytesIO(fetch(assets[asset_name(version, system, machine)])))
    new = exe.with_suffix(".new")
    new.write_bytes(archive.read(archive.namelist()[0]))
    new.chmod(0o755)
    # A running executable can be renamed on every OS, but not overwritten on Windows.
    old = exe.with_suffix(".old")
    try:
        exe.replace(old)
    except OSError:
        new.unlink(missing_ok=True)  # a stale .old still locked: leave no download behind
        raise
    try:
        new.replace(exe)
    except OSError:
        old.replace(exe)  # never leave the user without an executable
        raise
    return version


def cleanup(exe: Path) -> None:
    """Remove the previous executable left behind by :func:`apply`."""
    # Still held by another process or antivirus: retried on the next start.
    with contextlib.suppress(OSError):
        exe.with_suffix(".old").unlink(missing_ok=True)


def run_update(fetch: Fetch = _fetch) -> int:
    """The ``notelore update`` command."""
    if not getattr(sys, "frozen", False):
        print("This is a Python install. Update with: uv tool upgrade notelore")
        return 0
    try:
        version = apply(Path(sys.executable), platform.system(), platform.machine(), fetch)
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as exc:
        print(f"Update failed: {exc}", file=sys.stderr)
        return 1
    print(f"Updated to {version}." if version else f"Already up to date ({__version__}).")
    return 0

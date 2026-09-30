from __future__ import annotations

import hashlib
import io
import json
import sys
import zipfile
from pathlib import Path
from typing import Any

import pytest

from notelore import __version__, update

API = update.API
V = "9.9.9"


def release(version: str = V) -> bytes:
    zips = [f"notelore-{version}-windows-x64.zip", f"notelore-{version}-macos-arm64.zip"]
    names = zips + [f"{z}.sha256" for z in zips]
    return json.dumps(
        {
            "tag_name": f"v{version}",
            "assets": [{"name": n, "browser_download_url": f"https://dl/{n}"} for n in names],
        }
    ).encode()


def zipped(member: str, content: bytes) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr(member, content)
    return buf.getvalue()


def download(name: str, member: str, content: bytes, digest: str | None = None) -> dict[str, bytes]:
    """The zip download for ``name`` plus its published ``.sha256`` (sha256sum format)."""
    data = zipped(member, content)
    digest = digest or hashlib.sha256(data).hexdigest()
    return {
        f"https://dl/{name}": data,
        f"https://dl/{name}.sha256": f"{digest}  {name}\n".encode(),
    }


class Fetch:
    def __init__(self, pages: dict[str, bytes]) -> None:
        self.pages, self.calls = pages, 0

    def __call__(self, url: str) -> bytes:
        self.calls += 1
        if url not in self.pages:
            raise OSError(f"offline: {url}")
        return self.pages[url]


def test_is_newer_compares_numerically() -> None:
    assert update.is_newer("0.10.0", "0.9.1")
    assert not update.is_newer("0.9.1", "0.9.1")
    assert not update.is_newer("0.9.1", "0.10.0")


@pytest.mark.parametrize(
    ("system", "machine", "name"),
    [
        ("Windows", "AMD64", "notelore-1.0.0-windows-x64.zip"),
        ("Darwin", "arm64", "notelore-1.0.0-macos-arm64.zip"),
    ],
)
def test_asset_name_per_platform(system: str, machine: str, name: str) -> None:
    assert update.asset_name("1.0.0", system, machine) == name


def test_asset_name_unsupported_platform() -> None:
    with pytest.raises(ValueError, match="no prebuilt"):
        update.asset_name("1.0.0", "Linux", "x86_64")


def test_latest_parses_the_release() -> None:
    version, assets = update.latest(Fetch({API: release()}))
    assert version == V
    assert assets[f"notelore-{V}-windows-x64.zip"] == f"https://dl/notelore-{V}-windows-x64.zip"


def test_check_fetches_once_a_day_and_reports_newer(tmp_path: Path) -> None:
    fetch = Fetch({API: release()})
    cache = tmp_path / "update-check.json"
    assert update.check(cache, now=1000.0, current="0.1.0", fetch=fetch) == V
    assert update.check(cache, now=1000.0 + 3600, current="0.1.0", fetch=fetch) == V
    assert fetch.calls == 1
    assert update.check(cache, now=1000.0 + 90000, current="0.1.0", fetch=fetch) == V
    assert fetch.calls == 2
    assert update.check(cache, now=1000.0 + 90000, current=V, fetch=fetch) is None


def test_check_is_silent_offline_and_on_a_corrupt_cache(tmp_path: Path) -> None:
    cache = tmp_path / "update-check.json"
    assert update.check(cache, now=1.0, current="0.1.0", fetch=Fetch({})) is None
    cache.write_text("{not json", encoding="utf-8")
    assert update.check(cache, now=1.0, current="0.1.0", fetch=Fetch({API: release()})) == V


def test_hint_uses_the_state_dir(notelore_home: Path) -> None:
    assert update.hint(fetch=Fetch({API: release()})) == (
        f"Notelore {V} is available (you have {__version__}). Run: notelore update"
    )
    cache = notelore_home / "state" / "update-check.json"
    assert cache.exists()
    cache.unlink()  # a fresh check, not the cached 9.9.9
    assert update.hint(fetch=Fetch({API: release(__version__)})) is None


def test_fetch_is_a_plain_http_get(monkeypatch: pytest.MonkeyPatch) -> None:
    class Response(io.BytesIO):
        def __enter__(self) -> Response:
            return self

        def __exit__(self, *exc: object) -> None:
            self.close()

    seen: list[tuple[str, float]] = []

    def urlopen(url: str, timeout: float) -> Response:
        seen.append((url, timeout))
        return Response(b"body")

    monkeypatch.setattr("urllib.request.urlopen", urlopen)
    assert update._fetch("https://x/") == b"body"
    assert seen == [("https://x/", 3)]  # short: this runs at startup


def test_apply_replaces_the_executable_and_keeps_the_old_one(tmp_path: Path) -> None:
    exe = tmp_path / "notelore.exe"
    exe.write_bytes(b"old")
    name = f"notelore-{V}-windows-x64.zip"
    fetch = Fetch({API: release(), **download(name, "notelore.exe", b"new")})
    assert update.apply(exe, "Windows", "AMD64", fetch=fetch) == V
    assert exe.read_bytes() == b"new"
    assert exe.with_suffix(".old").read_bytes() == b"old"
    assert not exe.with_suffix(".new").exists()


@pytest.mark.parametrize(
    ("pages", "message"),
    [
        (lambda n: download(n, "notelore.exe", b"new", digest="0" * 64), "checksum mismatch"),
        (lambda n: download(n, "evil.exe", b"new"), "has no notelore.exe"),
        (
            lambda n: {**download(n, "notelore.exe", b"new"), f"https://dl/{n}.sha256": b" \n"},
            "empty",
        ),
    ],
    ids=["tampered", "wrong-member", "empty-checksum"],
)
def test_apply_refuses_an_unverified_download(tmp_path: Path, pages: Any, message: str) -> None:
    exe = tmp_path / "notelore.exe"
    exe.write_bytes(b"old")
    name = f"notelore-{V}-windows-x64.zip"
    fetch = Fetch({API: release(), **pages(name)})
    with pytest.raises(ValueError, match=message):
        update.apply(exe, "Windows", "AMD64", fetch=fetch)
    assert exe.read_bytes() == b"old"
    assert not exe.with_suffix(".new").exists()


def test_apply_refuses_a_release_without_checksums(tmp_path: Path) -> None:
    exe = tmp_path / "notelore.exe"
    exe.write_bytes(b"old")
    name = f"notelore-{V}-windows-x64.zip"
    unsigned = json.dumps(
        {
            "tag_name": f"v{V}",
            "assets": [{"name": name, "browser_download_url": f"https://dl/{name}"}],
        }
    ).encode()
    fetch = Fetch({API: unsigned, **download(name, "notelore.exe", b"new")})
    with pytest.raises(ValueError, match="publishes no checksum"):
        update.apply(exe, "Windows", "AMD64", fetch=fetch)
    assert exe.read_bytes() == b"old"


def test_apply_names_the_missing_build(tmp_path: Path) -> None:
    exe = tmp_path / "notelore.exe"
    exe.write_bytes(b"old")
    mac = f"notelore-{V}-macos-arm64.zip"
    only_mac = json.dumps(
        {"tag_name": f"v{V}", "assets": [{"name": mac, "browser_download_url": "u"}]}
    ).encode()
    fetch = Fetch({API: only_mac})
    with pytest.raises(ValueError, match=f"release {V} has no notelore-{V}-windows-x64.zip"):
        update.apply(exe, "Windows", "AMD64", fetch=fetch)
    assert exe.read_bytes() == b"old"


def test_apply_when_already_current(tmp_path: Path) -> None:
    exe = tmp_path / "notelore"
    exe.write_bytes(b"same")
    fetch = Fetch({API: release(__version__)})
    assert update.apply(exe, "Darwin", "arm64", fetch=fetch) is None
    assert exe.read_bytes() == b"same"


def test_run_update_outside_a_frozen_build_prints_the_uv_hint(
    capsys: pytest.CaptureFixture[str],
) -> None:
    assert update.run_update(fetch=Fetch({})) == 0
    assert "uv tool upgrade notelore" in capsys.readouterr().out


def test_run_update_in_a_frozen_build(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    exe = tmp_path / "notelore"
    exe.write_bytes(b"old")
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setattr(sys, "executable", str(exe))
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("platform.machine", lambda: "arm64")
    name = f"notelore-{V}-macos-arm64.zip"
    fetch = Fetch({API: release(), **download(name, "notelore", b"new")})
    assert update.run_update(fetch=fetch) == 0
    assert f"Updated to {V}" in capsys.readouterr().out
    assert exe.read_bytes() == b"new"
    monkeypatch.setattr("notelore.update.__version__", V)  # what the swapped-in binary reports
    assert update.run_update(fetch=Fetch({API: release(V)})) == 0
    assert "Already up to date" in capsys.readouterr().out
    assert update.run_update(fetch=Fetch({})) == 1
    assert "Update failed" in capsys.readouterr().err


def test_cleanup_removes_the_previous_executable(tmp_path: Path) -> None:
    old = tmp_path / "notelore.old"
    old.write_bytes(b"old")
    update.cleanup(tmp_path / "notelore.exe")
    assert not old.exists()
    update.cleanup(tmp_path / "notelore.exe")  # nothing left: still fine


def test_prerelease_or_garbled_versions_never_crash_the_check(tmp_path: Path) -> None:
    assert not update.is_newer("0.2.0-rc1", "0.1.0")
    fetch = Fetch({API: release("0.2.0-rc1")})
    assert update.check(tmp_path / "c.json", now=1.0, current="0.1.0", fetch=fetch) is None


def test_check_survives_an_unwritable_cache(tmp_path: Path) -> None:
    (tmp_path / "file").write_bytes(b"")
    cache = tmp_path / "file" / "c.json"  # parent is a file: mkdir fails
    assert update.check(cache, now=1.0, current="0.1.0", fetch=Fetch({API: release()})) == V


def test_apply_rolls_back_when_the_new_binary_cannot_move_in(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    exe = tmp_path / "notelore.exe"
    exe.write_bytes(b"old")
    original = Path.replace

    def replace(self: Path, target: Path) -> Path:
        if self.suffix == ".new":
            raise PermissionError("locked")
        return original(self, target)

    monkeypatch.setattr(Path, "replace", replace)
    name = f"notelore-{V}-windows-x64.zip"
    fetch = Fetch({API: release(), **download(name, "notelore.exe", b"new")})
    with pytest.raises(PermissionError):
        update.apply(exe, "Windows", "AMD64", fetch=fetch)
    assert exe.read_bytes() == b"old"
    assert not exe.with_suffix(".old").exists()


def test_cleanup_tolerates_a_locked_old_executable(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    old = tmp_path / "notelore.old"
    old.write_bytes(b"old")

    def unlink(self: Path, missing_ok: bool = False) -> None:
        raise PermissionError("held by another process")

    monkeypatch.setattr(Path, "unlink", unlink)
    update.cleanup(tmp_path / "notelore.exe")  # must not raise: retried next start


def test_apply_removes_the_download_when_the_running_binary_cannot_be_renamed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    exe = tmp_path / "notelore.exe"
    exe.write_bytes(b"old")
    original = Path.replace

    def replace(self: Path, target: Path) -> Path:
        if self == exe:
            raise PermissionError("locked")
        return original(self, target)

    monkeypatch.setattr(Path, "replace", replace)
    name = f"notelore-{V}-windows-x64.zip"
    fetch = Fetch({API: release(), **download(name, "notelore.exe", b"new")})
    with pytest.raises(PermissionError):
        update.apply(exe, "Windows", "AMD64", fetch=fetch)
    assert exe.read_bytes() == b"old"
    assert not exe.with_suffix(".new").exists()

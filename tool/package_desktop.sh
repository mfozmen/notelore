#!/usr/bin/env bash
# Packages a built desktop app: the installer (Windows setup.exe, macOS .dmg)
# and its .sha256 (sha256sum format, LF). Used by the release workflow and, to
# check the packaging on every PR, by flutter.yml.
#
#   tool/package_desktop.sh <version> <out-dir> <Release|Debug> [<app-path>] [<arch>]
#
# The optional app path and architecture package a thinned macOS bundle;
# without them the whole build is used.
# Run from the repo root after `flutter build windows|macos`. Windows needs
# Inno Setup 6 (choco install innosetup).
set -euo pipefail

version=$1
mkdir -p "$2"
out=$(cd "$2" && pwd)
mode=$3
app=apps/notelore
given_bundle=${4:-}
arch=${5:-}

checksum() {
  (cd "$out" && if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi > "$1.sha256")
}

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    built="$(pwd)/$app/build/windows/x64/runner/$mode" # absolute: iscc resolves paths from the .iss
    setup="notelore-app-$version-windows-x64-setup"
    # MSYS_NO_PATHCONV: Git Bash would turn the /D, /O and /F flags into paths.
    MSYS_NO_PATHCONV=1 "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" /Q \
      "/DAppVersion=$version" "/DSourceDir=$(cygpath -w "$built")" \
      "/O$(cygpath -w "$out")" "/F$setup" "$(cygpath -w "$app/windows/installer/notelore.iss")"
    checksum "$setup.exe"
    ;;
  Darwin)
    bundle="${given_bundle:-$app/build/macos/Build/Products/$mode/notelore.app}"
    stage=$(mktemp -d)
    ditto "$bundle" "$stage/notelore.app" # keeps the bundle's symlinks and permissions
    ln -s /Applications "$stage/Applications" # drag the app onto it to install
    dmg="notelore-app-$version-macos${arch:+-$arch}.dmg"
    hdiutil create -quiet -volname Notelore -srcfolder "$stage" -ov -format UDZO "$out/$dmg"
    checksum "$dmg"
    ;;
  *)
    echo "no desktop package for $(uname -s)" >&2
    exit 1
    ;;
esac
ls -l "$out"

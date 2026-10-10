#!/usr/bin/env bash
# Packages a built desktop app: the installer (Windows setup.exe, macOS .dmg)
# plus the zip the 0.3.x updater looks for, each with a .sha256 (sha256sum
# format, LF). Used by the release workflow and, to check the packaging on
# every PR, by flutter.yml.
#
#   tool/package_desktop.sh <version> <out-dir> <Release|Debug>
#
# Run from the repo root after `flutter build windows|macos`. Windows needs
# Inno Setup 6 (choco install innosetup).
set -euo pipefail

version=$1
mkdir -p "$2"
out=$(cd "$2" && pwd)
mode=$3
app=apps/notelore

checksum() {
  (cd "$out" && if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi > "$1.sha256")
}

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    built="$app/build/windows/x64/runner/$mode"
    setup="notelore-app-$version-windows-x64-setup"
    # MSYS_NO_PATHCONV: Git Bash would turn the /D, /O and /F flags into paths.
    MSYS_NO_PATHCONV=1 "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" /Q \
      "/DAppVersion=$version" "/DSourceDir=$(cygpath -w "$built")" \
      "/O$(cygpath -w "$out")" "/F$setup" "$(cygpath -w "$app/windows/installer/notelore.iss")"
    checksum "$setup.exe"
    # shortcut: the zip only serves the 0.3.x updater; drop it once nobody runs 0.3.x.
    zip="notelore-app-$version-windows-x64.zip"
    (cd "$built" && 7z a -tzip "$(cygpath -w "$out/$zip")" . > /dev/null)
    checksum "$zip"
    ;;
  Darwin)
    bundle="$app/build/macos/Build/Products/$mode/notelore.app"
    stage=$(mktemp -d)
    cp -R "$bundle" "$stage/"
    ln -s /Applications "$stage/Applications" # drag the app onto it to install
    dmg="notelore-app-$version-macos.dmg"
    hdiutil create -quiet -volname Notelore -srcfolder "$stage" -ov -format UDZO "$out/$dmg"
    checksum "$dmg"
    zip="notelore-app-$version-macos.zip" # for the 0.3.x updater, see above
    ditto -c -k --keepParent "$bundle" "$out/$zip"
    checksum "$zip"
    ;;
  *)
    echo "no desktop package for $(uname -s)" >&2
    exit 1
    ;;
esac
ls -l "$out"

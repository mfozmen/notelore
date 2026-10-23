#!/usr/bin/env bash
# Thins a universal macOS .app to one architecture and signs it ad hoc, so the
# release can ship a smaller dmg per Mac. The release key for the app bundle is
# not affected: the update checksum/signature covers the dmg.
#
#   tool/thin_macos_app.sh <path/to/notelore.app> <arm64|x86_64>
set -euo pipefail

app=$1
arch=$2
main="$app/Contents/MacOS/notelore"
[ -f "$main" ] || { echo "no $main" >&2; exit 1; }

while IFS= read -r -d '' file; do
  case "$(file -b "$file")" in
    *Mach-O*) ;;
    *) continue ;;
  esac
  archs=$(lipo -archs "$file")
  if [ "$archs" = "$arch" ]; then
    continue
  fi
  if ! printf '%s\n' "$archs" | tr ' ' '\n' | grep -qx "$arch"; then
    echo "no $arch slice in $file ($archs)" >&2
    exit 1
  fi
  lipo -thin "$arch" "$file" -output "$file.thin"
  mv "$file.thin" "$file"
done < <(find "$app" -type f -print0)

# Thinning invalidates the bundle's signature; ad-hoc is what the unsigned
# development app already has, and macOS 14 accepts it with the user's Open.
root=$(cd "$(dirname "$0")/.." && pwd)
entitlements="$root/apps/notelore/macos/Runner/Release.entitlements"
args=(--force --deep --sign -)
[ -f "$entitlements" ] && args+=(--entitlements "$entitlements")
codesign "${args[@]}" "$app"
codesign --verify --deep --strict "$app"
got=$(lipo -archs "$main")
[ "$got" = "$arch" ] || { echo "thinned main binary is $got, not $arch" >&2; exit 1; }

#!/usr/bin/env bash
# Thin a universal macOS .app to one architecture and ad-hoc sign it, so each
# Mac gets a smaller dmg; the dmg's update checksum/signature is unaffected.
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

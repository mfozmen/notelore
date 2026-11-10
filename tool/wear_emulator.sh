#!/usr/bin/env bash
# The Wear OS emulator for the watch app (docs/wear-os.md), apart from the phone AVD.
# Every adb call names the watch's serial, so the phone emulator (emulator-5554) is never touched.
#   bash tool/wear_emulator.sh create | start | install | shot <file.png> | tap <x> <y> | stop
set -euo pipefail

avd=notelore_wear_api34
port=5560
serial="emulator-$port"
image='system-images;android-34;android-wear;x86_64'
apk=apps/notelore/build/wear/outputs/apk/debug/wear-debug.apk

if [ -z "${ANDROID_HOME:-}" ]; then
  case "$(uname -s)" in
    Darwin) ANDROID_HOME="$HOME/Library/Android/sdk" ;;
    Linux) ANDROID_HOME="$HOME/Android/Sdk" ;;
    *) ANDROID_HOME="$(cygpath -u "$LOCALAPPDATA")/Android/Sdk" ;;
  esac
fi
tools="$ANDROID_HOME/cmdline-tools/latest/bin"
bat=""
[ -f "$tools/avdmanager.bat" ] && bat=.bat
adb() { "$ANDROID_HOME/platform-tools/adb" -s "$serial" "$@"; }

case "${1:-}" in
  create)
    # Through a file: cmd.exe splits a .bat argument at the semicolons in the package name.
    list="$(mktemp)"
    echo "$image" > "$list"
    [ -n "$bat" ] && list="$(cygpath -w "$list")"
    "$tools/sdkmanager$bat" --package_file="$list"
    echo no | "$tools/avdmanager$bat" create avd -n "$avd" -k "$image" -d wearos_large_round
    ;;
  start)
    "$ANDROID_HOME/emulator/emulator" -avd "$avd" -port "$port" -no-window -no-audio -no-boot-anim \
      -gpu swiftshader_indirect >/dev/null 2>&1 &
    adb wait-for-device
    until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done
    echo "$serial booted"
    ;;
  install)
    adb install -r "$apk"
    adb shell am start -n io.github.mfozmen.notelore/io.github.mfozmen.notelore.wear.MainActivity
    ;;
  shot)
    adb exec-out screencap -p > "${2:?file.png}"
    ;;
  tap)
    adb shell input tap "${2:?x}" "${3:?y}"
    ;;
  stop)
    adb emu kill
    ;;
  *)
    echo "usage: $0 create | start | install | shot <file.png> | tap <x> <y> | stop" >&2
    exit 2
    ;;
esac

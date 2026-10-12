#!/usr/bin/env bash
# Removes what a harness run generates; goldens, sources and calibration logs stay.
#   bash cleanup.sh                                   # Playwright output only
#   bash cleanup.sh <android-device> <ios-device>     # also app builds and the app installed on the devices
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"

rm -rf "$here"/{test-results,playwright-report,.export,.calibration,node_modules} "$here"/calibration/playwright-*.json
[[ $# -eq 2 ]] || exit 0

rm -rf "$root/build" "$root/ios/Pods" ~/Library/Developer/Xcode/DerivedData/Runner-*
(cd "$root" && git checkout -- ios/Podfile.lock)
adb -s "$1" uninstall com.linagora.android.teammail >/dev/null 2>&1 || true
xcrun simctl uninstall "$2" com.linagora.ios.teammail >/dev/null 2>&1 || true

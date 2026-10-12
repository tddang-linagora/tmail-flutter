#!/usr/bin/env bash
# One-off: compare the golden harness with real device webviews (not run in CI).
#   bash test/html_render_golden/playwright/calibrate.sh --android-device <id> --ios-device <id>
# Needs an Android emulator (Pixel 7, API 34) and an iOS simulator (iPhone 11); `flutter run`-able devices.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
image="mcr.microsoft.com/playwright:v1.52.0-noble"
app="integration_test/tests/html_render_calibration/calibration_app.dart"
android_device="" ios_device=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --android-device) android_device="$2"; shift 2 ;;
    --ios-device) ios_device="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$android_device" && -n "$ios_device" ]] || { echo "both --android-device and --ios-device are required" >&2; exit 2; }

documents="integration_test/tests/html_render_calibration/calibration_documents.dart"
trap '(cd "$root" && git checkout -- "$documents"); bash "$here/cleanup.sh" "$android_device" "$ios_device"' EXIT

rm -rf "$here/.calibration" "$here"/calibration/playwright-*.json "$here"/calibration/device-*.log
(cd "$root" && HTML_RENDER_CALIBRATION_DIR="$here/.calibration" \
  flutter test test/html_render_golden/export_calibration_documents_test.dart)

docker run --rm --platform linux/amd64 --ipc=host -e HTML_RENDER_CALIBRATION=1 \
  -e HTML_RENDER_CALIBRATION_DIR=/work/.calibration \
  -v "$here:/work" -w /work "$image" bash -c '
    source container-setup.sh
    npx playwright test
  '

cd "$root"
# Waits for the app to print CALIBRATION_DONE, then stops it.
run_device() {
  local device="$1" log="$2"
  flutter run -d "$device" -t "$app" > "$log" 2>&1 &
  local pid=$!
  until grep -q CALIBRATION_DONE "$log" || ! kill -0 "$pid" 2>/dev/null; do sleep 3; done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  grep -q CALIBRATION_DONE "$log" || { echo "calibration did not finish on $device, see $log" >&2; exit 1; }
}
run_device "$android_device" "$here/calibration/device-android.log"
run_device "$ios_device" "$here/calibration/device-ios.log"
node "$here/calibration/compare.mjs"

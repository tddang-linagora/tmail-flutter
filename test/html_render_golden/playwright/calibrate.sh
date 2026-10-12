#!/usr/bin/env bash
# One-off: compare the golden harness with real device webviews (not run in CI).
#   bash test/html_render_golden/playwright/calibrate.sh --android-device <id> --ios-device <id>
# Needs an Android emulator (Pixel 7, API 34) and an iOS simulator (iPhone 11); `patrol` on PATH.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
image="mcr.microsoft.com/playwright:v1.52.0-noble"
test_file="integration_test/tests/html_render_calibration/html_render_calibration_test.dart"
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
trap '(cd "$root" && git checkout -- "$documents")' EXIT

rm -rf "$here/.calibration" "$here"/calibration/playwright-*.json "$here"/calibration/device-*.log
(cd "$root" && HTML_RENDER_CALIBRATION_DIR="$here/.calibration" \
  flutter test test/html_render_golden/export_calibration_documents_test.dart)

docker run --rm --platform linux/amd64 --ipc=host \
  -e HTML_RENDER_CALIBRATION=1 -e HTML_RENDER_CALIBRATION_DIR=/work/.calibration \
  -v "$here:/work" -w /work "$image" bash -c '
    set -e
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends fonts-roboto-unhinted fonts-noto-core fonts-noto-mono \
      fonts-noto-cjk fonts-noto-color-emoji fonts-liberation fonts-liberation2 >/dev/null
    npm install --no-package-lock --no-audit --no-fund
    npx playwright test
  '

cd "$root"
flutter build apk --config-only
patrol test --hide-test-steps --dart-define=HTML_RENDER_CALIBRATION=true -t "$test_file" -d "$android_device" | tee "$here/calibration/device-android.log"
patrol test --hide-test-steps --dart-define=HTML_RENDER_CALIBRATION=true -t "$test_file" -d "$ios_device" | tee "$here/calibration/device-ios.log"
node "$here/calibration/compare.mjs"

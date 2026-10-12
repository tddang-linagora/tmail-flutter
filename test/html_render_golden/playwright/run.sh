#!/usr/bin/env bash
# Pixel goldens of real emails.
#   bash test/html_render_golden/playwright/run.sh                     # verify
#   bash test/html_render_golden/playwright/run.sh --update-snapshots  # regenerate
# Screenshots run in a pinned linux/amd64 Playwright image: same pixels locally and in CI.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
flutter_cmd="${FLUTTER:-flutter}"
image="mcr.microsoft.com/playwright:v1.52.0-noble"

rm -rf "$here/.export"
(cd "$root" && HTML_RENDER_EXPORT_DIR="$here/.export" \
  $flutter_cmd test test/html_render_golden/export_render_documents_test.dart)

docker run --rm --platform linux/amd64 --ipc=host \
  -v "$here:/work" -w /work \
  "$image" bash -c 'npm install --no-package-lock --no-audit --no-fund && npx playwright test "$@"' _ "$@"

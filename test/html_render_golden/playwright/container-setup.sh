#!/usr/bin/env bash
# Runs inside the Playwright image (see run.sh and calibrate.sh): fonts, device-metric fonts, npm deps.
set -euo pipefail
apt-get update -qq
# Android: Roboto + Noto; iOS stand-in: Liberation (see fontconfig/). optipng recompresses goldens losslessly.
apt-get install -y -qq --no-install-recommends fonts-roboto-unhinted fonts-noto-core fonts-noto-mono \
  fonts-noto-cjk fonts-noto-color-emoji fonts-liberation fonts-liberation2 optipng python3-fonttools >/dev/null

# iOS line heights, fitted to an iPhone (WebKit rounds ascent and descent separately);
# copied before Android patches the originals.
lib=/usr/share/fonts/truetype/liberation
patch=fontconfig/patch-metrics.py
python3 $patch /tmp/fonts-ios 1.046 0.18 $lib/LiberationSans-*.ttf
python3 $patch /tmp/fonts-ios 0.908 0.322 $lib/LiberationSerif-*.ttf
python3 $patch /tmp/fonts-ios 0.962 0.27 $lib/LiberationMono-*.ttf

# Android: every family lays out with Roboto's line height on the device, serif and monospace included.
# The container is throwaway, so Android's fonts are patched where they are.
python3 $patch /tmp/fonts-android 0.927 0.244 /usr/share/fonts/truetype/noto/NotoSerif-*.ttf $lib/LiberationMono-*.ttf
cp /tmp/fonts-android/NotoSerif-*.ttf /usr/share/fonts/truetype/noto/
cp /tmp/fonts-android/LiberationMono-*.ttf $lib/

npm install --no-package-lock --no-audit --no-fund

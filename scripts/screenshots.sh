#!/bin/bash
# Screenshots of the main screens on the simulator, in Greek and English, light and dark,
# so the app can be seen without a Mac. Used by .github/workflows/build.yml.
#
#   scripts/screenshots.sh <simulator udid> <derived data path> <output folder>
#
# The app reads -screen, -language and -theme from its launch arguments (see RootView.swift
# and AppSettings.swift), so each screenshot opens straight on its screen.

set -u
UDID="$1"
DERIVED="$2"
OUT="$3"
APP=$(find "$DERIVED/Build/Products" -maxdepth 2 -name "AstikaKastorias.app" -path "*iphonesimulator*" | head -1)
BUNDLE=com.kastoriadevs.astikoktel

if [ -z "$APP" ]; then
  echo "No simulator build of the app in $DERIVED"
  exit 1
fi
mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
# A tidy status bar, location allowed and set to the Αφετηρία, so "near me" works
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 || true
xcrun simctl privacy "$UDID" grant location "$BUNDLE" || true
xcrun simctl location "$UDID" set 40.5214,21.2619 || true

shot() {
  local name="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" > /dev/null
  sleep 6
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" > /dev/null && echo "$name"
}

for lang in el en; do
  shot "$lang-home" -language "$lang" -theme light -screen home
done
shot el-lines -language el -theme light -screen lines
shot el-line -language el -theme light -screen line:04
shot el-route -language el -theme light -screen route:04
shot el-stop -language el -theme light -screen stop:16001
shot el-map -language el -theme light -screen map
shot el-map-line -language el -theme light -screen mapline:04
shot el-announcements -language el -theme light -screen announcements
shot el-settings -language el -theme light -screen settings
shot el-home-dark -language el -theme dark -screen home
shot el-stop-dark -language el -theme dark -screen stop:16001
shot el-map-dark -language el -theme dark -screen map
exit 0

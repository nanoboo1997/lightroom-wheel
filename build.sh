#!/bin/zsh
set -eu
cd "$(dirname "$0")"
package="dist/LightroomWheel"
app="$package/Lightroom Wheel.app"
if [[ -d "$package/Lightroom Wheel.lrplugin/bridge" ]]; then
  echo "This output folder has runtime data. Move the existing dist/LightroomWheel folder before rebuilding." >&2
  exit 1
fi
mkdir -p "$app/Contents/MacOS" "$package/Lightroom Wheel.lrplugin"
cp Packaging/Info.plist "$app/Contents/Info.plist"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos14.2   -framework AppKit -framework ApplicationServices -framework ScreenCaptureKit -framework Vision   Source/Logic.swift Source/NumericOCR.swift Source/Bridge.swift Source/Main.swift   -o "$app/Contents/MacOS/LightroomWheel"
for file in Info.lua Init.lua Start.lua Shutdown.lua; do
  cp "Lightroom Wheel.lrplugin/$file" "$package/Lightroom Wheel.lrplugin/$file"
done
cp README.md README-TH.md LICENSE TEST-RESULTS.txt "$package/"
dot_clean -m "$app"
codesign --force --sign - --identifier local.codex.LightroomWheel "$app"
codesign --verify --deep --strict "$app"
echo "Built $package (Apple Silicon, macOS 14.2+). Rebuilds may require refreshing app permissions."

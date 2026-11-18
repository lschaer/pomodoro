#!/bin/zsh
# Builds Pomodoro.app next to this script. Needs only the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Pomodoro.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# App icon is generated once; delete Resources/AppIcon.icns to regenerate it.
[[ -f Resources/AppIcon.icns ]] || { mkdir -p Resources && swift tools/make-icon.swift Resources; }
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

swiftc -O -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-macos14.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Pomodoro"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

# `./build.sh install` also replaces the copy in /Applications and relaunches it.
if [[ "${1:-}" == "install" ]]; then
  pkill -x Pomodoro || true
  rm -rf /Applications/Pomodoro.app
  ditto "$APP" /Applications/Pomodoro.app
  open /Applications/Pomodoro.app
  echo "Installed /Applications/Pomodoro.app"
fi

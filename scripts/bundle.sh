#!/bin/sh
# Builds Memnox.app into build/, signed ad hoc so it runs on this Mac. Notarizing is a release step.
set -e
cd "$(dirname "$0")/.."
swift build -c release --product MemnoxVoice
APP=build/Memnox.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/MemnoxVoice" "$APP/Contents/MacOS/MemnoxVoice"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP. Open it with: open $APP"

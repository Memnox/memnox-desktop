#!/bin/sh
# Builds Memnox.app into build/, signed with the local identity scripts/signing-setup.sh makes, so
# macOS keeps its Accessibility and Automation grants from one build to the next. Notarizing is a release step.
set -e
cd "$(dirname "$0")/.."
swift build -c release --product MemnoxVoice
APP=build/Memnox.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/MemnoxVoice" "$APP/Contents/MacOS/MemnoxVoice"
cp Support/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Support/Logo/*.png "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/AgentLogos"
cp Support/AgentLogos/* "$APP/Contents/Resources/AgentLogos/"
# Kokoro's installer and server ride inside the app, so it installs the voice on first launch itself.
mkdir -p "$APP/Contents/Resources/kokoro"
cp scripts/kokoro-setup.sh Support/kokoro/server.py "$APP/Contents/Resources/kokoro/"
IDENTITY="Memnox Local Signing"
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
  echo "Signed ad hoc, so macOS will ask for Accessibility again. Run scripts/signing-setup.sh once to stop that."
fi
echo "Built $APP. Open it with: open $APP"

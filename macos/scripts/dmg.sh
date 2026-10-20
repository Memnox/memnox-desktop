#!/bin/sh
# Builds build/Memnox-<version>.dmg, the one file a person downloads, with everything the app needs inside it: the
# newest memnox published to npm with its own Node, and the Kokoro voice ready to run. A disk image runs nothing on its
# own, so the app does the rest on its first launch with no download: it puts memnox into ~/.memnox/node and starts its
# daemon, while the voice already speaks from inside the app. A Mac that already has memnox keeps its own.
# The image is signed with the local identity, so a Mac other than this one needs it notarized before Gatekeeper opens it.
# MEMNOX_RUNTIME_VERSION pins the runtime to one release; it is the latest otherwise.
set -e
cd "$(dirname "$0")/.."

# The voice, built first with scripts/voice-pack.sh when build/voice has none.
VOICE="build/voice/kokoro"
[ -f "$VOICE/server.py" ] || sh scripts/voice-pack.sh
# The runtime pack, built every time, so the image carries the newest release.
sh scripts/runtime-pack.sh

MEMNOX_RUNTIME_SOURCE=npm MEMNOX_VOICE_DIR="$PWD/$VOICE" MEMNOX_RUNTIME_PACK="$PWD/build/runtime" \
  sh scripts/bundle.sh

APP=build/Memnox.app
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="build/Memnox-$VERSION.dmg"
# The window the image opens on: the app beside a link to Applications over a background with an arrow between them,
# so installing is the one drag every Mac app asks for. Laid out on a writable image, then compressed.
STAGE="build/dmg"
RW="build/Memnox-rw.dmg"
MOUNT="/Volumes/Memnox"
rm -rf "$STAGE" "$DMG" "$RW"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/Memnox.app"
ln -s /Applications "$STAGE/Applications"
cp Support/DMG/background.png "$STAGE/.background/background.png"
[ -d "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet
hdiutil create -volname Memnox -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
hdiutil attach "$RW" -mountpoint "$MOUNT" -quiet
# Finder draws the layout, so Terminal is asked once for leave to script it; refused, the image is only left plain.
osascript <<SCRIPT || echo "Finder would not lay out the window, so the image opens as a plain folder"
tell application "Finder"
  tell disk "Memnox"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set options to the icon view options of container window
    set arrangement of options to not arranged
    set icon size of options to 128
    set text size of options to 13
    set background picture of options to file ".background:background.png"
    set position of item "Memnox.app" of container window to {165, 190}
    set position of item "Applications" of container window to {495, 190}
    update without registering applications
    delay 1
    close
  end tell
end tell
SCRIPT
sync
hdiutil detach "$MOUNT" -quiet
# LZMA, since the voice rides in the app unpacked and only a strong compressor brings its Python and model back down.
hdiutil convert "$RW" -format ULMO -o "$DMG"
rm -rf "$STAGE" "$RW"

IDENTITY="Memnox Local Signing"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" "$DMG"
fi
shasum -a 256 "$DMG" | cut -d' ' -f1 > "$DMG.sha256"
# The same image under a name with no version, which a GitHub release serves at one lasting address for install.sh.
ln -f "$DMG" build/Memnox.dmg
cp "$DMG.sha256" build/Memnox.dmg.sha256
du -h "$DMG" | cut -f1 | sed "s|^|$DMG is |"
echo "It carries memnox $(cat build/runtime/memnox-runtime.version) with its own Node, and the Kokoro voice."

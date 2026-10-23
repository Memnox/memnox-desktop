#!/bin/sh
# Builds Memnox.app into build/, signed with the local identity scripts/signing-setup.sh makes, so
# macOS keeps its Accessibility and Automation grants from one build to the next. Notarizing is a release step.
#
# Where the app gets the Memnox runtime is chosen here and written into its Info.plist:
#   ./scripts/bundle.sh                              the runtime checkout beside this one, built first
#   MEMNOX_RUNTIME_SOURCE=npm ./scripts/bundle.sh    the package published to npm, for a release
# MEMNOX_RUNTIME_DIR names the checkout when it is not ../../memnox-runtime, beside memnox-desktop.
set -e
cd "$(dirname "$0")/.."

SOURCE="${MEMNOX_RUNTIME_SOURCE:-local}"
case "$SOURCE" in
  local | npm) ;;
  *) echo "MEMNOX_RUNTIME_SOURCE is local or npm, not $SOURCE." >&2; exit 1 ;;
esac

if [ "$SOURCE" = local ]; then
  RUNTIME_DIR="$(cd "${MEMNOX_RUNTIME_DIR:-../../memnox-runtime}" && pwd)"
  echo "Building the local runtime in $RUNTIME_DIR"
  (cd "$RUNTIME_DIR" && pnpm install --frozen-lockfile && pnpm build)
fi

# The Noise framework is never in git, so a fresh clone gets it here before the first build.
[ -d Vendor/MemnoxNoise.xcframework ] || sh scripts/vendor-noise.sh
swift build -c release --product MemnoxVoice
APP=build/Memnox.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/MemnoxVoice" "$APP/Contents/MacOS/MemnoxVoice"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Read by the app's RuntimeInstaller, which links and runs this checkout, or installs from npm.
/usr/libexec/PlistBuddy -c "Add :MemnoxRuntimeSource string $SOURCE" "$APP/Contents/Info.plist"
if [ "$SOURCE" = local ]; then
  /usr/libexec/PlistBuddy -c "Add :MemnoxRuntimeCheckout string $RUNTIME_DIR" "$APP/Contents/Info.plist"
fi
mkdir -p "$APP/Contents/Resources"
# The icon Finder, the Dock and the disk image show: the iPhone app's icon drawn into the macOS shape.
cp Support/AppIcon.icns "$APP/Contents/Resources/"
cp Support/Logo/*.png "$APP/Contents/Resources/"
# The website's scenes, so the first run pictures each step on the same ground the website does.
mkdir -p "$APP/Contents/Resources/Scenes"
cp Support/Scenes/*.webp "$APP/Contents/Resources/Scenes/"
mkdir -p "$APP/Contents/Resources/AgentLogos"
cp Support/AgentLogos/* "$APP/Contents/Resources/AgentLogos/"
# The tools a person signs in to, drawn in the notch and on the card of what goes out in their name.
mkdir -p "$APP/Contents/Resources/ToolLogos"
cp Support/ToolLogos/* "$APP/Contents/Resources/ToolLogos/"
# Memnox's own cue sounds, which scripts/make-sounds.py writes; without them the app plays the Mac's.
mkdir -p "$APP/Contents/Resources/Sounds"
cp Support/Sounds/*.wav "$APP/Contents/Resources/Sounds/"
# The setup bed is AAC where the Mac that made it could encode one.
cp Support/Sounds/*.m4a "$APP/Contents/Resources/Sounds/" 2>/dev/null || true
KOKORO="$APP/Contents/Resources/kokoro"
# Every build carries the voice, built here the first time, since an app without it speaks in the Mac's voice for
# the minutes Kokoro takes to download, which sounds broken. MEMNOX_NO_VOICE=1 skips it for a quick build.
if [ -z "${MEMNOX_VOICE_DIR:-}" ] && [ -z "${MEMNOX_NO_VOICE:-}" ] && [ ! -f build/voice/kokoro/server.py ]; then
  echo "Building the voice pack once, into build/voice"
  # A pack that cannot be built still leaves an app that installs the voice on first launch, so it warns and goes on.
  sh scripts/voice-pack.sh || echo "WARNING: the voice pack did not build, so this app downloads Kokoro on its first launch." >&2
fi
if [ -z "${MEMNOX_VOICE_DIR:-}" ] && [ -z "${MEMNOX_NO_VOICE:-}" ] && [ -f build/voice/kokoro/server.py ]; then
  MEMNOX_VOICE_DIR="$PWD/build/voice/kokoro"
fi
if [ -n "${MEMNOX_VOICE_DIR:-}" ]; then
  # The voice scripts/voice-pack.sh built, ready to run where it lands, so it speaks the moment the app first opens.
  # No installer goes with it, so install.sh and the app have nothing left to set up.
  ditto "$MEMNOX_VOICE_DIR" "$KOKORO"
  cp Support/kokoro/server.py "$KOKORO/"
else
  # A build without it carries Kokoro's installer and server instead, which install the voice on first launch.
  mkdir -p "$KOKORO"
  cp scripts/kokoro-setup.sh Support/kokoro/server.py "$KOKORO/"
fi
# The runtime with its own Node that scripts/runtime-pack.sh built, and the script that unpacks it on first launch,
# so a Mac with no Node and no connection still gets memnox and its daemon.
if [ -n "${MEMNOX_RUNTIME_PACK:-}" ]; then
  mkdir -p "$APP/Contents/Resources/runtime"
  cp "$MEMNOX_RUNTIME_PACK/memnox-runtime.tar.xz" "$MEMNOX_RUNTIME_PACK/memnox-runtime.version" Support/runtime/unpack.sh \
    "$APP/Contents/Resources/runtime/"
fi
IDENTITY="Memnox Local Signing"
# Only a valid identity signs; one left without its trust is made again here, since a build signed ad hoc is a
# build macOS forgets the Accessibility grant for, which looks in the app like typing that is never allowed.
# CI has nobody to answer the trust prompt, which would wait forever, so it signs ad hoc instead.
if [ -z "${CI:-}" ] && ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  sh scripts/signing-setup.sh || true
fi
ADHOC=no
SIGNER=-
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  SIGNER="$IDENTITY"
else
  ADHOC=yes
fi
# The code inside the carried voice is signed one file at a time before the app, since the app's own signature only
# seals it and macOS runs nothing on Apple silicon that is not signed itself.
find "$KOKORO" -type f \( -name "python3.12" -o -name "*.so" -o -name "*.dylib" \) -exec codesign --force --sign "$SIGNER" {} +
codesign --force --sign "$SIGNER" "$APP"

# A daemon already running the checkout is restarted on what was just built, so the app meets the new code.
if [ "$SOURCE" = local ] && command -v memnox >/dev/null 2>&1; then
  case "$(cd "$(dirname "$(readlink -f "$(command -v memnox)")")" && pwd -P)" in
    "$(cd "$RUNTIME_DIR" && pwd -P)"/*) memnox daemon --install ;;
    *) echo "memnox on your PATH is not this checkout; the app links it when it opens." ;;
  esac
fi
echo "Built $APP against the $SOURCE runtime. Open it with: open $APP"
if [ "$ADHOC" = yes ]; then
  cat >&2 <<WARN

WARNING: Memnox.app is signed ad hoc, because "$IDENTITY" is missing or not trusted in your keychain.
  macOS treats every ad hoc build as a new app, so the Accessibility grant is forgotten on each rebuild:
  the switch shows on in System Settings while Memnox is still not allowed to type.
  Fix once: sh scripts/signing-setup.sh   (it says what to do in Keychain Access if the trust prompt was declined)
  then:     sh scripts/bundle.sh
  Until then, switch Memnox off and on again under Privacy and Security after every build.
WARN
fi

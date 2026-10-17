#!/bin/sh
# Installs the newest Memnox developer preview into Applications and opens it:
#   curl -fsSL https://raw.githubusercontent.com/Memnox/memnox-desktop/main/macos/scripts/install.sh | sh
# The preview is signed with the project's own certificate rather than an Apple Developer ID, so a disk image a browser
# downloaded is stopped by Gatekeeper. curl marks nothing as downloaded, so the copy fetched here opens as one built
# from source would, and the checksum published beside the image is what proves it is the one released.
# MEMNOX_DMG_URL installs another image, such as one built locally, for a test.
set -eu

REPO="Memnox/memnox-desktop"
APP_NAME="Memnox.app"
BUNDLE_ID="com.memnox.voice"
MIN_MACOS=14

fail() { printf 'memnox install: %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || fail "Memnox for macOS runs on a Mac."
# The voice and the runtime it carries are built for Apple silicon only.
[ "$(uname -m)" = arm64 ] || fail "this preview runs on Apple silicon Macs only."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge "$MIN_MACOS" ] || fail "Memnox needs macOS $MIN_MACOS or later."

# The newest release that carries the Mac app, a preview included, since GitHub's own latest address skips every
# preview, and the newest release may be the Windows and Linux app's, which this repo releases too.
newest() {
  curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=30" \
    | grep -o '"browser_download_url": *"[^"]*/Memnox\.dmg"' | head -1 | sed 's/.*"\(https[^"]*\)"$/\1/'
}
URL="${MEMNOX_DMG_URL:-$(newest || true)}"
[ -n "$URL" ] || fail "could not find a release of Memnox to install."

WORK="$(mktemp -d)"
MOUNT="$WORK/mount"
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

echo "Downloading Memnox"
curl -fL --progress-bar --retry 3 "$URL" -o "$WORK/Memnox.dmg" || fail "could not download $URL"
# A local image is trusted as given; a released one must match the checksum published with it.
if [ -z "${MEMNOX_DMG_URL:-}" ]; then
  EXPECTED="$(curl -fsSL --retry 3 "$URL.sha256" | cut -d' ' -f1)" || fail "could not download the checksum"
  ACTUAL="$(shasum -a 256 "$WORK/Memnox.dmg" | cut -d' ' -f1)"
  [ "$EXPECTED" = "$ACTUAL" ] || fail "the download does not match its published checksum, so it was not installed."
fi

mkdir -p "$MOUNT"
hdiutil attach "$WORK/Memnox.dmg" -mountpoint "$MOUNT" -nobrowse -readonly -quiet || fail "could not open the disk image"
[ -d "$MOUNT/$APP_NAME" ] || fail "the disk image holds no $APP_NAME"

# Applications when this account may write there, else the one in the home folder, which macOS treats the same way.
TARGET=/Applications
[ -w "$TARGET" ] || { TARGET="$HOME/Applications"; mkdir -p "$TARGET"; }

# A running copy is asked to quit first, so the new one is what opens.
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
rm -rf "${TARGET:?}/$APP_NAME"
ditto "$MOUNT/$APP_NAME" "$TARGET/$APP_NAME"
xattr -dr com.apple.quarantine "$TARGET/$APP_NAME" 2>/dev/null || true

echo "Memnox is in $TARGET. Opening it; the first run asks for its permissions and installs memnox and its voice."
open "$TARGET/$APP_NAME"

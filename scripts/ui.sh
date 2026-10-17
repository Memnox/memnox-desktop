#!/bin/sh
# Rebuilds only the app's code and swaps it into the Memnox.app scripts/bundle.sh made, then opens it, so a change to
# the interface shows in seconds. The runtime, the resources and the daemon are left as they are, since none of them
# changed. Run scripts/bundle.sh again when they do, or when there is no build/Memnox.app yet.
#
#   ./scripts/ui.sh              rebuild and open Memnox
#   ./scripts/ui.sh --preview    rebuild and open the island on its own, touring its states with no daemon needed
set -e
cd "$(dirname "$0")/.."

APP=build/Memnox.app
if [ ! -d "$APP" ]; then
  echo "No $APP yet, so the whole app is built once first."
  sh scripts/bundle.sh
fi

# Debug rather than release, because an incremental debug build recompiles only what changed and so takes seconds.
swift build --product MemnoxVoice
cp "$(swift build --show-bin-path)/MemnoxVoice" "$APP/Contents/MacOS/MemnoxVoice"

# Signed with the same identity as the full build, so macOS still knows the app and keeps its grants.
IDENTITY="Memnox Local Signing"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
  echo "Signed ad hoc, so macOS may ask for Accessibility again. sh scripts/signing-setup.sh fixes that once." >&2
fi

# The running copy is quit first, since opening an app that is already open only brings the old code forward.
pkill -x MemnoxVoice 2>/dev/null || true
while pgrep -x MemnoxVoice >/dev/null; do sleep 0.1; done

if [ "${1:-}" = "--preview" ]; then
  open "$APP" --args --island-preview
else
  open "$APP"
fi
echo "Opened $APP with the new interface."

#!/bin/sh
# Builds and opens Memnox for Mac from source, for working on it, with nothing else to clone:
#   sh macos/scripts/dev.sh
# The Noise framework comes from the newest memnox-runtime release and the app installs memnox from
# npm, so this repo is the only clone needed. A memnox-runtime checkout beside this repo, or named by
# MEMNOX_RUNTIME, is built and run instead, for working on both at once. A step already done is
# skipped, so it is also the command to run every day; MEMNOX_NO_VOICE=1 skips the voice pack.
set -eu

fail() { printf 'memnox dev: %s\n' "$1" >&2; exit 1; }
step() { printf '\n==> %s\n' "$1"; }

[ "$(uname -s)" = Darwin ] || fail "this builds Memnox for Mac, so it runs on macOS."
[ "$(uname -m)" = arm64 ] || fail "the Mac app builds on Apple silicon only, and this Mac is $(uname -m)."
cd "$(dirname "$0")/.."
runtime=${MEMNOX_RUNTIME:-../../memnox-runtime}
[ -n "${MEMNOX_RUNTIME:-}" ] && [ ! -f "$runtime/package.json" ] &&
  fail "MEMNOX_RUNTIME names $runtime, which is not a memnox-runtime checkout."

step "Xcode"
xcodebuild -version >/dev/null 2>&1 ||
  fail "the app needs the macOS 26 SDK from Xcode 26 or later; install Xcode and run sudo xcode-select -s /Applications/Xcode.app"
xcodebuild -version | head -1

step "The Noise framework"
if [ -d Vendor/MemnoxNoise.xcframework ]; then
  echo "already in Vendor"
else
  sh scripts/vendor-noise.sh
fi

step "memnox-runtime"
if [ -f "$runtime/package.json" ]; then
  # bundle.sh builds the checkout with pnpm, so it needs the pnpm the runtime pins.
  command -v corepack >/dev/null 2>&1 || fail "a runtime checkout is built with pnpm, which needs Node 22 or later with corepack enable."
  export MEMNOX_RUNTIME_SOURCE=local MEMNOX_RUNTIME="$(cd "$runtime" && pwd)"
  echo "building and running the checkout $MEMNOX_RUNTIME"
else
  export MEMNOX_RUNTIME_SOURCE=npm
  echo "no checkout beside this repo, so the app installs memnox from npm when it opens"
fi

step "Build and sign build/Memnox.app"
sh scripts/bundle.sh

step "Opening Memnox"
# An open copy keeps running the old build, so it is quit before the new one opens.
osascript -e 'quit app "Memnox"' >/dev/null 2>&1 || true
open build/Memnox.app

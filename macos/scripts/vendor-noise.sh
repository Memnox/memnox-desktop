#!/bin/sh
# Puts MemnoxNoise.xcframework into Vendor, which Package.swift needs and git never holds (55 MB of static libraries).
# Taken from memnox-runtime's build when there is one, else from the iPhone app in memnox-mobile/ios, else built in memnox-runtime with cargo.
# Run on its own, or by bundle.sh and sync-relay.sh when Vendor is empty.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
runtime="${MEMNOX_RUNTIME:-$here/../../memnox-runtime}"
# The phone app lives in memnox-mobile/ios, or in a memnox-ios checkout not yet moved there.
ios="${MEMNOX_IOS:-$here/../../memnox-mobile/ios}"
[ -n "${MEMNOX_IOS:-}" ] || [ -d "$ios" ] || ios="$here/../../memnox-ios"
target="$here/Vendor/MemnoxNoise.xcframework"

noise="$runtime/native/noise/build/MemnoxNoise.xcframework"
[ -d "$noise" ] || noise="$ios/Vendor/MemnoxNoise.xcframework"
if [ ! -d "$noise" ]; then
  build="$runtime/native/noise/scripts/build-xcframework.sh"
  if [ ! -f "$build" ]; then
    echo "no MemnoxNoise.xcframework in memnox-runtime or the iPhone app, and no memnox-runtime checkout to build it in; set MEMNOX_RUNTIME or MEMNOX_IOS" >&2
    exit 1
  fi
  if ! command -v cargo >/dev/null 2>&1 || ! command -v rustup >/dev/null 2>&1; then
    echo "no MemnoxNoise.xcframework to copy, and building it needs rustup and cargo: https://rustup.rs" >&2
    exit 1
  fi
  echo "Building MemnoxNoise.xcframework in $runtime/native/noise"
  sh "$build"
  noise="$runtime/native/noise/build/MemnoxNoise.xcframework"
fi
rm -rf "$target"
mkdir -p "$here/Vendor"
cp -R "$noise" "$target"
echo "copied $noise"

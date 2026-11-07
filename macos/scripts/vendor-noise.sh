#!/bin/sh
# Puts MemnoxNoise.xcframework into Vendor, which Package.swift needs and git never holds (55 MB of static libraries).
# Taken from memnox-runtime's build when there is one, else from the iPhone app in memnox-mobile/ios, else built in a
# memnox-runtime checkout with cargo, else downloaded from the newest memnox-runtime release.
# Run on its own, or by bundle.sh and sync-relay.sh when Vendor is empty.
set -eu
# The Noise framework, the bundled Node and the voice's Python are all arm64, so an Intel Mac stops here rather than at a link error.
[ "$(uname -m)" = arm64 ] || { echo "the Mac app builds on Apple silicon only, and this Mac is $(uname -m)" >&2; exit 1; }
here="$(cd "$(dirname "$0")/.." && pwd)"
runtime="${MEMNOX_RUNTIME:-$here/../../memnox-runtime}"
ios="${MEMNOX_IOS:-$here/../../memnox-mobile/ios}"
target="$here/Vendor/MemnoxNoise.xcframework"

# The newest memnox-runtime release carries a built one, checked against its own SHA256, for working on this repo alone.
download() {
  release="${MEMNOX_NOISE_RELEASE:-https://github.com/Memnox/memnox-runtime/releases/latest/download}"
  work=$(mktemp -d "${TMPDIR:-/tmp}/memnox-noise.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  echo "Downloading MemnoxNoise.xcframework from $release"
  curl -fsSL --retry 3 -o "$work/MemnoxNoise.xcframework.zip" "$release/MemnoxNoise.xcframework.zip" &&
    curl -fsSL --retry 3 -o "$work/MemnoxNoise.xcframework.zip.sha256" "$release/MemnoxNoise.xcframework.zip.sha256" || {
    echo "the release at $release has no MemnoxNoise.xcframework.zip; set MEMNOX_RUNTIME to a memnox-runtime checkout to build it" >&2
    exit 1
  }
  (cd "$work" && shasum -a 256 -c MemnoxNoise.xcframework.zip.sha256) >/dev/null || {
    echo "MemnoxNoise.xcframework.zip does not match its SHA256, so nothing was unpacked" >&2
    exit 1
  }
  ditto -x -k "$work/MemnoxNoise.xcframework.zip" "$work"
  noise="$work/MemnoxNoise.xcframework"
}

noise="$runtime/native/noise/build/MemnoxNoise.xcframework"
[ -d "$noise" ] || noise="$ios/Vendor/MemnoxNoise.xcframework"
if [ ! -d "$noise" ]; then
  build="$runtime/native/noise/scripts/build-xcframework.sh"
  if [ -f "$build" ] && command -v cargo >/dev/null 2>&1 && command -v rustup >/dev/null 2>&1; then
    echo "Building MemnoxNoise.xcframework in $runtime/native/noise"
    sh "$build"
    noise="$runtime/native/noise/build/MemnoxNoise.xcframework"
  else
    download
  fi
fi
rm -rf "$target"
mkdir -p "$here/Vendor"
cp -R "$noise" "$target"
echo "copied $noise"

#!/bin/sh
# Downloads sherpa-onnx's static libraries outside target and points SHERPA_ONNX_LIB_DIR at them for CI.
# Left to itself the crate unpacks them into target/sherpa-onnx-prebuilt, which the Rust cache deletes
# while keeping the build script's output that names it, so every run with a warm cache fails to link.
# The version is read from Cargo.lock, so it always matches the crate that links against it.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
lock="$here/../../Cargo.lock"
version=$(awk '/^name = "sherpa-onnx-sys"$/ { getline; gsub(/version = |"/, ""); print; exit }' "$lock")
if [ -z "$version" ]; then
  echo "sherpa-onnx-sys not found in $lock" >&2
  exit 1
fi
case "$(uname -s)" in
  Linux) platform=linux-x64-static-lib ;;
  MINGW* | MSYS* | CYGWIN*) platform=win-x64-static-MT-Release-lib ;;
  *)
    echo "no sherpa-onnx download set up for $(uname -s); the crate fetches its own" >&2
    exit 0
    ;;
esac
stem="sherpa-onnx-v$version-$platform"
dir="${RUNNER_TEMP:-$here/.sherpa}/sherpa-onnx"
mkdir -p "$dir"
curl -fsSL --retry 3 "https://github.com/k2-fsa/sherpa-onnx/releases/download/v$version/$stem.tar.bz2" \
  | tar -xjf - -C "$dir"
lib="$dir/$stem/lib"
if [ ! -f "$lib/libsherpa-onnx-c-api.a" ] && [ ! -f "$lib/sherpa-onnx-c-api.lib" ]; then
  echo "the sherpa-onnx archive did not unpack a c-api library into $lib" >&2
  exit 1
fi
echo "sherpa-onnx $version in $lib"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "SHERPA_ONNX_LIB_DIR=$lib" >> "$GITHUB_ENV"
fi

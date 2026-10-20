#!/bin/sh
# Builds the voice the app carries, ready to run with nothing unpacked: a Python of its own, the packages the server
# imports, the 8-bit Kokoro model and the voices setup offers, in build/voice/kokoro. scripts/bundle.sh copies the
# folder into the app as it stands, so the voice speaks the moment Memnox first opens. Run on an Apple silicon Mac
# with uv on it.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/../build/voice}"
PACK="$OUT/kokoro"
RELEASE="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
# The 8-bit model: a fifth of the full one's download and quicker to speak, at a sound the full one is not missed for.
MODEL="kokoro-v1.0.int8.onnx"
MODEL_BYTES=92361271
# Every voice the release has, from which only the ones setup offers are kept.
ALL_VOICES="voices-v1.0.bin"
ALL_VOICES_BYTES=28214398
# The same ids as KokoroVoice.choices in Sources/MemnoxVoice/Platform/Kokoro.swift; change one and change the other.
OFFERED="af_sky af_heart af_bella af_nicole af_sarah am_adam am_michael bf_emma bf_isabella bm_george bm_lewis"
PYTHON="3.12"

UV="$(command -v uv 2>/dev/null || true)"
[ -n "$UV" ] || { echo "uv is needed to build the voice: brew install uv"; exit 1; }
rm -rf "$PACK"
mkdir -p "$PACK" "$OUT/downloads"

echo "Python $PYTHON"
"$UV" python install "$PYTHON" --install-dir "$OUT/downloads/python" --no-progress
FOUND="$(cd "$OUT/downloads/python" && ls -d cpython-$PYTHON.*-macos-aarch64-none | head -1)"
[ -n "$FOUND" ] || { echo "uv left no Python $PYTHON install in $OUT/downloads/python"; exit 1; }
# Under a name with no version in it, so the app finds the interpreter at one fixed path.
cp -R "$OUT/downloads/python/$FOUND" "$PACK/python"
PY="$PACK/python/bin/python$PYTHON"

echo "Packages"
# Installed beside the server rather than into a venv, since a venv names its Python by an absolute path and the app
# is wherever the person put it. server.py puts this folder on its path itself.
SITE="$PACK/site-packages"
"$UV" pip install --quiet --python "$PY" --target "$SITE" kokoro-onnx numpy
# No misaki: kokoro-onnx pronounces with its own espeak, which sounds as good here, and misaki with spaCy is a fifth of
# the download and the half minute macOS spends checking its libraries the first time the voice starts.

echo "Trimming"
# What the server never runs: Python's own tests and tools, installers, and compiled caches the app could not write
# back into a signed bundle anyway.
LIB="$PACK/python/lib/python$PYTHON"
rm -rf "$LIB/test" "$LIB/idlelib" "$LIB/tkinter" "$LIB/turtledemo" "$LIB/ensurepip" "$LIB/lib2to3" \
  "$LIB/site-packages"/* "$PACK/python/lib/libtcl"* "$PACK/python/lib/libtk"* "$PACK/python/lib/tcl"* "$PACK/python/lib/tk"* \
  "$PACK/python/share" "$PACK/python/include"
# The interpreter is linked statically, so the shared library is only for embedding, and bin keeps it alone.
rm -f "$PACK/python/lib/libpython"*
find "$PACK/python/bin" -mindepth 1 ! -name "python$PYTHON" -exec rm -f {} +
rm -rf "$SITE/pip" "$SITE/setuptools" "$SITE/_distutils_hack" "$SITE/bin"
# Tk lives in folders named for its own extensions, which the names above miss.
rm -rf "$PACK/python/lib/thread"* "$PACK/python/lib/itcl"* "$LIB/lib-dynload/_tkinter"*
# onnxruntime's tools for converting and quantizing models, which speaking never imports.
rm -rf "$SITE/onnxruntime/transformers" "$SITE/onnxruntime/quantization" "$SITE/onnxruntime/tools"
# Every voice setup offers is American or British English, and both read en_dict, so the other languages' go.
find "$SITE/espeakng_loader" -name "*_dict" ! -name "en_dict" -exec rm -f {} +
find "$SITE/numpy" -name "*_tests.cpython-*.so" -exec rm -f {} +
find "$PACK" -type d \( -name __pycache__ -o -name tests -o -name test \) -prune -exec rm -rf {} +

echo "Model and voices"
bytes() { stat -f %z "$1" 2>/dev/null || echo 0; }
for pair in "$MODEL $MODEL_BYTES" "$ALL_VOICES $ALL_VOICES_BYTES"; do
  set -- $pair
  file="$OUT/downloads/$1"
  [ "$(bytes "$file")" -eq "$2" ] || curl -fL --retry 5 --retry-all-errors --retry-delay 2 -C - "$RELEASE/$1" -o "$file"
  [ "$(bytes "$file")" -eq "$2" ] || { echo "$1 came down at $(bytes "$file") bytes rather than $2"; exit 1; }
done
cp "$OUT/downloads/$MODEL" "$PACK/$MODEL"
"$PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import numpy as np
every = np.load(sys.argv[2])
offered = sys.argv[4].split()
missing = [name for name in offered if name not in every]
if missing:
    sys.exit(f"the release has no voice {missing}")
np.savez(sys.argv[3], **{name: every[name] for name in offered})
' "$SITE" "$OUT/downloads/$ALL_VOICES" "$PACK/voices.npz" "$OFFERED"
cp "$HERE/../Support/kokoro/server.py" "$PACK/server.py"

echo "Compiling"
# Compiled here, since the app runs Python with -B and a signed bundle must never be written to: left to compile on
# first launch, the voice is silent until every package is compiled. Checked by nothing but their presence,
# so a copy that changes file times never makes Python compile them again.
"$PY" -I -m compileall -q --invalidation-mode unchecked-hash "$PACK/python/lib/python$PYTHON" "$SITE" >/dev/null

echo "Checking it speaks"
"$PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1] + "/site-packages")
from kokoro_onnx import Kokoro
kokoro = Kokoro(sys.argv[1] + "/" + sys.argv[2], sys.argv[1] + "/voices.npz")
samples, rate = kokoro.create("Ready.", voice="af_sky", speed=1.0, lang="en-us")
assert len(samples) > rate // 10, "the voice said nothing"
' "$PACK" "$MODEL" 2>/dev/null
du -sh "$PACK" | cut -f1 | sed "s|^|$PACK is |"

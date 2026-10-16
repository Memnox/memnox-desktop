#!/bin/sh
# Builds the voice pack: a Python, the environment, the model, the voices and the server in one archive, so a Mac
# installs its voice with one download from a host near the person rather than four slow ones from GitHub and PyPI,
# which from much of the world come down at a few hundred kilobytes a second. Run on an Apple silicon Mac with uv on
# it. Upload the two files it leaves in build/voice-pack to a bucket behind a CDN, then build the app with
# MEMNOX_VOICE_PACK set to the archive's URL, so the installer inside the app takes the pack before anything else.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/../build/voice-pack}"
# Numbered, so a pack built with another Python or another model is a new file beside the old, never over it.
NAME="kokoro-pack-1"
PACK="$OUT/$NAME"
# The same release, files and sizes as kokoro-setup.sh, which installs them one by one where there is no pack.
RELEASE="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
SPACY_MODEL="en_core_web_sm @ https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl"
MODEL="kokoro-v1.0.onnx"
MODEL_BYTES=325532387
VOICES="voices-v1.0.bin"
VOICES_BYTES=28214398
PYTHON="3.12"

UV="$(command -v uv 2>/dev/null || true)"
[ -n "$UV" ] || { echo "uv is needed to build the pack: brew install uv"; exit 1; }
rm -rf "$PACK"
mkdir -p "$PACK"

echo "Python $PYTHON"
"$UV" python install "$PYTHON" --install-dir "$PACK/python" --no-progress
PYDIR="$(cd "$PACK/python" && ls -d cpython-$PYTHON.*-macos-aarch64-none | head -1)"
[ -n "$PYDIR" ] || { echo "uv left no Python $PYTHON install in $PACK/python"; exit 1; }
# The unversioned alias points at the same install, and the installer finds the versioned folder on its own.
rm -f "$PACK/python/cpython-$PYTHON-macos-aarch64-none"

echo "Environment"
"$UV" venv --quiet --relocatable --python "$PACK/python/$PYDIR/bin/python$PYTHON" "$PACK/venv"
"$UV" pip install --quiet --python "$PACK/venv/bin/python" kokoro-onnx numpy
# Misaki on its own with only what it reads English with, for the reasons kokoro-setup.sh gives.
"$UV" pip install --quiet --python "$PACK/venv/bin/python" --no-deps misaki-fork
"$UV" pip install --quiet --python "$PACK/venv/bin/python" addict regex num2words spacy "$SPACY_MODEL"
# The interpreter links point inside the pack by a relative path, so the pack works wherever it lands.
for link in python python3 "python$PYTHON"; do
  ln -sfn "../../python/$PYDIR/bin/python$PYTHON" "$PACK/venv/bin/$link"
done
# pyvenv.cfg names the Python's home as an absolute path, which the installer rewrites to where it unpacked.
sed -i '' "s|^home = .*|home = PACK_HOME/python/$PYDIR/bin|" "$PACK/venv/pyvenv.cfg"

echo "Voice files"
bytes() { stat -f %z "$1" 2>/dev/null || echo 0; }
# A whole copy this Mac's own voice already installed is taken rather than pulled again from GitHub, which is slow.
INSTALLED="$HOME/.memnox/voice/kokoro"
for pair in "$MODEL $MODEL_BYTES" "$VOICES $VOICES_BYTES"; do
  set -- $pair
  if [ "$(bytes "$INSTALLED/$1")" -eq "$2" ]; then cp "$INSTALLED/$1" "$PACK/$1"; continue; fi
  curl -fL --retry 5 --retry-all-errors --retry-delay 2 -C - "$RELEASE/$1" -o "$PACK/$1"
  [ "$(bytes "$PACK/$1")" -eq "$2" ] || { echo "$1 came down at $(bytes "$PACK/$1") bytes rather than $2"; exit 1; }
done
cp "$HERE/../Support/kokoro/server.py" "$PACK/server.py"

echo "Archive"
# The model and the voices hardly compress, so a quick level keeps the build short and the archive about as small.
XZ_OPT="-T0 -3" tar -C "$OUT" -cJf "$OUT/$NAME.tar.xz" "$NAME"
shasum -a 256 "$OUT/$NAME.tar.xz" | cut -d' ' -f1 > "$OUT/$NAME.tar.xz.sha256"
rm -rf "$PACK"
du -h "$OUT/$NAME.tar.xz" | cut -f1 | sed "s|^|$NAME.tar.xz is |"
echo "Upload $NAME.tar.xz and $NAME.tar.xz.sha256 from $OUT to the bucket, then build with"
echo "  MEMNOX_VOICE_PACK=https://<your host>/$NAME.tar.xz ./scripts/bundle.sh"

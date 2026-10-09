#!/bin/sh
# Installs Kokoro for Memnox's voice into ~/.memnox/voice/kokoro: a Python environment, the model
# and its voices (about 340 MB, once), and the small server the app starts. Free, and on device.
# The app runs the copy inside its bundle on first launch, so this needs no repository, no PATH
# and no Python of the Mac's own: uv brings a Python 3.12 just for Kokoro when none is there.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="${MEMNOX_KOKORO_DIR:-$HOME/.memnox/voice/kokoro}"
RELEASE="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
SPACY_MODEL="en_core_web_sm @ https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl"
# Written once this version of the setup has run, so a Mac set up before it runs it again.
MARK="setup-2"
# Beside this script inside the app, in Support/kokoro when run from the repository.
SERVER="$HERE/server.py"
[ -f "$SERVER" ] || SERVER="$HERE/../Support/kokoro/server.py"
mkdir -p "$DIR"

# An app opened from Finder has a bare PATH, so uv is looked for where installers put it.
UV=""
for candidate in "$(command -v uv 2>/dev/null)" "$DIR/uv/uv" "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv" /opt/homebrew/bin/uv /usr/local/bin/uv; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then UV="$candidate"; break; fi
done
if [ -z "$UV" ]; then
  echo "STEP Getting the Python tools"
  # Unmanaged, so it lands in Kokoro's own folder and no shell profile is touched.
  curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$DIR/uv" INSTALLER_NO_MODIFY_PATH=1 sh >/dev/null
  UV="$DIR/uv/uv"
fi

echo "STEP Setting up Python"
"$UV" venv --quiet --allow-existing --python 3.12 "$DIR/venv"
"$UV" pip install --quiet --python "$DIR/venv/bin/python" kokoro-onnx numpy

# Misaki is the pronunciation Kokoro was trained to read, clearer on every word than espeak. Its
# English extra would bring torch and transformers, gigabytes for a neural fallback never used
# here, and a phonemizer that replaces the one kokoro-onnx speaks with, so it goes in on its own
# with only what it reads English with, spaCy's small model among them since the environment
# has no pip to fetch it later. Without misaki the server speaks with espeak, so a failure here
# does not fail the install.
echo "STEP Teaching it to pronounce"
{ "$UV" pip install --quiet --python "$DIR/venv/bin/python" --no-deps misaki-fork \
  && "$UV" pip install --quiet --python "$DIR/venv/bin/python" addict regex num2words spacy "$SPACY_MODEL"; } \
  || echo "misaki did not install, so the voice pronounces with espeak"

for file in kokoro-v1.0.onnx voices-v1.0.bin; do
  if [ ! -s "$DIR/$file" ]; then
    echo "STEP Downloading the voice, $file"
    # Resumed and retried, since a 300 MB download over a flaky link breaks off more often than it fails outright.
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 -C - "$RELEASE/$file" -o "$DIR/$file.part"
    mv "$DIR/$file.part" "$DIR/$file"
  fi
done

# Copied last, since the app counts Kokoro installed only once every piece is in place.
cp "$SERVER" "$DIR/server.py"
touch "$DIR/$MARK"
echo "STEP Ready"
echo "Kokoro is ready in $DIR."

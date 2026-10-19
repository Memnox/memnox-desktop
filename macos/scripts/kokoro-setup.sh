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
# The two voice files at the size the release publishes them, so a file that came down short never passes for the voice.
MODEL="kokoro-v1.0.onnx"
MODEL_BYTES=325532387
VOICES="voices-v1.0.bin"
VOICES_BYTES=28214398
# Written once this version of the setup has run, so a Mac set up before it runs it again.
MARK="setup-3"
# Beside this script inside the app, in Support/kokoro when run from the repository.
SERVER="$HERE/server.py"
[ -f "$SERVER" ] || SERVER="$HERE/../Support/kokoro/server.py"
mkdir -p "$DIR"

# The app that started this may be gone before it ends, as when it reopens for a permission, and the install must
# finish all the same: a closed pipe is ignored, and the first write that fails moves the rest of the output to the
# log file, since a shell that keeps failing to write leaks the unsent text into its next command substitution.
trap '' PIPE
# Each step is told to the app by its STEP line and timed in the log, so a slow install says where it was slow.
step() { { echo "TIME $(date +%T)"; echo "STEP $1"; } 2>/dev/null || exec >>"$DIR/install.log" 2>&1; }

# One install at a time: a second app instance waits for the first instead of downloading into the same files beside
# it, which left a model nobody could load. A lock whose holder is no longer running is stale and taken over.
LOCK="$DIR/installing"
until mkdir "$LOCK" 2>/dev/null; do
  holder="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -z "$holder" ]; then sleep 1; holder="$(cat "$LOCK/pid" 2>/dev/null)"; fi
  if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
    step "Waiting for an install already under way"
    sleep 5
  else
    rm -rf "$LOCK"
  fi
done
echo $$ > "$LOCK/pid"
DOWNLOADS=""
cleanup() {
  [ -n "$DOWNLOADS" ] && kill $DOWNLOADS 2>/dev/null
  rm -rf "$LOCK"
  return 0
}
trap cleanup EXIT
trap 'exit 1' INT TERM

bytes() { stat -f %z "$1" 2>/dev/null || echo 0; }

# An install that finished while this one waited for the lock, or before the app looked, leaves nothing to do, and
# running it again would take the working voice apart to rebuild it, keeping the app's spinner up all the while.
if [ -f "$DIR/$MARK" ] && [ "$(bytes "$DIR/$MODEL")" = "$MODEL_BYTES" ] && [ "$(bytes "$DIR/$VOICES")" = "$VOICES_BYTES" ] \
  && "$DIR/venv/bin/python" -c "import kokoro_onnx" 2>/dev/null; then
  step "Ready"
  exit 0
fi

# Everything the voice needs in one archive from a host near the person, built by scripts/voice-pack.sh and named
# here by the build, since the pieces otherwise come from GitHub and PyPI, which are slow from much of the world.
# Empty means no pack, and the pieces come one by one from where their makers publish them.
PACK_DEFAULT=""
PACK_URL="${MEMNOX_VOICE_PACK:-$PACK_DEFAULT}"
# The same pack carried inside the app beside this script, as the downloadable disk image ships it, so the voice
# installs on first launch with no download.
PACK_FILE="${MEMNOX_VOICE_PACK_FILE:-$HERE/kokoro-pack.tar.xz}"

# Unpacks a pack archive and points the venv's Python at its new home. False when anything is short.
unpack() {
  step "Unpacking the voice"
  rm -rf "$DIR/venv" "$DIR/python"
  tar -C "$DIR" --strip-components 1 -xJf "$1" || return 1
  home="$(ls -d "$DIR"/python/cpython-*/bin 2>/dev/null | head -1)"
  [ -n "$home" ] || return 1
  sed -i '' "s|^home = .*|home = $home|" "$DIR/venv/pyvenv.cfg" || return 1
  "$DIR/venv/bin/python" -c "import kokoro_onnx" 2>/dev/null || return 1
}

# Takes the pack: the one on this Mac when there is one, which came inside the signed app, else the hosted one,
# resumed if it broke off and accepted only against its checksum. Anything short of that returns false, and the pieces
# are fetched instead.
pack() {
  if [ -f "$PACK_FILE" ] && unpack "$PACK_FILE"; then return 0; fi
  [ -n "$PACK_URL" ] || return 1
  step "Downloading the voice"
  curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 -C - "$PACK_URL" -o "$DIR/pack.tar.xz.part" || return 1
  curl -fsSL --retry 3 --retry-all-errors "$PACK_URL.sha256" -o "$DIR/pack.sha256" || return 1
  if [ "$(shasum -a 256 "$DIR/pack.tar.xz.part" | cut -d' ' -f1)" != "$(cut -d' ' -f1 < "$DIR/pack.sha256")" ]; then
    echo "the voice pack did not match its checksum, so it was thrown away"
    rm -f "$DIR/pack.tar.xz.part" "$DIR/pack.sha256"
    return 1
  fi
  unpack "$DIR/pack.tar.xz.part" || return 1
  rm -f "$DIR/pack.tar.xz.part" "$DIR/pack.sha256"
}

if pack; then
  cp "$SERVER" "$DIR/server.py"
  touch "$DIR/$MARK"
  step "Ready"
  echo "Kokoro is ready in $DIR, from the voice pack."
  exit 0
fi

# Starts a voice file downloading in the background unless it is already whole. The download resumes a part left
# by an earlier run, since a 300 MB file over a slow link breaks off more often than it fails outright; a part that
# grew past the real size, or a finished file at the wrong size, is thrown away since it cannot be trusted.
fetch() {
  file="$DIR/$1"
  [ "$(bytes "$file")" -eq "$2" ] && return 0
  rm -f "$file"
  [ "$(bytes "$file.part")" -gt "$2" ] && rm -f "$file.part"
  curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 -C - "$RELEASE/$1" -o "$file.part" &
  DOWNLOADS="$DOWNLOADS $!"
}

# Accepts a downloaded file only at its known size, so nothing half there is ever what the voice reads.
finish() {
  file="$DIR/$1"
  [ -f "$file.part" ] && mv "$file.part" "$file"
  [ "$(bytes "$file")" -eq "$2" ] && return 0
  echo "$1 came down at $(bytes "$file") bytes rather than $2, so it was thrown away"
  rm -f "$file"
  return 1
}

# The two voice files are most of the install and need nothing from Python, so they come down together while the
# environment is built.
fetch "$MODEL" "$MODEL_BYTES"
fetch "$VOICES" "$VOICES_BYTES"

# An app opened from Finder has a bare PATH, so uv is looked for where installers put it.
UV=""
for candidate in "$(command -v uv 2>/dev/null)" "$DIR/uv/uv" "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv" /opt/homebrew/bin/uv /usr/local/bin/uv; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then UV="$candidate"; break; fi
done
if [ -z "$UV" ]; then
  step "Getting the tools"
  # Unmanaged, so it lands in Kokoro's own folder and no shell profile is touched.
  curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$DIR/uv" INSTALLER_NO_MODIFY_PATH=1 sh >/dev/null
  UV="$DIR/uv/uv"
fi

step "Setting up"
"$UV" venv --quiet --allow-existing --python 3.12 "$DIR/venv"
"$UV" pip install --quiet --python "$DIR/venv/bin/python" kokoro-onnx numpy

# Misaki is the pronunciation Kokoro was trained to read, clearer on every word than espeak. Its
# English extra would bring torch and transformers, gigabytes for a neural fallback never used
# here, and a phonemizer that replaces the one kokoro-onnx speaks with, so it goes in on its own
# with only what it reads English with, spaCy's small model among them since the environment
# has no pip to fetch it later. Without misaki the server speaks with espeak, so a failure here
# does not fail the install.
step "Teaching it to pronounce"
{ "$UV" pip install --quiet --python "$DIR/venv/bin/python" --no-deps misaki-fork \
  && "$UV" pip install --quiet --python "$DIR/venv/bin/python" addict regex num2words spacy "$SPACY_MODEL"; } \
  || echo "misaki did not install, so the voice pronounces with espeak"

# Waited for one by one, so a download that failed fails the install rather than leaving half a voice behind.
step "Downloading the voice"
for pid in $DOWNLOADS; do wait "$pid"; done
DOWNLOADS=""
finish "$MODEL" "$MODEL_BYTES"
finish "$VOICES" "$VOICES_BYTES"

# Copied last, since the app counts Kokoro installed only once every piece is in place.
cp "$SERVER" "$DIR/server.py"
touch "$DIR/$MARK"
step "Ready"
echo "Kokoro is ready in $DIR."

#!/bin/sh
# Builds and opens Memnox for Linux from source, for working on it, with no release installed:
#   sh linux/scripts/dev.sh
# It installs the system libraries and runs `tauri dev`, and the app installs and starts the runtime
# published to npm on its first run, so this repo is the only clone needed. A memnox-runtime checkout
# beside this repo, or named by MEMNOX_RUNTIME, is built and run instead, for working on both at once.
# A step already done is skipped, so it is also the command to run every day.
set -eu

fail() { printf 'memnox dev: %s\n' "$1" >&2; exit 1; }
step() { printf '\n==> %s\n' "$1"; }

[ "$(uname -s)" = Linux ] || fail "this builds Memnox for Linux, so it runs on Linux."

repo=$(cd "$(dirname "$0")/../.." && pwd)
app="$repo/shared/tauri-core"
runtime=${MEMNOX_RUNTIME:-$repo/../memnox-runtime}
[ -n "${MEMNOX_RUNTIME:-}" ] && [ ! -f "$runtime/packages/core/src/wire.ts" ] &&
  fail "MEMNOX_RUNTIME names $runtime, which is not a memnox-runtime checkout."

# Root is asked for only when something is missing, since every later run finds it all in place.
sudo_() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }

step "System libraries"
if pkg-config --exists webkit2gtk-4.1 gtk-layer-shell-0 alsa dbus-1 2>/dev/null; then
  echo "already installed"
elif command -v apt-get >/dev/null 2>&1; then
  sudo_ apt-get update
  sudo_ apt-get install -y build-essential curl git pkg-config libdbus-1-dev libwebkit2gtk-4.1-dev \
    libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev libgtk-layer-shell-dev libasound2-dev python3
elif command -v dnf >/dev/null 2>&1; then
  sudo_ dnf group install -y c-development
  sudo_ dnf install -y curl git pkgconf-pkg-config dbus-devel webkit2gtk4.1-devel gtk3-devel \
    libappindicator-gtk3-devel librsvg2-devel gtk-layer-shell-devel alsa-lib-devel python3
elif command -v pacman >/dev/null 2>&1; then
  sudo_ pacman -S --needed --noconfirm base-devel curl git dbus webkit2gtk-4.1 gtk3 \
    libappindicator-gtk3 librsvg gtk-layer-shell alsa-lib python
else
  fail "no apt, dnf or pacman here; install the libraries in linux/README.md by hand and run this again."
fi

step "Node and Rust"
command -v node >/dev/null 2>&1 || fail "Node 22 or later is not on PATH; install it, for example with nvm, and run this again."
major=$(node -p 'process.versions.node.split(".")[0]')
[ "$major" -ge 22 ] || fail "Node $major is too old, since the runtime needs Node 22 or later."
command -v corepack >/dev/null 2>&1 || npm install -g corepack
if ! command -v cargo >/dev/null 2>&1; then
  [ -x "$HOME/.cargo/bin/cargo" ] || curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal
  PATH="$HOME/.cargo/bin:$PATH"
fi
echo "node $(node -v), $(cargo --version)"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

step "memnox-runtime"
if [ -f "$runtime/packages/core/src/wire.ts" ]; then
  runtime=$(cd "$runtime" && pwd)
  # Each repo runs under the pnpm its own packageManager pins, since the two pin different versions.
  (cd "$runtime" && corepack pnpm install --frozen-lockfile && corepack pnpm build)
  # A debug build runs this checkout's CLI rather than an npm memnox, which a release never does.
  export MEMNOX_RUNTIME="$runtime" MEMNOX_RUNTIME_DIR="$runtime"
else
  echo "no checkout beside this repo, so the wire comes from npm and the app installs memnox on its first run"
fi

step "Allow once through polkit"
policy=/usr/share/polkit-1/actions/org.memnox.desktop.policy
if cmp -s "$repo/linux/packaging/org.memnox.desktop.policy" "$policy"; then
  echo "already installed"
else
  sudo_ install -m 644 "$repo/linux/packaging/org.memnox.desktop.policy" "$policy"
fi

step "Speech libraries"
# Fetched once outside target, so a cargo clean never deletes what the build links against.
sherpa=$(ls -d "$app"/.sherpa/sherpa-onnx/sherpa-onnx-v*/lib 2>/dev/null | head -1 || true)
if [ -z "$sherpa" ]; then
  sh "$app/scripts/sherpa-libs.sh"
  sherpa=$(ls -d "$app"/.sherpa/sherpa-onnx/sherpa-onnx-v*/lib | head -1)
else
  echo "already in $sherpa"
fi
export SHERPA_ONNX_LIB_DIR="$sherpa"

step "The app"
cd "$app"
corepack pnpm wire
corepack pnpm install --frozen-lockfile

step "Opening Memnox: the tray icon opens the panel, and Ctrl Alt Space opens the island"
exec corepack pnpm tauri dev "$@"

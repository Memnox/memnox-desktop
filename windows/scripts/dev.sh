#!/bin/sh
# Builds and opens Memnox for Windows from source, for working on it, with nothing else to clone.
# From Git Bash, since the app's own build steps are shell scripts:
#   sh windows/scripts/dev.sh
# What is missing of Node, Rust and Visual Studio's C++ build tools is installed with winget, the wire
# comes from npm and the app installs memnox on its first run, so this repo is the only clone needed.
# A memnox-runtime checkout beside this repo, or named by MEMNOX_RUNTIME, is built and run instead,
# for working on both at once. A step already done is skipped, so it is also the command to run every day.
set -eu

fail() { printf 'memnox dev: %s\n' "$1" >&2; exit 1; }
step() { printf '\n==> %s\n' "$1"; }

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) ;;
  *) fail "this builds Memnox for Windows, so it runs in Git Bash on Windows." ;;
esac

repo=$(cd "$(dirname "$0")/../.." && pwd)
app="$repo/shared/tauri-core"
runtime=${MEMNOX_RUNTIME:-$repo/../memnox-runtime}
[ -n "${MEMNOX_RUNTIME:-}" ] && [ ! -f "$runtime/packages/core/src/wire.ts" ] &&
  fail "MEMNOX_RUNTIME names $runtime, which is not a memnox-runtime checkout."

# A tool winget installs is on the PATH of the next window only, so the run stops there and asks for one.
installed=no
winget_() {
  command -v winget >/dev/null 2>&1 || fail "winget is missing, so install $1 by hand as windows/README.md says and run this again."
  winget install --exact --id "$@" --accept-package-agreements --accept-source-agreements
  installed=yes
}

step "Visual Studio's C++ build tools"
vswhere="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
if [ -x "$vswhere" ] && [ -n "$("$vswhere" -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)" ]; then
  echo "already installed"
else
  winget_ Microsoft.VisualStudio.2022.BuildTools \
    --override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --wait"
fi

step "Node and Rust"
command -v node >/dev/null 2>&1 || winget_ OpenJS.NodeJS.LTS
command -v cargo >/dev/null 2>&1 || [ -x "$HOME/.cargo/bin/cargo.exe" ] || winget_ Rustlang.Rustup
if [ "$installed" = yes ]; then
  fail "installed what was missing; open a new Git Bash so it is on the PATH, and run this again."
fi
PATH="$HOME/.cargo/bin:$PATH"
major=$(node -p 'process.versions.node.split(".")[0]')
[ "$major" -ge 22 ] || fail "Node $major is too old, since the runtime needs Node 22 or later."
command -v corepack >/dev/null 2>&1 || npm install -g corepack
rustc -vV | grep -q '^host: .*msvc' || fail "Rust's host is not MSVC; run rustup default stable-msvc and run this again."
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

step "The app"
cd "$app"
corepack pnpm wire
corepack pnpm install --frozen-lockfile

step "Opening Memnox: the tray icon opens the panel, and Ctrl Alt Space opens the island"
exec corepack pnpm tauri dev "$@"

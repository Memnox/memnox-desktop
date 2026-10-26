#!/bin/sh
# Builds memnox-runtime's core and copies its dist into .runtime, so `@memnox/core/wire` resolves to
# the runtime's own build, the same files the npm package ships, and the wire is imported rather than
# copied by hand. A copy rather than a link, since Git Bash on Windows copies a link anyway.
# MEMNOX_RUNTIME names the checkout; the default is the sibling of memnox-desktop.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
runtime=${MEMNOX_RUNTIME:-$here/../../../memnox-runtime}
if [ ! -f "$runtime/packages/core/src/wire.ts" ]; then
  echo "memnox-runtime with packages/core/src/wire.ts not found at $runtime; clone it beside this repo with" >&2
  echo "  git clone https://github.com/Memnox/memnox.git memnox-runtime" >&2
  echo "or set MEMNOX_RUNTIME to where it is" >&2
  exit 1
fi
runtime=$(cd "$runtime" && pwd)
if ! command -v corepack >/dev/null 2>&1; then
  echo "corepack is not on PATH, and the runtime needs the pnpm it pins; Node 25 and later need npm install -g corepack" >&2
  exit 1
fi
# The runtime runs under the pnpm its own packageManager names, since an older pnpm misreads its lockfile.
rpnpm() { (cd "$runtime" && COREPACK_ENABLE_DOWNLOAD_PROMPT=0 corepack pnpm "$@"); }
if [ ! -d "$runtime/node_modules" ]; then
  rpnpm install --frozen-lockfile
fi
rpnpm --filter @memnox/core build >/dev/null
rm -rf "$here/.runtime"
mkdir -p "$here/.runtime/packages/core"
cp -R "$runtime/packages/core/dist" "$here/.runtime/packages/core/dist"
echo "copied the wire from $runtime"

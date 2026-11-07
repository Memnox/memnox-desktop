#!/bin/sh
# Puts memnox-runtime's built core into .runtime, so `@memnox/core/wire` resolves to the runtime's own
# build and the wire is imported rather than copied by hand. A copy rather than a link, since Git Bash
# on Windows copies a link anyway.
# With a memnox-runtime checkout, named by MEMNOX_RUNTIME or beside memnox-desktop, it builds that one,
# for working on both at once. Without one it takes the core published to npm, the same release the
# app installs on its first run, so working on the desktop alone needs no second clone.
# MEMNOX_CORE_VERSION picks another published version than latest.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
runtime=${MEMNOX_RUNTIME:-$here/../../../memnox-runtime}

if [ -f "$runtime/packages/core/src/wire.ts" ]; then
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
  dist="$runtime/packages/core/dist"
  from="the checkout $runtime"
elif [ -n "${MEMNOX_RUNTIME:-}" ]; then
  echo "MEMNOX_RUNTIME names $runtime, which has no packages/core/src/wire.ts" >&2
  exit 1
else
  # Only the package is unpacked and none of its dependencies installed, since the wire imports none of them.
  work=$(mktemp -d "${TMPDIR:-/tmp}/memnox-wire.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  tarball=$(cd "$work" && npm pack --silent "@memnox/core@${MEMNOX_CORE_VERSION:-latest}")
  tar -xzf "$work/$tarball" -C "$work"
  dist="$work/package/dist"
  from="npm, $(node -p 'require(process.argv[1]).version' "$work/package/package.json")"
fi

rm -rf "$here/.runtime"
mkdir -p "$here/.runtime/packages/core"
cp -R "$dist" "$here/.runtime/packages/core/dist"
echo "copied the wire from $from"

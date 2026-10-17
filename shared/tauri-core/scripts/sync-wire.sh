#!/bin/sh
# Builds memnox-runtime's core and copies its dist into .runtime, so `@memnox/core/wire` resolves to
# the runtime's own build, the same files the npm package ships, and the wire is imported rather than
# copied by hand. A copy rather than a link, since Git Bash on Windows copies a link anyway.
# MEMNOX_RUNTIME names the checkout; the default is the sibling of memnox-desktop.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
runtime=${MEMNOX_RUNTIME:-$here/../../../memnox-runtime}
if [ ! -f "$runtime/packages/core/src/wire.ts" ]; then
  echo "memnox-runtime with packages/core/src/wire.ts not found at $runtime; set MEMNOX_RUNTIME" >&2
  exit 1
fi
runtime=$(cd "$runtime" && pwd)
if [ ! -d "$runtime/node_modules" ]; then
  (cd "$runtime" && pnpm install --frozen-lockfile)
fi
(cd "$runtime" && pnpm --filter @memnox/core build >/dev/null)
rm -rf "$here/.runtime"
mkdir -p "$here/.runtime/packages/core"
cp -R "$runtime/packages/core/dist" "$here/.runtime/packages/core/dist"
echo "copied the wire from $runtime"

#!/bin/sh
# Refreshes shared/wire, the copy of memnox-runtime's built wire this repo keeps, so `@memnox/core/wire`
# resolves inside this repo and a clone builds with no second repo and no network. Run it when the
# runtime's wire changed, and commit what it changes along with the code that needs it.
# With a memnox-runtime checkout, named by MEMNOX_RUNTIME or beside memnox-desktop, it builds that one,
# for working on both at once. MEMNOX_CORE_VERSION takes a core published to npm instead, by version or
# `latest`. With neither there is nothing newer to copy, so the copy this repo keeps stands.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
runtime=${MEMNOX_RUNTIME:-$here/../../../memnox-runtime}
out="$here/../wire"

if [ -n "${MEMNOX_CORE_VERSION:-}" ]; then
  # Only the package is unpacked and none of its dependencies installed, since the wire imports none of them.
  work=$(mktemp -d "${TMPDIR:-/tmp}/memnox-wire.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  tarball=$(cd "$work" && npm pack --silent "@memnox/core@$MEMNOX_CORE_VERSION")
  tar -xzf "$work/$tarball" -C "$work"
  dist="$work/package/dist"
  from="npm, $(node -p 'require(process.argv[1]).version' "$work/package/package.json")"
elif [ -f "$runtime/packages/core/src/wire.ts" ]; then
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
  echo "no memnox-runtime checkout and no MEMNOX_CORE_VERSION, so shared/wire stays as this repo keeps it"
  exit 0
fi

node "$here/scripts/copy-wire.mjs" "$dist" "$out" >/dev/null
echo "copied the wire from $from into shared/wire"

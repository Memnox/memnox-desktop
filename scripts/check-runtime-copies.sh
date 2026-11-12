#!/bin/sh
# Says which of this repo's copies of memnox-runtime fell behind a runtime checkout: the vision, the protocol
# vectors, the ux contract, the Noise layer and the built wire. A pull request never runs this, since it is
# built from the copies alone and must pass or fail on what it holds. The Runtime copies workflow runs it
# against the runtime's main, and a release runs it before it builds.
#   MEMNOX_RUNTIME=../memnox-runtime sh scripts/check-runtime-copies.sh
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
runtime=${MEMNOX_RUNTIME:-$repo/../memnox-runtime}
[ -f "$runtime/packages/core/src/wire.ts" ] || { echo "no memnox-runtime checkout at $runtime; set MEMNOX_RUNTIME" >&2; exit 1; }
runtime=$(cd "$runtime" && pwd)
behind=0

# One copied file against the runtime's, each named by its path in its own repo.
same() {
  if [ ! -f "$runtime/$2" ]; then
    echo "behind or ahead: the runtime has no $2, which $1 is a copy of"
    behind=1
  elif ! cmp -s "$repo/$1" "$runtime/$2"; then
    echo "differs: $1 from the runtime's $2"
    behind=1
  fi
}

same VISION.md VISION.md
same shared/vectors/protocol.json vectors/protocol.json
same shared/ux/contract.json docs/ux/contract.json
# The Noise layer's Rust is formatted by this repo's own rustfmt, so its bytes never match the runtime's; the suite
# of vectors both must pass is what is held to the runtime's, byte for byte.
same shared/tauri-core/crates/desktop-noise/tests/vectors/memnox-suite.json native/noise/tests/vectors/memnox-suite.json

# The wire is built before it is compared, under the pnpm the runtime pins.
work=$(mktemp -d "${TMPDIR:-/tmp}/memnox-copies.XXXXXX")
trap 'rm -rf "$work"' EXIT
(
  cd "$runtime"
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  [ -d node_modules ] || corepack pnpm install --frozen-lockfile >/dev/null
  corepack pnpm --filter @memnox/core build >/dev/null
)
node "$repo/shared/tauri-core/scripts/copy-wire.mjs" "$runtime/packages/core/dist" "$work/wire" >/dev/null
if ! diff -r -x README.md "$repo/shared/wire" "$work/wire" >/dev/null; then
  echo "differs: shared/wire from the wire the runtime builds; run pnpm wire in shared/tauri-core"
  behind=1
fi

if [ "$behind" -eq 0 ]; then
  echo "every copy matches $runtime"
else
  echo "Refresh each copy named above from the runtime, or land the runtime's side first if this repo is the one ahead."
  exit 1
fi

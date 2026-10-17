#!/bin/sh
# Copies the protocol vectors memnox-runtime writes, so every desktop app is tested against what the daemon builds.
# Run it after the runtime's `pnpm vectors`, never edit the copy by hand, and commit the copy with the change it follows.
set -eu
here="$(cd "$(dirname "$0")/../.." && pwd)"
runtime="${MEMNOX_RUNTIME:-$here/../memnox-runtime}"
from="$runtime/vectors/protocol.json"
if [ ! -f "$from" ]; then
  echo "no vectors at $from; run pnpm vectors in memnox-runtime, or set MEMNOX_RUNTIME" >&2
  exit 1
fi
mkdir -p "$here/shared/vectors"
cp "$from" "$here/shared/vectors/protocol.json"
echo "copied $from"

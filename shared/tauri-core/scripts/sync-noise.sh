#!/bin/sh
# Copies memnox-runtime's Noise layer into crates/desktop-noise, so this app runs the same snow code the
# runtime, the Mac and the phones run. A copy rather than a path dependency, since CI checks the runtime
# out inside this repository while a developer keeps it beside it.
# MEMNOX_RUNTIME names the checkout; the default is the sibling of memnox-desktop.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
runtime=${MEMNOX_RUNTIME:-$here/../../../memnox-runtime}
noise="$runtime/native/noise"
if [ ! -f "$noise/src/core.rs" ]; then
  echo "memnox-runtime with native/noise/src/core.rs not found at $runtime; set MEMNOX_RUNTIME" >&2
  exit 1
fi
crate="$here/crates/desktop-noise"
cp "$noise/src/core.rs" "$crate/src/core.rs"
cp "$noise/tests/vectors.rs" "$crate/tests/vectors.rs"
mkdir -p "$crate/tests/vectors"
cp "$noise/tests/vectors/memnox-suite.json" "$crate/tests/vectors/memnox-suite.json"
echo "copied the Noise layer from $noise"

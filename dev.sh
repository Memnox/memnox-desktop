#!/bin/sh
# Builds and opens the Memnox app for this computer from this checkout, for working on it:
#   sh dev.sh
# It runs the Mac, the Linux or the Windows script, each of which needs no other repository: the
# runtime comes from its newest published release unless a memnox-runtime checkout sits beside this one.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
case "$(uname -s)" in
  Darwin) exec sh "$here/macos/scripts/dev.sh" "$@" ;;
  Linux) exec sh "$here/linux/scripts/dev.sh" "$@" ;;
  MINGW* | MSYS* | CYGWIN*) exec sh "$here/windows/scripts/dev.sh" "$@" ;;
  *) echo "memnox dev: no Memnox app builds on $(uname -s)" >&2; exit 1 ;;
esac

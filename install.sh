#!/bin/sh
# Installs the Memnox app for this computer, the one line memnox.com hands out:
#   curl -fsSL https://memnox.com/install | sh
# It runs the Mac or the Linux installer from this repository, and each of those checks its download before installing.
set -eu

BASE="https://raw.githubusercontent.com/Memnox/memnox-desktop/main"

case "$(uname -s)" in
  Darwin) platform=macos ;;
  Linux) platform=linux ;;
  *)
    printf 'memnox install: on Windows, download the installer from https://memnox.com/download/windows\n' >&2
    exit 1
    ;;
esac

curl -fsSL --retry 3 "$BASE/$platform/scripts/install.sh" | sh

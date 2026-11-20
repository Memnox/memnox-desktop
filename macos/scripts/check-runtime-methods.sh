#!/bin/sh
# Stops a release whose bundled runtime does not serve every daemon method this app calls. The app is built against
# the runtime's main, while the image carries the newest runtime published to npm, so a feature merged on both sides
# but not yet released by the runtime would ship broken without this: the app would only hear "unknown method".
#   sh scripts/check-runtime-methods.sh <the installed memnox package folder>
set -e
PACKAGE="$1"
[ -d "$PACKAGE" ] || { echo "usage: scripts/check-runtime-methods.sh <memnox package folder>" >&2; exit 1; }
cd "$(dirname "$0")/.."

PROTOCOL=Sources/MemnoxVoiceCore/Domain/SharedKernel/DaemonProtocol.swift
# Every raw value of the app's DaemonMethod enum, which is the whole list of methods it can send.
METHODS="$(sed -n '/enum DaemonMethod/,/^}/p' "$PROTOCOL" | sed -n 's/.*case [A-Za-z0-9]* = "\([a-z][a-z0-9-]*\)".*/\1/p')"
[ -n "$METHODS" ] || { echo "no methods read from $PROTOCOL" >&2; exit 1; }

MISSING=""
for method in $METHODS; do
  grep -rqF -e "'$method'" -e "\"$method\"" --include='*.js' "$PACKAGE" || MISSING="$MISSING $method"
done
if [ -n "$MISSING" ]; then
  echo "the runtime in this image does not serve:$MISSING" >&2
  echo "Release the runtime with those methods to npm first, then build the image again." >&2
  exit 1
fi
echo "the bundled runtime serves all $(echo "$METHODS" | wc -l | tr -d ' ') methods this app calls"

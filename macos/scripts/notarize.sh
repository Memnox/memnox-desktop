#!/bin/sh
# Notarizes one app or disk image with Apple and staples the ticket to it, so Gatekeeper opens it on any Mac, offline
# included. An app goes up zipped, since the notary service takes a zip, a disk image or a package.
#
# The credentials are either a profile `xcrun notarytool store-credentials` saved in this Mac's keychain:
#   MEMNOX_NOTARY_PROFILE=memnox scripts/notarize.sh build/Memnox.app
# or an App Store Connect API key, which is how CI signs in:
#   MEMNOX_NOTARY_KEY=AuthKey_XXXX.p8 MEMNOX_NOTARY_KEY_ID=XXXX MEMNOX_NOTARY_ISSUER=<uuid> scripts/notarize.sh ...
set -e
TARGET="$1"
[ -e "$TARGET" ] || { echo "usage: scripts/notarize.sh <Memnox.app or Memnox.dmg>" >&2; exit 1; }

if [ -n "${MEMNOX_NOTARY_PROFILE:-}" ]; then
  set -- --keychain-profile "$MEMNOX_NOTARY_PROFILE"
elif [ -n "${MEMNOX_NOTARY_KEY:-}" ] && [ -n "${MEMNOX_NOTARY_KEY_ID:-}" ] && [ -n "${MEMNOX_NOTARY_ISSUER:-}" ]; then
  set -- --key "$MEMNOX_NOTARY_KEY" --key-id "$MEMNOX_NOTARY_KEY_ID" --issuer "$MEMNOX_NOTARY_ISSUER"
else
  echo "no notary credentials: set MEMNOX_NOTARY_PROFILE, or MEMNOX_NOTARY_KEY, MEMNOX_NOTARY_KEY_ID and MEMNOX_NOTARY_ISSUER" >&2
  exit 1
fi

UPLOAD="$TARGET"
WORK=""
case "$TARGET" in
  *.app)
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    UPLOAD="$WORK/$(basename "$TARGET" .app).zip"
    ditto -c -k --keepParent "$TARGET" "$UPLOAD"
    ;;
esac

echo "Notarizing $TARGET"
# The log is fetched on a refusal, since the status alone never says which file Apple turned down.
OUT="$(xcrun notarytool submit "$UPLOAD" "$@" --wait --output-format plist)" || true
STATUS="$(echo "$OUT" | plutil -extract status raw -o - - 2>/dev/null || true)"
ID="$(echo "$OUT" | plutil -extract id raw -o - - 2>/dev/null || true)"
if [ "$STATUS" != Accepted ]; then
  echo "Apple did not accept $TARGET: ${STATUS:-no answer}" >&2
  [ -n "$ID" ] && xcrun notarytool log "$ID" "$@" >&2
  exit 1
fi
xcrun stapler staple "$TARGET"
echo "$TARGET is notarized and stapled"

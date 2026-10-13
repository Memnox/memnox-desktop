#!/bin/sh
# Makes a local code signing identity, once, so every build of Memnox.app is the same app to macOS.
# Signed ad hoc, each build is a stranger, and Accessibility and Automation are asked for again: the switch
# shows on in System Settings while AXIsProcessTrusted says no, which is what "not allowed to type yet" means.
set -e
NAME="Memnox Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# Only a valid identity counts: a certificate left without its key or its trust signs apps macOS then treats as strangers.
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "$NAME is already in your keychain."
  exit 0
fi
# Whatever is left of an earlier one goes first, or the import collides with it and the trust never takes.
while security delete-identity -c "$NAME" >/dev/null 2>&1; do :; done
while security delete-certificate -c "$NAME" >/dev/null 2>&1; do :; done
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
cat > "$DIR/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$DIR/cert.conf" \
  -keyout "$DIR/key.pem" -out "$DIR/cert.pem" >/dev/null 2>&1
openssl pkcs12 -export -legacy -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
  -out "$DIR/identity.p12" -passout pass:memnox >/dev/null 2>&1 \
  || openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
       -out "$DIR/identity.p12" -passout pass:memnox
security import "$DIR/identity.p12" -k "$KEYCHAIN" -P memnox -T /usr/bin/codesign
# Trusted for code signing only; macOS asks for your password once to allow it. A cancelled prompt leaves the
# certificate untrusted, which is worse than none: it exists, so nothing makes it again, and nothing can sign with it.
if ! security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$DIR/cert.pem"; then
  echo "The trust was not set, so $NAME cannot sign yet." >&2
fi
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "Made $NAME. Run scripts/bundle.sh, then allow Memnox under Accessibility one last time."
  exit 0
fi
cat >&2 <<WHY

$NAME is in your keychain but macOS does not trust it for code signing, so builds would still be
signed ad hoc and Accessibility would forget Memnox on every rebuild. To finish by hand:
  1. Open Keychain Access, pick the login keychain, and find "$NAME" under My Certificates.
  2. Open it, expand Trust, and set Code Signing to Always Trust. Enter your password when asked.
  3. Run scripts/signing-setup.sh again, which will report it as already there, then scripts/bundle.sh.
WHY
exit 1

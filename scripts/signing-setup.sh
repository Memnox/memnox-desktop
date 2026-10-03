#!/bin/sh
# Makes a local code signing identity, once, so every build of Memnox.app is the same app to macOS.
# Signed ad hoc, each build is a stranger, and Accessibility and Automation are asked for again.
set -e
NAME="Memnox Local Signing"
if security find-identity -p codesigning | grep -q "$NAME"; then
  echo "$NAME is already in your keychain."
  exit 0
fi
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
security import "$DIR/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P memnox -T /usr/bin/codesign
# Trusted for code signing only; macOS asks for your password once to allow it.
security add-trusted-cert -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$DIR/cert.pem"
echo "Made $NAME. Run scripts/bundle.sh, then allow Memnox under Accessibility one last time."

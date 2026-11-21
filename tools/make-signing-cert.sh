#!/bin/bash
# Creates a self-signed code-signing identity in the login keychain, used by build.sh.
# A stable signature means macOS keeps the Accessibility permission across rebuilds
# (with ad-hoc signing every build looks like a brand-new app).
# Safe to re-run: it does nothing if the identity already exists.
set -euo pipefail

NAME="${1:-MiniDict Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Identity \"$NAME\" already exists."
    exit 0
fi

# Apple's LibreSSL writes PKCS#12 files that `security import` reads without fuss.
OPENSSL=/usr/bin/openssl
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
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
subjectKeyIdentifier = hash
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null

# Throwaway passphrase: the .p12 only exists inside $TMP for the import below.
PASS="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/id.p12" -passout "pass:$PASS"

# -T lets codesign use the private key without a keychain prompt on every build.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Created \"$NAME\":"
security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME" || true

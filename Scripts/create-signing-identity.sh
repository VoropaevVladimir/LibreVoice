#!/bin/bash
#
# Creates the local "LibreVoice Developer" code-signing identity, once per machine.
#
# See Scripts/sign.sh for why signing matters at all. In short: without a certificate the
# app is identified to macOS by the hash of its executable, so every rebuild loses its
# Accessibility and Microphone permissions.
#
# The identity lives in its **own keychain**, not the login keychain. That is not tidiness:
# `codesign` can only use a private key whose partition list allows it, and updating the
# partition list requires the keychain's password. Creating a dedicated keychain means the
# password is one this script generates, so the whole setup runs without ever asking for —
# or handling — the user's login password. It is the same approach CI machines use.
#
# The certificate is self-signed and trusted by nothing. That is sufficient for what it is
# for: giving the app a *stable* identity so its permissions survive updates. Shipping to
# other people additionally needs a genuine Apple Developer ID, for notarisation and to
# stop Gatekeeper warning about an unidentified developer.
#
# To undo everything this creates:
#     security delete-keychain librevoice-signing.keychain
set -euo pipefail

KEYCHAIN="librevoice-signing.keychain"
IDENTITY="LibreVoice Developer"
# Where the keychain's password is kept so future signings can unlock it non-interactively.
# The password guards only a throwaway self-signed key that is trusted by nothing, so a
# 0600 file in the user's home is proportionate — and it is what lets `sign.sh` run in a
# fresh shell (or after a reboot) without a GUI prompt. Kept out of the source tree.
PASSWORD_FILE="$HOME/.librevoice/signing-keychain-password"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    echo "'$IDENTITY' already exists in $KEYCHAIN — nothing to do."
    exit 0
fi

KEYCHAIN_PASSWORD="lv-$(openssl rand -hex 16)"
TRANSFER_PASSWORD="transfer"

cat > "$WORKDIR/cert.cnf" <<'CONFIG'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = LibreVoice Developer
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONFIG

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -config "$WORKDIR/cert.cnf" 2>/dev/null

# The legacy algorithms are required: OpenSSL 3 defaults to a PKCS#12 MAC that macOS's
# Security framework rejects with "MAC verification failed".
openssl pkcs12 -export -out "$WORKDIR/identity.p12" \
    -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
    -passout "pass:$TRANSFER_PASSWORD" -name "$IDENTITY" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES 2>/dev/null

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
# No auto-lock timeout: the keychain holds nothing sensitive, and a locked keychain is
# exactly what broke signing in a later session. `sign.sh` unlocks it anyway, but leaving
# it unlocked means a build never even has to.
security set-keychain-settings "$KEYCHAIN"
security import "$WORKDIR/identity.p12" -k "$KEYCHAIN" -P "$TRANSFER_PASSWORD" -T /usr/bin/codesign -A
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s login.keychain-db "$KEYCHAIN"

# Persist the password so `sign.sh` can unlock the keychain in any future shell.
mkdir -p "$(dirname "$PASSWORD_FILE")"
printf '%s' "$KEYCHAIN_PASSWORD" > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

echo "created '$IDENTITY' in $KEYCHAIN"
security find-identity -p codesigning "$KEYCHAIN" | grep "$IDENTITY"

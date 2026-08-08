#!/bin/bash
#
# Signs a built LibreVoice.app with the local "LibreVoice Developer" identity.
#
# Why this exists
# ---------------
# An ad-hoc signature (`codesign -s -`, what Xcode does with no team) identifies the app
# to macOS *by the hash of its executable*. Every rebuild therefore looks like a brand
# new application: the Accessibility and Microphone grants in System Settings stop
# applying, the old row stays there switched on, and dictation silently loses the right
# to type into other apps. That is not a development annoyance — it is what every user
# would hit on every update.
#
# Signing with a certificate changes the app's designated requirement from
#
#     cdhash H"…"                                  (a specific build)
#
# to
#
#     identifier "com.librevoice.LibreVoice" and certificate leaf = H"…"
#
# which is stable across rebuilds, so the permissions persist. This is what a real
# Developer ID does; the certificate here is self-signed, which is enough for the app to
# keep its permissions on this Mac. Distribution to other people still needs a genuine
# Developer ID (for notarisation and Gatekeeper).
#
# Usage:  Scripts/sign.sh /path/to/LibreVoice.app
set -euo pipefail

APP="${1:?usage: sign.sh /path/to/LibreVoice.app}"
IDENTITY="LibreVoice Developer"
KEYCHAIN="librevoice-signing.keychain"
PASSWORD_FILE="$HOME/.librevoice/signing-keychain-password"

if ! security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    echo "error: signing identity '$IDENTITY' not found in $KEYCHAIN" >&2
    echo "       run Scripts/create-signing-identity.sh first" >&2
    exit 1
fi

# Unlock the keychain first. A locked keychain makes codesign fail with the opaque
# `errSecInternalComponent` — it cannot reach the private key — which is precisely what
# happens in a shell that did not create the keychain (a new session, or after a reboot).
# The password was stored by create-signing-identity.sh for exactly this.
if [ -f "$PASSWORD_FILE" ]; then
    security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN"
else
    echo "warning: $PASSWORD_FILE not found; if signing fails, re-run create-signing-identity.sh" >&2
fi

# Entitlements come from a file under source control, NOT from the built app.
#
# This script used to read them back out of whatever Xcode had signed and re-apply them.
# That silently carried `com.apple.security.get-task-allow` into release builds — the
# debug entitlement that lets any process running as this user attach a debugger to
# LibreVoice and read its memory, including microphone audio, transcripts and the personal
# prompt. Copying entitlements forward means never noticing what you are copying; stating
# them explicitly means the list is reviewable. See release.entitlements for what is
# deliberately absent and why.
ENTITLEMENTS="$(cd "$(dirname "$0")" && pwd)/release.entitlements"

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "error: $ENTITLEMENTS is missing" >&2
    exit 1
fi

# Nested code first: macOS verifies inside out, and a framework signed by a different
# identity than its host is rejected outright. Every embedded framework is signed —
# today that is whisper.framework and llama.framework, and the loop keeps this script
# correct when the next one arrives.
for FRAMEWORK in "$APP"/Contents/Frameworks/*.framework; do
    codesign --force --sign "$IDENTITY" --options runtime "$FRAMEWORK/Versions/A"
done

codesign --force --sign "$IDENTITY" --options runtime \
    --entitlements "$ENTITLEMENTS" "$APP"

echo "signed: $APP"
codesign -d -r- "$APP" 2>&1 | grep designated

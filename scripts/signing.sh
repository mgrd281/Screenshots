#!/bin/bash
# Signs Snapfly with the Developer ID and has Apple notarize it, in the
# Build Snapfly workflow. Everything comes from one secret, SNAPFLY_SIGNING,
# which scripts/mac-signing.sh prepares on the owner's Mac: the App Store
# Connect API key with its ids, and the Developer ID key and certificate.
#
#   scripts/signing.sh developer-id   Puts the Developer ID in a temporary
#                                     keychain and sets SIGN_IDENTITY.
#   scripts/signing.sh notarize APP   Sends APP to Apple and staples the ticket.
#   scripts/signing.sh cleanup        Removes the keychain and the files.
set -euo pipefail
cd "$(dirname "$0")/.."

SSL=/usr/bin/openssl   # LibreSSL: its .p12 files are the kind Keychain imports.
TMP="${RUNNER_TEMP:-/tmp}/snapfly-signing"
KEYCHAIN="$TMP/signing.keychain-db"
mkdir -p "$TMP"
chmod 700 "$TMP"

setenv() { [ -n "${GITHUB_ENV:-}" ] && echo "$1=$2" >> "$GITHUB_ENV" || true; }

# One part of the secret: the lines after "# name", up to the next "# ".
part() {
  printf '%s\n' "$SNAPFLY_SIGNING" | tr -d '\r' \
    | awk -v name="# $1" '$0 == name { on = 1; next } /^# / { on = 0 } on && NF'
}

api_key_file() {
  local file="$TMP/AuthKey.p8"
  part api-key > "$file"
  chmod 600 "$file"
  echo "$file"
}

notary() { xcrun notarytool "$@" --key "$(api_key_file)" --key-id "$(part key-id)" --issuer "$(part issuer)"; }

case "${1:-}" in
  developer-id)
    part developer-id-key > "$TMP/key.pem"
    part developer-id-certificate > "$TMP/cert.pem"
    chmod 600 "$TMP/key.pem"
    if [ "$($SSL pkey -in "$TMP/key.pem" -pubout)" != "$($SSL x509 -in "$TMP/cert.pem" -noout -pubkey)" ]; then
      echo "::error::The key and the certificate in SNAPFLY_SIGNING do not belong together."
      exit 1
    fi

    # A temporary keychain on the search list, with Apple's intermediate
    # certificate so codesign can build the chain.
    password="$(uuidgen)"
    security create-keychain -p "$password" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
    security unlock-keychain -p "$password" "$KEYCHAIN"
    if curl -fsSL https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer -o "$TMP/ca.cer"; then
      security import "$TMP/ca.cer" -k "$KEYCHAIN" >/dev/null || true
    fi
    p12password="$(uuidgen)"
    $SSL pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/identity.p12" -passout "pass:$p12password"
    security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$p12password" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$KEYCHAIN" >/dev/null
    # shellcheck disable=SC2046
    security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
    rm -f "$TMP/identity.p12" "$TMP/key.pem"

    sha1="$($SSL x509 -in "$TMP/cert.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
    setenv SIGN_IDENTITY "$sha1"
    echo "Signing as $($SSL x509 -in "$TMP/cert.pem" -noout -subject)"
    ;;

  notarize)
    app="$2"
    ditto -c -k --keepParent "$app" "$TMP/notarize.zip"
    notary submit "$TMP/notarize.zip" --wait --timeout 30m --output-format json > "$TMP/notary.json" || true
    field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$TMP/notary.json" "$1" 2>/dev/null || true; }
    status="$(field status)"
    if [ "$status" != "Accepted" ]; then
      cat "$TMP/notary.json" || true
      id="$(field id)"
      if [ -n "$id" ]; then notary log "$id" || true; fi
      echo "::error::Apple did not accept Snapfly for notarization (status: ${status:-none})."
      exit 1
    fi
    xcrun stapler staple "$app"
    setenv NOTARIZED true
    ;;

  cleanup)
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
    rm -rf "$TMP"
    ;;

  *)
    echo "Usage: scripts/signing.sh developer-id|notarize APP|cleanup" >&2
    exit 1
    ;;
esac

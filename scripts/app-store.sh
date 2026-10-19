#!/bin/bash
# Builds the Mac App Store edition, signs it for the store and uploads it
# to App Store Connect, from the App Store workflow. It needs two secrets:
# SNAPFLY_SIGNING (scripts/mac-signing.sh) for the App Store Connect key,
# and SNAPFLY_STORE (scripts/mac-store-signing.sh) for the store keys and
# certificates. The app's record must exist in App Store Connect.
set -euo pipefail
cd "$(dirname "$0")/.."

SSL=/usr/bin/openssl   # LibreSSL: its .p12 files are the kind Keychain imports.
TMP="${RUNNER_TEMP:-/tmp}/snapfly-store"
KEYCHAIN="$TMP/store.keychain-db"
BUNDLE_ID="de.ghazarian.Snapfly"
APP="build/Snapfly.app"
PKG="build/Snapfly.pkg"
mkdir -p "$TMP"
chmod 700 "$TMP"

# One part of a secret: the lines after "# name", up to the next "# ".
part() {
  printf '%s\n' "$1" | tr -d '\r' | awk -v name="# $2" '$0 == name { on = 1; next } /^# / { on = 0 } on && NF'
}

if [ "${1:-}" = "cleanup" ]; then
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  rm -rf "$TMP"
  exit 0
fi

# The App Store Connect key, for asc.swift and for altool.
export ASC_KEY_ID ASC_ISSUER_ID ASC_KEY
ASC_KEY_ID="$(part "$SNAPFLY_SIGNING" key-id)"
ASC_ISSUER_ID="$(part "$SNAPFLY_SIGNING" issuer)"
ASC_KEY="$(part "$SNAPFLY_SIGNING" api-key)"
export API_PRIVATE_KEYS_DIR="$TMP/keys"
mkdir -p "$API_PRIVATE_KEYS_DIR"
printf '%s\n' "$ASC_KEY" > "$API_PRIVATE_KEYS_DIR/AuthKey_$ASC_KEY_ID.p8"

# The app's record comes first: without it there is nothing to upload to.
if ! APPLE_ID="$(swift scripts/asc.swift app "$BUNDLE_ID")"; then
  echo "::error::Create Snapfly in App Store Connect first (Apps, +, New App, bundle ID $BUNDLE_ID)."
  exit 1
fi

# Both identities in a temporary keychain, with Apple's intermediates.
password="$(uuidgen)"
security create-keychain -p "$password" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$password" "$KEYCHAIN"
for ca in AppleWWDRCAG3 AppleWWDRCAG6; do
  if curl -fsSL "https://www.apple.com/certificateauthority/$ca.cer" -o "$TMP/$ca.cer"; then
    security import "$TMP/$ca.cer" -k "$KEYCHAIN" >/dev/null || true
  fi
done
# Prints the certificate's common name, which signs by name.
add_identity() {
  part "$SNAPFLY_STORE" "$1-key" > "$TMP/key.pem"
  part "$SNAPFLY_STORE" "$1-certificate" > "$TMP/cert.pem"
  local p12password; p12password="$(uuidgen)"
  $SSL pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout "pass:$p12password"
  security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$p12password" \
    -T /usr/bin/codesign -T /usr/bin/productbuild >/dev/null
  rm -f "$TMP/key.pem" "$TMP/id.p12"
  # The subject reads "/CN=…/OU=…" or "CN = …, OU = …", depending on the tool.
  $SSL x509 -in "$TMP/cert.pem" -noout -subject | sed -n 's/.*CN *= *\([^/,]*\).*/\1/p' | sed 's/ *$//'
}
SIGNER="$(add_identity app-store)"
INSTALLER="$(add_identity installer)"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$KEYCHAIN" >/dev/null
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
TEAM="$(echo "$SIGNER" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"
echo "Signing as $SIGNER, packaging as $INSTALLER, team $TEAM"

# The profile that lets this certificate put this app in the store.
BUNDLE="$(swift scripts/asc.swift bundle-id "$BUNDLE_ID" Snapfly)"
CERT_ID="$(part "$SNAPFLY_STORE" app-store-id)"
swift scripts/asc.swift profile "$BUNDLE" "$CERT_ID" "Snapfly Mac App Store $CERT_ID" "$TMP/profile" >/dev/null

# Syncing with the iPhone, once the app's identifier has the iCloud container
# (SYNC.md): the profile then allows it, and the build names the container.
CONTAINER="iCloud.de.ghazarian.Snapfly"
security cms -D -i "$TMP/profile" > "$TMP/profile.plist"
CLOUD_ENTITLEMENTS=""
if /usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.icloud-container-identifiers" \
     "$TMP/profile.plist" 2>/dev/null | grep -qF "$CONTAINER"; then
  export SNAPFLY_CLOUD_CONTAINER="$CONTAINER"
  CLOUD_ENTITLEMENTS="<key>com.apple.developer.icloud-container-identifiers</key><array><string>$CONTAINER</string></array>
  <key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array>
  <key>com.apple.developer.icloud-container-environment</key><string>Production</string>"
  if /usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.aps-environment" "$TMP/profile.plist" >/dev/null 2>&1; then
    CLOUD_ENTITLEMENTS="$CLOUD_ENTITLEMENTS
  <key>com.apple.developer.aps-environment</key><string>production</string>"
  fi
  echo "The profile allows iCloud: this build can sync."
else
  echo "::warning::The app's identifier has no iCloud container yet (SYNC.md, section 5), so this build leaves syncing out."
fi

# Each upload needs a higher build number than the one before.
BUILD="$(( ${GITHUB_RUN_NUMBER:-1} + 100 ))"
STORE=1 BUILD_NUMBER="$BUILD" scripts/build-app.sh
scripts/check-private-apis.sh "$APP/Contents/MacOS/Snapfly"
cp "$TMP/profile" "$APP/Contents/embedded.provisionprofile"

# The sandbox, and only the doors Snapfly needs: folders the user picks,
# Pictures, where the Screenshot app saves for it, asking browsers which
# page is open, so the send button shows only on chat websites and the time
# stamp can name the page, asking the PTB's atomic clock for the time, and
# the microphone, for a recording with the voice when chosen.
cat > "$TMP/entitlements.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.files.user-selected.read-write</key><true/>
  <key>com.apple.security.files.bookmarks.app-scope</key><true/>
  <key>com.apple.security.assets.pictures.read-write</key><true/>
  <key>com.apple.security.automation.apple-events</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.device.audio-input</key><true/>
  <key>com.apple.security.temporary-exception.apple-events</key>
  <array>
    <string>com.apple.Safari</string>
    <string>com.apple.SafariTechnologyPreview</string>
    <string>com.google.Chrome</string>
    <string>com.google.Chrome.canary</string>
    <string>company.thebrowser.Browser</string>
    <string>com.microsoft.edgemac</string>
    <string>com.brave.Browser</string>
    <string>com.vivaldi.Vivaldi</string>
    <string>com.operasoftware.Opera</string>
  </array>
  <key>com.apple.application-identifier</key><string>$TEAM.$BUNDLE_ID</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM</string>
  $CLOUD_ENTITLEMENTS
</dict>
</plist>
PLIST
codesign --force --timestamp --options runtime --entitlements "$TMP/entitlements.plist" \
  --keychain "$KEYCHAIN" --sign "$SIGNER" "$APP"
codesign --verify --strict --verbose=2 "$APP"
productbuild --component "$APP" /Applications --keychain "$KEYCHAIN" --sign "$INSTALLER" "$PKG"

xcrun altool --upload-package "$PKG" --type macos --apple-id "$APPLE_ID" --bundle-id "$BUNDLE_ID" \
  --bundle-version "$BUILD" --bundle-short-version-string "$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)" \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
echo "Uploaded build $BUILD. It shows in App Store Connect, TestFlight, once Apple has processed it."

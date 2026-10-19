#!/bin/bash
# Builds the iPhone app, signs it for the App Store and uploads it to App
# Store Connect, from the iPhone App Store workflow. It needs two secrets:
# SNAPFLY_SIGNING (scripts/mac-signing.sh) for the App Store Connect key,
# and SNAPFLY_IPHONE (scripts/iphone-signing.sh) for the Apple Distribution
# key and certificate. Without the second it does nothing. The app's record
# in App Store Connect must have the iPhone added to it.
set -euo pipefail
cd "$(dirname "$0")/.."

SSL=/usr/bin/openssl   # LibreSSL: its .p12 files are the kind Keychain imports.
TMP="${RUNNER_TEMP:-/tmp}/snapfly-iphone"
KEYCHAIN="$TMP/iphone.keychain-db"
BUNDLE_ID="de.ghazarian.Snapfly"
OUT="build/iphone"
# Where Xcode looks for profiles: the first before Xcode 16, the second since.
PROFILES=("$HOME/Library/MobileDevice/Provisioning Profiles"
          "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles")

# One part of a secret: the lines after "# name", up to the next "# ".
part() {
  printf '%s\n' "$1" | tr -d '\r' | awk -v name="# $2" '$0 == name { on = 1; next } /^# / { on = 0 } on && NF'
}

if [ "${1:-}" = "cleanup" ]; then
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  if [ -f "$TMP/uuid" ]; then
    for folder in "${PROFILES[@]}"; do rm -f "$folder/$(cat "$TMP/uuid").mobileprovision"; done
  fi
  rm -rf "$TMP"
  exit 0
fi

if [ -z "${SNAPFLY_IPHONE:-}" ]; then
  echo "::notice::No SNAPFLY_IPHONE secret yet, so nothing is uploaded. Run scripts/iphone-signing.sh on the Mac to make it."
  exit 0
fi
mkdir -p "$TMP" "$OUT"
chmod 700 "$TMP"

# The App Store Connect key, for asc.swift and for altool.
export ASC_KEY_ID ASC_ISSUER_ID ASC_KEY
ASC_KEY_ID="$(part "$SNAPFLY_SIGNING" key-id)"
ASC_ISSUER_ID="$(part "$SNAPFLY_SIGNING" issuer)"
ASC_KEY="$(part "$SNAPFLY_SIGNING" api-key)"
export API_PRIVATE_KEYS_DIR="$TMP/keys"
mkdir -p "$API_PRIVATE_KEYS_DIR"
printf '%s\n' "$ASC_KEY" > "$API_PRIVATE_KEYS_DIR/AuthKey_$ASC_KEY_ID.p8"

# The Mac and the iPhone share one record, under the same bundle ID.
if ! APPLE_ID="$(swift scripts/asc.swift app "$BUNDLE_ID")"; then
  echo "::error::Create Snapfly in App Store Connect first (Apps, +, New App, bundle ID $BUNDLE_ID)."
  exit 1
fi

# The identity in a temporary keychain, with Apple's intermediates.
password="$(uuidgen)"
security create-keychain -p "$password" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$password" "$KEYCHAIN"
for ca in AppleWWDRCAG3 AppleWWDRCAG6; do
  if curl -fsSL "https://www.apple.com/certificateauthority/$ca.cer" -o "$TMP/$ca.cer"; then
    security import "$TMP/$ca.cer" -k "$KEYCHAIN" >/dev/null || true
  fi
done
part "$SNAPFLY_IPHONE" iphone-key > "$TMP/key.pem"
part "$SNAPFLY_IPHONE" iphone-certificate > "$TMP/cert.pem"
p12password="$(uuidgen)"
$SSL pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout "pass:$p12password"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$p12password" -T /usr/bin/codesign >/dev/null
rm -f "$TMP/key.pem" "$TMP/id.p12"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$KEYCHAIN" >/dev/null
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
# The subject reads "/CN=…/OU=…" or "CN = …, OU = …", depending on the tool.
SIGNER="$($SSL x509 -in "$TMP/cert.pem" -noout -subject | sed -n 's/.*CN *= *\([^/,]*\).*/\1/p' | sed 's/ *$//')"
TEAM="$(echo "$SIGNER" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"
echo "Signing as $SIGNER, team $TEAM"

# The profile that lets this certificate put this app in the store, where
# Xcode finds it.
BUNDLE="$(swift scripts/asc.swift bundle-id "$BUNDLE_ID" Snapfly)"
CERT_ID="$(part "$SNAPFLY_IPHONE" iphone-id)"
PROFILE_NAME="Snapfly iPhone App Store $CERT_ID"
swift scripts/asc.swift profile "$BUNDLE" "$CERT_ID" "$PROFILE_NAME" "$TMP/profile.mobileprovision" IOS_APP_STORE >/dev/null
security cms -D -i "$TMP/profile.mobileprovision" > "$TMP/profile.plist"
/usr/libexec/PlistBuddy -c "Print :UUID" "$TMP/profile.plist" > "$TMP/uuid"
for folder in "${PROFILES[@]}"; do
  mkdir -p "$folder"
  cp "$TMP/profile.mobileprovision" "$folder/$(cat "$TMP/uuid").mobileprovision"
done

# Syncing with the Mac, once the app's identifier has the iCloud container
# (SYNC.md): the profile then allows it, so the build gets the entitlements,
# a line in Info.plist naming the container, and fetching in the background
# when iCloud says something changed.
CONTAINER="iCloud.de.ghazarian.Snapfly"
CLOUD_SETTINGS=()
CLOUD_EXPORT=""
if /usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.icloud-container-identifiers" \
     "$TMP/profile.plist" 2>/dev/null | grep -qF "$CONTAINER"; then
  PUSH=""
  if /usr/libexec/PlistBuddy -c "Print :Entitlements:aps-environment" "$TMP/profile.plist" >/dev/null 2>&1; then
    PUSH="<key>aps-environment</key><string>production</string>"
  fi
  cat > "$TMP/Snapfly.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.developer.icloud-container-identifiers</key><array><string>$CONTAINER</string></array>
  <key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array>
  $PUSH
</dict>
</plist>
PLIST
  # The app's own Info.plist (iOS/Info.plist, preparing photos in the
  # background), with the container and iCloud's notices added.
  cp iOS/Info.plist "$TMP/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SnapflyCloudContainer string $CONTAINER" "$TMP/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CKSharingSupported bool true" "$TMP/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes: string remote-notification" "$TMP/Info.plist"
  CLOUD_SETTINGS=(CODE_SIGN_ENTITLEMENTS="$TMP/Snapfly.entitlements" INFOPLIST_FILE="$TMP/Info.plist")
  CLOUD_EXPORT="<key>iCloudContainerEnvironment</key><string>Production</string>"
  echo "The profile allows iCloud: this build can sync."
else
  echo "::warning::The app's identifier has no iCloud container yet (SYNC.md, section 5), so this build leaves syncing out."
fi

# Each upload needs a higher build number than the one before. The version
# is the Mac's, from the VERSION file.
BUILD="$(( ${GITHUB_RUN_NUMBER:-1} + 100 ))"
xcodebuild -project iOS/Snapfly.xcodeproj -scheme Snapfly -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$OUT/Snapfly.xcarchive" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="$SIGNER" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN" \
  ${CLOUD_SETTINGS[@]+"${CLOUD_SETTINGS[@]}"} \
  MARKETING_VERSION="$(tr -d '[:space:]' < VERSION)" CURRENT_PROJECT_VERSION="$BUILD" -quiet archive

cat > "$TMP/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>$BUNDLE_ID</key><string>$PROFILE_NAME</string>
  </dict>
  <key>manageAppVersionAndBuildNumber</key><false/>
  $CLOUD_EXPORT
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/Snapfly.xcarchive" -exportPath "$OUT" \
  -exportOptionsPlist "$TMP/export.plist" -quiet
IPA="$OUT/Snapfly.ipa"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$OUT/Snapfly.xcarchive/Products/Applications/Snapfly.app/Info.plist")"

if ! xcrun altool --upload-package "$IPA" --type ios --apple-id "$APPLE_ID" --bundle-id "$BUNDLE_ID" \
     --bundle-version "$BUILD" --bundle-short-version-string "$VERSION" \
     --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"; then
  echo "::error::Apple did not take the upload. If it names the platform, add iOS to Snapfly in App Store Connect (the + beside macOS, top left), then run this again."
  exit 1
fi
echo "Uploaded iPhone build $BUILD. It shows in App Store Connect, TestFlight, once Apple has processed it."

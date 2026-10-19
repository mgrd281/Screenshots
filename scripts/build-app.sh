#!/bin/bash
# Builds Snapfly.app into ./build without needing Xcode.
# Usage: scripts/build-app.sh [debug|release]
# With STORE=1 it builds the Mac App Store edition (see Edition.swift),
# signed ad hoc for scripts/app-store.sh to sign. BUILD_NUMBER sets the
# build number, which App Store Connect wants higher at every upload.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Snapfly.app"
# Every edition carries the version in the VERSION file, and CHANGELOG.md
# says what it brings, so the build stops when that section is missing.
VERSION="$(tr -d '[:space:]' < VERSION)"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION should read like 1.2.3, not '$VERSION'" >&2
  exit 1
fi
if ! grep -qxF "## $VERSION" CHANGELOG.md; then
  echo "CHANGELOG.md has no '## $VERSION' section" >&2
  exit 1
fi
BUILD="${BUILD_NUMBER:-1}"
DEFINE=""
if [ -n "${STORE:-}" ]; then DEFINE="-Xswiftc -DAPP_STORE"; fi

# Builds one architecture and prints the binary's path.
# The Command Line Tools for macOS 27 ship an SDK whose SwiftUI needs a macro
# plugin they do not include. If the default SDK fails, fall back to the
# newest macOS 26 SDK installed alongside it.
build_arch() {
  local triple="$1-apple-macosx14.0"
  # shellcheck disable=SC2086
  if [ -z "${SDKROOT:-}" ] && ! swift build -c "$CONFIG" --triple "$triple" $DEFINE >&2; then
    FALLBACK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)"
    if [ -z "$FALLBACK" ]; then exit 1; fi
    echo "Retrying with $FALLBACK" >&2
    export SDKROOT="$FALLBACK"
  fi
  # shellcheck disable=SC2086
  if [ -n "${SDKROOT:-}" ]; then swift build -c "$CONFIG" --triple "$triple" $DEFINE >&2; fi
  # shellcheck disable=SC2086
  cp "$(swift build -c "$CONFIG" --triple "$triple" $DEFINE --show-bin-path)/Tendedero" "$OUT/Tendedero-$1"
}

# A universal binary, so it runs on Apple silicon and on Intel Macs, from
# macOS 14 Sonoma onwards.
OUT="$(mktemp -d)"
build_arch arm64
build_arch x86_64
lipo -create "$OUT/Tendedero-arm64" "$OUT/Tendedero-x86_64" -output "$OUT/Tendedero"
BIN="$OUT/Tendedero"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Snapfly"

# Icon
WORK="$(mktemp -d)"
# Drawn by scripts/make-icon.py; run it again after changing the design.
cp assets/icon.png "$WORK/icon.png"
ICONSET="$WORK/Snapfly.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Snapfly.icns"
rm -rf "$WORK"

# Translations: one folder per language, listed in Info.plist so macOS knows
# which languages the app speaks.
LANGUAGES=""
for dir in Sources/Tendedero/Resources/*.lproj; do
  cp -R "$dir" "$APP/Contents/Resources/"
  LANGUAGES="$LANGUAGES<string>$(basename "$dir" .lproj)</string>"
done

# The logos of WhatsApp, Gmail, GMX and WEB.DE, shown beside the paper plane.
cp -R assets/chat-logos "$APP/Contents/Resources/chat-logos"
rm -rf "$APP/Contents/Resources/chat-logos/source"

# The licence of the code this began as travels with every copy, as it asks.
cp LICENSE "$APP/Contents/Resources/LICENSE"

# Where share links are made, when the owner's Cloudflare account has them.
SHARE_URL="${SNAPFLY_SHARE_URL:-$(scripts/share-url.sh)}"
SHARE_ENTRY=""
if [ -n "$SHARE_URL" ]; then SHARE_ENTRY="<key>SnapflyShareURL</key><string>${SHARE_URL}</string>"; fi

# The Developer ID that signs this build, if there is one (or SIGN_IDENTITY).
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')}"

# Syncing with the iPhone through the owner's iCloud: only in a build allowed
# to use the iCloud container, the App Store edition (scripts/app-store.sh)
# or a Developer ID build with its profile (scripts/signing.sh cloud-profile).
# Info.plist names the container only then, as the app opens iCloud only
# when it is named, and opening it unentitled would stop the app.
CLOUD="${SNAPFLY_CLOUD_CONTAINER:-}"
PROFILE="${SNAPFLY_DIRECT_PROFILE:-}"
if [ -z "${STORE:-}" ] && { [ -z "$IDENTITY" ] || [ -z "$PROFILE" ] || [ ! -f "$PROFILE" ]; }; then CLOUD=""; fi
CLOUD_ENTRY=""
if [ -n "$CLOUD" ]; then CLOUD_ENTRY="<key>SnapflyCloudContainer</key><string>${CLOUD}</string>"; fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Snapfly</string>
  <key>CFBundleDisplayName</key><string>Snapfly</string>
  <key>CFBundleIdentifier</key><string>de.ghazarian.Snapfly</string>
  <key>CFBundleExecutable</key><string>Snapfly</string>
  <key>CFBundleIconFile</key><string>Snapfly</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array>${LANGUAGES}</array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  ${SHARE_ENTRY}
  ${CLOUD_ENTRY}
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDesktopFolderUsageDescription</key>
  <string>Snapfly watches the folder where macOS saves your screenshots so it can hang them on the line.</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>Snapfly watches the folder you chose so it can hang new images on the line.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>Snapfly watches the folder you chose so it can hang new images on the line.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Snapfly records your voice with a screen recording, only when you chose the microphone under Settings › General.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Snapfly asks your browser which page is open, so its send button shows only on chat websites like ChatGPT.</string>
  <!-- Photos and PDFs from anywhere: Finder's "Send Safely with Snapfly" and
       "Hide Private Details with Snapfly", translated in each language's
       ServicesMenu.strings, and Open With. Snapfly is only ever an
       alternative, never what opens them. -->
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Send Safely with Snapfly</string></dict>
      <key>NSMessage</key><string>sendSafely</string>
      <key>NSPortName</key><string>Snapfly</string>
      <key>NSRequiredContext</key><dict/>
      <key>NSSendFileTypes</key><array><string>public.image</string><string>com.adobe.pdf</string></array>
    </dict>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Hide Private Details with Snapfly</string></dict>
      <key>NSMessage</key><string>hideDetails</string>
      <key>NSPortName</key><string>Snapfly</string>
      <key>NSRequiredContext</key><dict/>
      <key>NSSendFileTypes</key><array><string>public.image</string><string>com.adobe.pdf</string><string>public.folder</string></array>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Photo or PDF</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.image</string><string>com.adobe.pdf</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Sign with a Developer ID when one is in the keychain (or SIGN_IDENTITY is
# set), with the hardened runtime and a secure timestamp that notarization
# requires. Without one, sign ad hoc so the app still runs locally.
if [ -n "$IDENTITY" ] && [ -z "${STORE:-}" ]; then
  # iCloud, for syncing, comes with the profile that allows it, and push
  # when the profile has it too, so the iPhone's changes arrive at once.
  CLOUD_ENTITLEMENTS=""
  if [ -n "$CLOUD" ]; then
    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
    PROFILE_PLIST="$(mktemp)"
    security cms -D -i "$PROFILE" > "$PROFILE_PLIST"
    TEAM="$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$PROFILE_PLIST")"
    CLOUD_ENTITLEMENTS="<key>com.apple.application-identifier</key><string>${TEAM}.de.ghazarian.Snapfly</string>
  <key>com.apple.developer.team-identifier</key><string>${TEAM}</string>
  <key>com.apple.developer.icloud-container-identifiers</key><array><string>${CLOUD}</string></array>
  <key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array>
  <key>com.apple.developer.icloud-container-environment</key><string>Production</string>"
    if /usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.aps-environment" "$PROFILE_PLIST" >/dev/null 2>&1; then
      CLOUD_ENTITLEMENTS="$CLOUD_ENTITLEMENTS
  <key>com.apple.developer.aps-environment</key><string>production</string>"
    fi
    rm -f "$PROFILE_PLIST"
  fi
  # The hardened runtime blocks Apple Events and the microphone unless asked
  # for: the send button over chats asks the browser which page is open, and
  # a screen recording may record the voice.
  ENTITLEMENTS="$(mktemp)"
  cat > "$ENTITLEMENTS" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.automation.apple-events</key><true/>
  <key>com.apple.security.device.audio-input</key><true/>
  ${CLOUD_ENTITLEMENTS}
</dict>
</plist>
ENT
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
  rm -f "$ENTITLEMENTS"
  echo "Signed with $IDENTITY${CLOUD:+, with iCloud for syncing}"
else
  codesign --force --deep --sign - "$APP" >/dev/null
  echo "Signed ad hoc (no Developer ID found)"
fi
echo "Built $APP"

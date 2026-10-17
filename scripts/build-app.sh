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
VERSION="1.0.0"
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
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDesktopFolderUsageDescription</key>
  <string>Snapfly watches the folder where macOS saves your screenshots so it can hang them on the line.</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>Snapfly watches the folder you chose so it can hang new images on the line.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>Snapfly watches the folder you chose so it can hang new images on the line.</string>
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
      <key>NSSendFileTypes</key><array><string>public.image</string><string>com.adobe.pdf</string></array>
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
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
if [ -n "$IDENTITY" ] && [ -z "${STORE:-}" ]; then
  # The hardened runtime blocks Apple Events unless asked for: the send
  # button over chats asks the browser which page is open.
  ENTITLEMENTS="$(mktemp)"
  cat > "$ENTITLEMENTS" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.automation.apple-events</key><true/>
</dict>
</plist>
ENT
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
  rm -f "$ENTITLEMENTS"
  echo "Signed with $IDENTITY"
else
  codesign --force --deep --sign - "$APP" >/dev/null
  echo "Signed ad hoc (no Developer ID found)"
fi
echo "Built $APP"

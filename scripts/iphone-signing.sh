#!/bin/bash
# Prepares what GitHub needs to sign the iPhone app for the App Store. Run it
# once on your Mac, in Terminal, after scripts/mac-signing.sh:
#
#   curl -fsSL https://raw.githubusercontent.com/mgrd281/Screenshots/main/scripts/iphone-signing.sh -o ~/snapfly-iphone.sh && bash ~/snapfly-iphone.sh
#
# With the App Store Connect key in ~/Snapfly-Signing it makes a private key,
# has Apple create its Apple Distribution certificate, makes the iPhone's
# App Store profile once to be sure the bundle ID allows it, and puts the
# key and certificate on the clipboard as one block. You paste that
# yourself into GitHub, as the secret SNAPFLY_IPHONE. The key stays in
# ~/Snapfly-Signing; keep it.
set -euo pipefail

SSL=/usr/bin/openssl
DIR="$HOME/Snapfly-Signing"
REPO="mgrd281/Screenshots"
BUNDLE_ID="de.ghazarian.Snapfly"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
wait_enter() { printf '\n%s ' "$1"; read -r _ < /dev/tty; }
key_public() { $SSL pkey -in "$1" -pubout 2>/dev/null; }
cert_public() { $SSL x509 -inform DER -in "$1" -noout -pubkey 2>/dev/null; }

P8="$(ls -t "$DIR"/AuthKey_*.p8 2>/dev/null | head -1 || true)"
if [ -z "$P8" ]; then
  echo "لم أجد مفتاح App Store Connect في $DIR. شغّل أداة التوقيع الأولى قبل هذه."
  exit 1
fi
export ASC_KEY_ID="$(basename "$P8" .p8)"; ASC_KEY_ID="${ASC_KEY_ID#AuthKey_}"
export ASC_KEY="$(cat "$P8")"

say "١) Issuer ID"
echo "افتح https://appstoreconnect.apple.com/access/integrations/api وانسخ Issuer ID من أعلى الصفحة."
printf "الصقه هنا ثم اضغط Enter: "
read -r ASC_ISSUER_ID < /dev/tty
ASC_ISSUER_ID="$(echo "$ASC_ISSUER_ID" | tr -d '[:space:]')"
export ASC_ISSUER_ID

say "٢) شهادة الآيفون"
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/scripts/asc.swift" -o "$DIR/asc.swift"
swift "$DIR/asc.swift" check

# The key, made once, and the certificate Apple signs for it.
KEY="$DIR/iphone.key"
CERT="$DIR/iphone.cer"
[ -f "$KEY" ] || { $SSL genrsa -out "$KEY" 2048 2>/dev/null; chmod 600 "$KEY"; }
if [ -f "$CERT" ] && [ "$(cert_public "$CERT")" = "$(key_public "$KEY")" ] && [ -f "$DIR/iphone.id" ]; then
  echo "الشهادة موجودة من قبل."
else
  $SSL req -new -key "$KEY" -subj "/CN=Snapfly iPhone" -out "$DIR/iphone.certSigningRequest"
  if ! swift "$DIR/asc.swift" create-certificate DISTRIBUTION "$DIR/iphone.certSigningRequest" "$CERT" > "$DIR/iphone.id"; then
    rm -f "$DIR/iphone.id"
    echo "رفضت Apple صنع الشهادة. صوّر هذه النافذة وأرسلها لـ Claude."
    exit 1
  fi
  echo "أنشأتها Apple."
fi

say "٣) ملف الآيفون"
BUNDLE="$(swift "$DIR/asc.swift" bundle-id "$BUNDLE_ID" Snapfly)"
CERT_ID="$(cat "$DIR/iphone.id")"
if ! swift "$DIR/asc.swift" profile "$BUNDLE" "$CERT_ID" "Snapfly iPhone App Store $CERT_ID" \
     "$DIR/iphone.mobileprovision" IOS_APP_STORE > /dev/null; then
  echo "رفضت Apple ملف الآيفون. صوّر هذه النافذة وأرسلها لـ Claude."
  exit 1
fi
echo "يقبل $BUNDLE_ID الآيفون."

say "٤) احفظه في GitHub"
{
  echo "# iphone-id"
  echo "$CERT_ID"
  echo "# iphone-key"
  cat "$KEY"
  echo "# iphone-certificate"
  $SSL x509 -inform DER -in "$CERT"
} | pbcopy
echo "نسخت كل شيء. سيفتح الآن GitHub. فيه:"
echo "  • Name:  SNAPFLY_IPHONE"
echo "  • Secret:  الصق بـ ⌘V"
echo "  • ثم Add secret"
open "https://github.com/$REPO/settings/secrets/actions/new"
wait_enter "بعد الحفظ، اضغط Enter هنا…"
printf '' | pbcopy

say "تم ✅  اكتب لـ Claude: «تم»"

#!/bin/bash
# Prepares what GitHub needs to sign Snapfly with your Developer ID and have
# Apple notarize it. Run it once on your Mac, in Terminal:
#
#   curl -fsSL https://raw.githubusercontent.com/mgrd281/Screenshots/main/scripts/mac-signing.sh -o ~/snapfly-signing.sh && bash ~/snapfly-signing.sh
#
# It makes a private key and a certificate request on this Mac, opens the
# Apple pages where you create the certificate and an API key, and finally
# puts everything on the clipboard as one block of text. You paste that
# yourself into GitHub, as the secret SNAPFLY_SIGNING. Nothing is sent
# anywhere by this script. The key stays in ~/Snapfly-Signing; keep it.
set -euo pipefail

SSL=/usr/bin/openssl
DIR="$HOME/Snapfly-Signing"
KEY="$DIR/developer-id.key"
CSR="$DIR/Snapfly-Developer-ID.certSigningRequest"
CERT="$DIR/developer-id.cer"
REPO="mgrd281/Screenshots"

mkdir -p "$DIR"
chmod 700 "$DIR"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
wait_enter() { printf '\n%s ' "$1"; read -r _ < /dev/tty; }

# The public half of a key or of a certificate, to see that they belong together.
key_public() { $SSL pkey -in "$1" -pubout 2>/dev/null; }
cert_public() { $SSL x509 -inform DER -in "$1" -noout -pubkey 2>/dev/null; }

# The newest file in Downloads that matches, or nothing.
newest_download() { ls -t "$HOME"/Downloads/$1 2>/dev/null | head -1 || true; }

say "١) المفتاح وطلب الشهادة"
if [ ! -f "$KEY" ]; then
  $SSL genrsa -out "$KEY" 2048 2>/dev/null
  chmod 600 "$KEY"
fi
$SSL req -new -key "$KEY" -subj "/CN=Snapfly Developer ID" -out "$CSR"
echo "جاهز في المجلد: $DIR"

if [ -f "$CERT" ] && [ "$(cert_public "$CERT")" = "$(key_public "$KEY")" ]; then
  echo "الشهادة موجودة من قبل."
else
  say "٢) أنشئ الشهادة على موقع Apple"
  echo "سيفتح الآن موقع Apple ومجلد الملف. في الموقع:"
  echo "  • اختر  Developer ID Application  ثم Continue"
  echo "  • اختر  G2 Sub-CA  ثم Choose File، واختر الملف  Snapfly-Developer-ID.certSigningRequest"
  echo "  • اضغط Continue ثم Download"
  open -R "$CSR"
  open "https://developer.apple.com/account/resources/certificates/add"
  while true; do
    wait_enter "بعد أن تضغط Download، اضغط Enter هنا…"
    found=""
    for file in "$HOME"/Downloads/*.cer; do
      [ -f "$file" ] || continue
      if [ "$(cert_public "$file")" = "$(key_public "$KEY")" ]; then found="$file"; fi
    done
    if [ -n "$found" ]; then
      cp "$found" "$CERT"
      echo "وجدت الشهادة: $(basename "$found")"
      break
    fi
    echo "لم أجد الشهادة في مجلد التنزيلات بعد. تأكد أنك اخترت الملف الصحيح، ثم حاول مرة أخرى."
  done
fi

say "٣) مفتاح App Store Connect"
echo "سيفتح الآن موقع App Store Connect. فيه:"
echo "  • إذا ظهر زر  Request Access  فاضغطه ووافق"
echo "  • تبويب  Team Keys  ثم زر  +"
echo "  • الاسم: Snapfly  — الصلاحية (Access): Admin  — ثم Generate"
echo "  • اضغط  Download  بجانب المفتاح الجديد (يُحمَّل مرة واحدة فقط)"
open "https://appstoreconnect.apple.com/access/integrations/api"
while true; do
  wait_enter "بعد التنزيل، اضغط Enter هنا…"
  P8="$(newest_download 'AuthKey_*.p8')"
  [ -n "$P8" ] && break
  echo "لم أجد ملفًا اسمه AuthKey_….p8 في مجلد التنزيلات بعد."
done
KEY_ID="$(basename "$P8" .p8)"
KEY_ID="${KEY_ID#AuthKey_}"
cp "$P8" "$DIR/"
echo "وجدت المفتاح: $KEY_ID"

echo
echo "انسخ الآن  Issuer ID  من أعلى الصفحة نفسها (رقم طويل فيه شرطات)،"
printf "والصقه هنا ثم اضغط Enter: "
read -r ISSUER_ID < /dev/tty
ISSUER_ID="$(echo "$ISSUER_ID" | tr -d '[:space:]')"
if [ ${#ISSUER_ID} -lt 30 ]; then
  echo "هذا لا يشبه Issuer ID. شغّل السكربت مرة أخرى."
  exit 1
fi

say "٤) احفظه في GitHub"
{
  echo "# issuer"
  echo "$ISSUER_ID"
  echo "# key-id"
  echo "$KEY_ID"
  echo "# api-key"
  tr -d '\r' < "$P8"
  echo
  echo "# developer-id-key"
  cat "$KEY"
  echo "# developer-id-certificate"
  $SSL x509 -inform DER -in "$CERT"
} | pbcopy
echo "نسخت كل شيء. سيفتح الآن GitHub. فيه:"
echo "  • Name:  SNAPFLY_SIGNING"
echo "  • Secret:  الصق بـ ⌘V"
echo "  • ثم Add secret"
open "https://github.com/$REPO/settings/secrets/actions/new"
wait_enter "بعد الحفظ، اضغط Enter هنا…"
printf '' | pbcopy

say "تم ✅  اكتب لـ Claude: «تم»"
echo "احتفظ بالمجلد $DIR في مكان آمن، ففيه مفتاحك الخاص."

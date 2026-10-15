#!/bin/bash
# Prepares what GitHub needs to sign the Mac App Store edition. Run it once
# on your Mac, in Terminal, after scripts/mac-signing.sh:
#
#   curl -fsSL https://raw.githubusercontent.com/mgrd281/Screenshots/main/scripts/mac-store-signing.sh -o ~/snapfly-store.sh && bash ~/snapfly-store.sh
#
# With the App Store Connect key in ~/Snapfly-Signing it makes two private
# keys, has Apple create their certificates (Mac App Distribution and Mac
# Installer Distribution), registers the bundle ID, and puts it all on the
# clipboard as one block. You paste that yourself into GitHub, as the
# secret SNAPFLY_STORE. The keys stay in ~/Snapfly-Signing; keep them.
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

say "٢) الشهادتان"
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/scripts/asc.swift" -o "$DIR/asc.swift"
swift "$DIR/asc.swift" check

# One certificate: its key, made once, and the certificate Apple signs for it.
make_certificate() {
  local name="$1" type="$2" key="$DIR/$1.key" cert="$DIR/$1.cer"
  [ -f "$key" ] || { $SSL genrsa -out "$key" 2048 2>/dev/null; chmod 600 "$key"; }
  if [ -f "$cert" ] && [ "$(cert_public "$cert")" = "$(key_public "$key")" ] && [ -f "$DIR/$name.id" ]; then
    echo "$name: موجودة من قبل."
    return
  fi
  $SSL req -new -key "$key" -subj "/CN=Snapfly $name" -out "$DIR/$name.certSigningRequest"
  swift "$DIR/asc.swift" create-certificate "$type" "$DIR/$name.certSigningRequest" "$cert" > "$DIR/$name.id"
  echo "$name: أنشأتها Apple."
}
make_certificate app-store MAC_APP_DISTRIBUTION
make_certificate installer MAC_INSTALLER_DISTRIBUTION

say "٣) معرّف التطبيق"
swift "$DIR/asc.swift" bundle-id "$BUNDLE_ID" Snapfly > /dev/null
echo "سجّلت $BUNDLE_ID."

say "٤) احفظه في GitHub"
{
  echo "# app-store-id"
  cat "$DIR/app-store.id"
  echo "# app-store-key"
  cat "$DIR/app-store.key"
  echo "# app-store-certificate"
  $SSL x509 -inform DER -in "$DIR/app-store.cer"
  echo "# installer-key"
  cat "$DIR/installer.key"
  echo "# installer-certificate"
  $SSL x509 -inform DER -in "$DIR/installer.cer"
} | pbcopy
echo "نسخت كل شيء. سيفتح الآن GitHub. فيه:"
echo "  • Name:  SNAPFLY_STORE"
echo "  • Secret:  الصق بـ ⌘V"
echo "  • ثم Add secret"
open "https://github.com/$REPO/settings/secrets/actions/new"
wait_enter "بعد الحفظ، اضغط Enter هنا…"
printf '' | pbcopy

say "تم ✅  اكتب لـ Claude: «تم»"

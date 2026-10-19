#!/bin/bash
# Prints the address of Snapfly's share links, on the owner's Cloudflare
# account, for scripts/build-app.sh to put in Info.plist: nothing when the
# account is not set up or the Worker is not deployed yet, so the app then
# leaves Copy Link out. Reads CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID,
# which the owner pastes as repository secrets; it changes nothing there.
set -uo pipefail

[ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] || exit 0
API="https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID"
ask() { curl -fsS --max-time 20 -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "$API/$1"; }

# The Worker is there.
ask "workers/scripts" 2>/dev/null \
  | python3 -c 'import json,sys; sys.exit(0 if any(s.get("id") == "snapfly-share" for s in json.load(sys.stdin)["result"]) else 1)' \
  2>/dev/null || exit 0
SUBDOMAIN="$(ask "workers/subdomain" 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["subdomain"])' 2>/dev/null)"
[ -n "$SUBDOMAIN" ] || exit 0
echo "https://snapfly-share.$SUBDOMAIN.workers.dev/"

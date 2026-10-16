#!/bin/bash
# Stops when a binary calls into the window server's private functions
# (CGS…, SLS…). The Mac App Store refuses an app that does.
# Usage: scripts/check-private-apis.sh path/to/binary
set -euo pipefail
FOUND="$(nm -u "$1" | grep -E '^_(CGS|SLS)[A-Z]' || true)"
if [ -n "$FOUND" ]; then
  echo "Private functions the App Store does not allow:" >&2
  echo "$FOUND" >&2
  exit 1
fi
echo "No private window server functions in $1"

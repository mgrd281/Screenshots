#!/bin/bash
# Opens the App Store edition as App Review does, sandboxed, and checks that
# something shows each time: the first time on a Mac, opened again while it
# runs, and once more after quitting, where only the menu bar icon is left.
# Usage: STORE=1 ARCHS=arm64 scripts/build-app.sh debug && scripts/launch-check.sh
# Each look at the screen goes to captures/launch, for the artifact.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Snapfly.app"
OUT="captures/launch"
mkdir -p "$OUT"

# The sandbox the store edition runs in, signed ad hoc: the same doors as
# scripts/app-store.sh, without those that need the owner's team.
ENTITLEMENTS="$(mktemp)"
cat > "$ENTITLEMENTS" <<PLIST
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
</dict>
</plist>
PLIST
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q app-sandbox

FAILED=0
fail() { echo "::error::$1"; echo "FAILED: $1"; FAILED=1; }
# The icon's window may belong to the system's menu bar on a newer macOS,
# so a missing one is said, not failed on.
warn() { echo "::warning::$1"; echo "WARNING: $1"; }

# Snapfly's windows on screen, as "level x y width height" per line.
windows() {
  local pid
  pid="$(pgrep -x Snapfly | head -1 || true)"
  if [ -z "$pid" ]; then return; fi
  swift scripts/app-windows.swift "$pid"
}

# What shows, said in the log and kept as a picture.
look() {
  echo "== $1"
  windows | tee "$OUT/$1.txt"
  echo "-- the menu bar's windows"
  swift scripts/app-windows.swift menubar | tee "$OUT/$1-menubar.txt"
  screencapture -x "$OUT/$1.png" 2>/dev/null || true
}

# The menu bar icon: a window of Snapfly's at the status bar's level, or,
# from macOS 26, where Control Center shows every app's icon, one more
# window at that level than before Snapfly was opened.
icons() { awk '$2 == 25 && $6 > 0 && $7 > 0' "$1" | wc -l; }
has_icon() {
  awk '$2 == 25 && $4 >= 0 && $6 > 0 && $7 > 0 { found = 1 } END { exit !found }' "$OUT/$1.txt" \
    || [ "$(icons "$OUT/$1-menubar.txt")" -gt "$(icons "$OUT/before-menubar.txt")" ]
}
# A window to find Snapfly by, like Settings: at the normal level, and large.
has_window() { awk '$2 == 0 && $6 >= 300 && $7 >= 200 { found = 1 } END { exit !found }' "$OUT/$1.txt"; }
running() { pgrep -x Snapfly >/dev/null; }

pkill -x Snapfly 2>/dev/null || true
echo "== before"
swift scripts/app-windows.swift menubar | tee "$OUT/before-menubar.txt"
open "$APP"
sleep 10
look first-launch
running || fail "Snapfly was not running 10 seconds after it was opened."
has_icon first-launch || warn "No menu bar icon window of Snapfly's showed on the first launch."
# The welcome card, or the question that follows it, above the icon.
awk '$2 != 25 { found = 1 } END { exit !found }' "$OUT/first-launch.txt" \
  || fail "Nothing but the menu bar icon showed on the first launch."

# Opened again while it runs, as from Finder or Launchpad: Settings.
open "$APP"
sleep 5
look reopened
has_window reopened || fail "Opening Snapfly again while it runs showed no window."

# Quit, and opened as on a Mac where it ran before: no welcome, the icon.
pkill -x Snapfly || true
sleep 3
open "$APP"
sleep 10
look second-launch
running || fail "Snapfly was not running 10 seconds after it was opened the second time."
has_icon second-launch || warn "No menu bar icon window of Snapfly's showed on the second launch."

# Once more, as on the Mac of a reviewer who saw the welcome and the
# question before: nothing asks, so the icon shows, or Settings when the
# menu bar has no room for it.
pkill -x Snapfly || true
sleep 3
# The question counts as asked, from the arguments, which the app's own
# settings cannot be written over from outside its sandbox.
open "$APP" --args -inboxOffered YES
sleep 15
look third-launch
running || fail "Snapfly was not running 10 seconds after it was opened the third time."
has_icon third-launch || has_window third-launch \
  || fail "Neither the menu bar icon nor Settings showed on a launch with nothing to ask."

pkill -x Snapfly || true
# A crash leaves a report; it says why.
for report in ~/Library/Logs/DiagnosticReports/Snapfly*; do
  [ -e "$report" ] || continue
  fail "Snapfly crashed: $report"
  head -80 "$report"
done
rm -f "$ENTITLEMENTS"
exit "$FAILED"

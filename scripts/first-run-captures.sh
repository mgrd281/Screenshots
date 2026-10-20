#!/bin/bash
# Captures the iPhone's first run on the simulator, for review: still frames
# at set moments of the story (German, in light and dark, and a few in Arabic
# and English), a recording of the whole story from a fresh launch, and how
# soon it showed, from the app's log. With the main branch's build beside it,
# as it was before. Then Protect Picture on the first run's made-up invoice,
# covered by the real engine, on this iPhone and the smallest the runner
# has. Simulator numbers say how it behaves, not how fast a phone is. Writes
# everything to captures/.
set -euo pipefail

out=captures
bundle=de.ghazarian.Snapfly
mkdir -p "$out"

# The newest iPhone the runner has, a Pro where there is one.
device=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.split("iOS-")[-1].split("-") if part.isdigit())
    for device in devices:
        name = device["name"]
        if not name.startswith("iPhone"):
            continue
        score = (version, "Pro" in name and "Max" not in name, name)
        if best is None or score > best[0]:
            best = (score, device["udid"], name)
print(best[1])
print(best[2], file=sys.stderr)
')
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

# Builds the app from a checkout for the simulator; prints where it is.
build() {
  local source=$1 derived=$2
  xcodebuild -project "$source/iOS/Snapfly.xcodeproj" -scheme Snapfly -configuration Debug \
    -destination "id=$device" -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO -quiet build >&2
  echo "$derived/Build/Products/Debug-iphonesimulator/Snapfly.app"
}

# A fresh install, as a new owner has it.
install() {
  xcrun simctl uninstall "$device" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl install "$device" "$1"
}

launch() {
  local language=$1
  shift
  xcrun simctl terminate "$device" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl launch "$device" "$bundle" -AppleLanguages "($language)" -AppleLocale "$language" "$@" >/dev/null
}

# Records a fresh launch for some seconds.
record() {
  local name=$1 seconds=$2
  xcrun simctl io "$device" recordVideo --codec=h264 --force "$out/$name.mp4" &
  local recorder=$!
  sleep 2
  launch de
  sleep "$seconds"
  kill -INT "$recorder"
  wait "$recorder" || true
}

# After: this branch.
after=$(build . build/captures/after)
install "$after"
xcrun simctl ui "$device" appearance light
xcrun simctl spawn "$device" log stream --level info --style compact \
  --predicate 'subsystem == "de.ghazarian.Snapfly" AND eventMessage CONTAINS "First run"' > "$out/measurements.txt" &
logger=$!
record after 17
kill "$logger" || true
# It is still running once the story is over: a smoke test of the first run.
running=$(xcrun simctl spawn "$device" launchctl list)
if ! grep -q "$bundle" <<<"$running"; then
  echo "The app is not running after its first run." >&2
  exit 1
fi

# Still frames, the story held at each moment.
still() {
  local language=$1 appearance=$2 moment=$3
  xcrun simctl ui "$device" appearance "$appearance"
  launch "$language" -SnapflyFirstRunAt "$moment"
  sleep 3
  xcrun simctl io "$device" screenshot "$out/after-$language-$appearance-$moment.png" >/dev/null
}
for moment in 0 0.75 1.2 1.55 2.0 3.6 6.4 7.2 8.0 8.9 10.0 11.5 14.0; do
  still de light "$moment"
done
for moment in 2.0 9.0 14.0; do still de dark "$moment"; done
for moment in 2.5 14.0; do still ar light "$moment"; done
still en light 14.0

# Protect Picture, once the engine has covered the invoice.
editor() {
  local on=$1 language=$2 appearance=$3 name=$4
  xcrun simctl ui "$on" appearance "$appearance"
  xcrun simctl terminate "$on" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl launch "$on" "$bundle" -AppleLanguages "($language)" -AppleLocale "$language" -SnapflyEditorSample >/dev/null
  sleep 14
  xcrun simctl io "$on" screenshot "$out/editor-$name.png" >/dev/null
}
editor "$device" de light de-light
editor "$device" de dark de-dark
editor "$device" ar light ar-light
editor "$device" en light en-light

# And on the smallest iPhone there is, where the apps beside the page are tightest.
small=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
order = ("SE", "mini", "16e", "17e")
found = {}
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "iOS-" not in runtime:
        continue
    for device in devices:
        for rank, word in enumerate(order):
            if device["name"].startswith("iPhone") and word in device["name"]:
                found.setdefault(rank, device["udid"])
print(found[min(found)] if found else "")
')
if [ -n "$small" ] && [ "$small" != "$device" ]; then
  xcrun simctl boot "$small" || true
  xcrun simctl bootstatus "$small" -b
  xcrun simctl install "$small" "$after"
  editor "$small" de light de-light-small
  xcrun simctl shutdown "$small" || true
fi

# Before: the main branch, where this branch left it.
base=$(git merge-base HEAD origin/main)
if [ "$base" != "$(git rev-parse HEAD)" ]; then
  temp=${RUNNER_TEMP:-/tmp}
  git worktree add --detach "$temp/before" "$base" >&2
  before=$(build "$temp/before" build/captures/before)
  install "$before"
  xcrun simctl ui "$device" appearance light
  record before 8
  xcrun simctl io "$device" screenshot "$out/before-de-light.png" >/dev/null
fi

ls -l "$out"
cat "$out/measurements.txt"

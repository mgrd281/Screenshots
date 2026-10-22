#!/bin/bash
# Always Hide on the simulator, for review: its UI tests (iOS/SnapflyUITests),
# then still frames of the screen and every sheet over it, on made-up details
# held in memory (-SnapflyAlwaysHide), in German, light and dark, at the
# largest text sizes, on the newest iPhone the runner has and on the
# smallest, and once in Arabic and English. Writes the frames to
# captures/always-hide and the test results to build/always-hide.xcresult.
# A failed test fails the run, once the frames are made.
set -euo pipefail

out=captures/always-hide
derived=build/always-hide
bundle=de.ghazarian.Snapfly
mkdir -p "$out"

# The newest iPhone the runner has, the largest: a Pro Max where there is one.
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
        score = (version, "Pro Max" in name, "Plus" in name or "Air" in name, name)
        if best is None or score > best[0]:
            best = (score, device["udid"], name)
print(best[1])
print(best[2], file=sys.stderr)
')
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
# The keyboard's first-run tip would sit over the sheets.
quiet_keyboard() {
  xcrun simctl spawn "$1" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true || true
  xcrun simctl spawn "$1" defaults write com.apple.keyboard.preferences DidShowGestureKeyboardIntroduction -bool true || true
}
quiet_keyboard "$device"
xcrun simctl status_bar "$device" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

xcodebuild -project iOS/Snapfly.xcodeproj -scheme Snapfly -configuration Debug -destination "id=$device" \
  -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO -quiet build-for-testing
app="$derived/Build/Products/Debug-iphonesimulator/Snapfly.app"

# The UI tests, in light. Scan's run in the Scan Checks workflow, on a build
# optimized for its made-up scans: in this one a page takes minutes to make.
xcrun simctl ui "$device" appearance light
tests=0
rm -rf build/always-hide.xcresult
xcodebuild -project iOS/Snapfly.xcodeproj -scheme Snapfly -destination "id=$device" -derivedDataPath "$derived" \
  -skip-testing:SnapflyUITests/ScanUITests -resultBundlePath build/always-hide.xcresult CODE_SIGNING_ALLOWED=NO \
  test-without-building || tests=$?

xcrun simctl install "$device" "$app"

# A frame of a state, as the sample opens it: on a device, in an
# appearance and a language, at a text size when one is given.
shot() {
  local on=$1 name=$2 state=$3 appearance=$4 language=$5 size=${6:-}
  local arguments=(-SnapflyAlwaysHide "$state" -AppleLanguages "($language)" -AppleLocale "$language")
  if [ -n "$size" ]; then arguments+=(-UIPreferredContentSizeCategoryName "$size"); fi
  xcrun simctl ui "$on" appearance "$appearance"
  xcrun simctl terminate "$on" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl launch "$on" "$bundle" "${arguments[@]}" >/dev/null
  sleep 6
  xcrun simctl io "$on" screenshot "$out/$name.png" >/dev/null
}

# Once to warm up: a first launch takes longer than the frame waits.
xcrun simctl launch "$device" "$bundle" -SnapflyAlwaysHide filled >/dev/null
sleep 10
xcrun simctl terminate "$device" "$bundle" >/dev/null 2>&1 || true

states=(filled empty editing picker name address card account editCard word label labelNext blankName blankWord)
for state in "${states[@]}"; do shot "$device" "de-light-$state" "$state" light de; done
for state in "${states[@]}"; do shot "$device" "de-dark-$state" "$state" dark de; done
for state in "${states[@]}"; do shot "$device" "de-xxxl-$state" "$state" light de UICTContentSizeCategoryXXXL; done
for state in "${states[@]}"; do
  shot "$device" "de-accessibility-xxxl-$state" "$state" light de UICTContentSizeCategoryAccessibilityXXXL
done
shot "$device" "ar-light-filled" filled light ar
shot "$device" "ar-light-picker" picker light ar
shot "$device" "ar-light-name" name light ar
shot "$device" "en-light-filled" filled light en

# And on the smallest iPhone there is.
small=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
order = ("SE", "mini", "16e", "17e")
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.split("iOS-")[-1].split("-") if part.isdigit())
    if version < (17,):
        continue
    for device in devices:
        for rank, word in enumerate(order):
            if device["name"].startswith("iPhone") and word in device["name"]:
                score = (-rank, version)
                if best is None or score > best[0]:
                    best = (score, device["udid"], device["name"])
print(best[1] if best else "")
if best: print(best[2], file=sys.stderr)
')
# Frames more, never a reason to stop.
if [ -n "$small" ] && [ "$small" != "$device" ]; then
  (
    xcrun simctl boot "$small" || true
    xcrun simctl bootstatus "$small" -b
    quiet_keyboard "$small"
    xcrun simctl status_bar "$small" override --time 9:41 --batteryState charged --batteryLevel 100 || true
    xcrun simctl install "$small" "$app"
    xcrun simctl launch "$small" "$bundle" -SnapflyAlwaysHide filled >/dev/null
    sleep 10
    for state in "${states[@]}"; do shot "$small" "de-small-$state" "$state" light de; done
    for state in "${states[@]}"; do shot "$small" "de-small-dark-$state" "$state" dark de; done
    shot "$small" "de-small-xxxl-filled" filled light de UICTContentSizeCategoryXXXL
    shot "$small" "de-small-xxxl-name" name light de UICTContentSizeCategoryXXXL
  ) || echo "The smallest iPhone could not be captured." >&2
  xcrun simctl shutdown "$small" || true
fi

ls -l "$out"
if [ "$tests" != 0 ]; then
  echo "The UI tests failed." >&2
  exit "$tests"
fi

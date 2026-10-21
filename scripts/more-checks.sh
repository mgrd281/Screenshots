#!/bin/bash
# More on the simulator, for review: its UI tests (iOS/SnapflyUITests), still
# frames of the tab and each page on made-up choices held in memory
# (-SnapflyMore), in German, light and dark, at the largest text sizes, on
# the newest iPhone the runner has and on the smallest, and once in Arabic
# and English; then videos of the motion (simctl io recordVideo) as the UI
# tests walk through it, and the same walks with Reduce Motion. Writes the
# frames and videos to captures/more and the test results to
# build/more.xcresult. A failed test fails the run, once the frames are made.
set -euo pipefail

out=captures/more
derived=build/more
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
xcrun simctl status_bar "$device" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

xcodebuild -project iOS/Snapfly.xcodeproj -scheme Snapfly -configuration Debug -destination "id=$device" \
  -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO -quiet build-for-testing
app="$derived/Build/Products/Debug-iphonesimulator/Snapfly.app"

# The UI tests, in light; the walks for the videos skip themselves here.
xcrun simctl ui "$device" appearance light
tests=0
rm -rf build/more.xcresult
xcodebuild -project iOS/Snapfly.xcodeproj -scheme Snapfly -destination "id=$device" -derivedDataPath "$derived" \
  -only-testing:SnapflyUITests/MoreUITests -resultBundlePath build/more.xcresult CODE_SIGNING_ALLOWED=NO \
  test-without-building || tests=$?

xcrun simctl install "$device" "$app"

# A frame of a state, as the sample opens it: on a device, in an appearance
# and a language, at a text size when one is given, with more arguments
# after it.
shot() {
  local on=$1 name=$2 state=$3 appearance=$4 language=$5 size=${6:-}
  shift 6 || shift $#
  local arguments=(-SnapflyMore "$state" -AppleLanguages "($language)" -AppleLocale "$language")
  if [ -n "$size" ]; then arguments+=(-UIPreferredContentSizeCategoryName "$size"); fi
  arguments+=("$@")
  xcrun simctl ui "$on" appearance "$appearance"
  xcrun simctl terminate "$on" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl launch "$on" "$bundle" "${arguments[@]}" >/dev/null
  sleep 6
  xcrun simctl io "$on" screenshot "$out/$name.png" >/dev/null
}

# Once to warm up: a first launch takes longer than the frame waits.
xcrun simctl launch "$device" "$bundle" -SnapflyMore root >/dev/null
sleep 10
xcrun simctl terminate "$device" "$bundle" >/dev/null 2>&1 || true

# Each state, and the end of the long ones.
frames() {
  local on=$1 prefix=$2 appearance=$3 language=$4 size=${5:-}
  for state in root off own covered people style strong detection; do
    shot "$on" "$prefix-$state" "$state" "$appearance" "$language" "$size"
  done
  for state in root covered style detection; do
    shot "$on" "$prefix-$state-end" "$state" "$appearance" "$language" "$size" -SnapflyMoreEnd
  done
}
frames "$device" de-light light de
frames "$device" de-dark dark de
frames "$device" de-accessibility-xxxl light de UICTContentSizeCategoryAccessibilityXXXL
frames "$device" de-dark-accessibility-xxxl dark de UICTContentSizeCategoryAccessibilityXXXL
for look in label blur pixels dots erase; do
  shot "$device" "de-light-style-$look" style light de "" -SnapflyMoreLook "$look"
  shot "$device" "de-light-root-$look" root light de "" -SnapflyMoreLook "$look"
done
shot "$device" "de-light-digits" digits light de
shot "$device" "ar-light-root" root light ar
shot "$device" "ar-light-covered" covered light ar
shot "$device" "en-light-root" root light en
shot "$device" "en-light-covered" covered light en

# Videos of the walks: the motion as it plays, then with Reduce Motion.
# Never a reason to stop.
record() {
  local name=$1 test=$2 still=${3:-}
  xcrun simctl ui "$device" appearance light
  xcrun simctl io "$device" recordVideo --codec=h264 --force "$out/$name.mp4" >/dev/null 2>&1 &
  local recorder=$!
  sleep 2
  env TEST_RUNNER_SNAPFLY_RECORD=1 ${still:+TEST_RUNNER_SNAPFLY_STILL=1} \
    xcodebuild -project iOS/Snapfly.xcodeproj -scheme Snapfly -destination "id=$device" -derivedDataPath "$derived" \
    -only-testing:"SnapflyUITests/MoreUITests/$test" CODE_SIGNING_ALLOWED=NO -quiet test-without-building \
    || echo "The walk $test did not finish." >&2
  sleep 1
  kill -INT "$recorder" 2>/dev/null || true
  wait "$recorder" 2>/dev/null || true
}
(
  record first-open testRecordFirstOpen
  record tile-to-page testRecordTileToPage
  record pills-presets-tabs testRecordPillsPresetsAndTabs
  record style testRecordStyle
  record reduce-motion-first-open testRecordFirstOpen still
  record reduce-motion-tile-to-page testRecordTileToPage still
  record reduce-motion-pills-presets-tabs testRecordPillsPresetsAndTabs still
  record reduce-motion-style testRecordStyle still
) || echo "The videos could not all be recorded." >&2

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
    xcrun simctl status_bar "$small" override --time 9:41 --batteryState charged --batteryLevel 100 || true
    xcrun simctl install "$small" "$app"
    xcrun simctl launch "$small" "$bundle" -SnapflyMore root >/dev/null
    sleep 10
    frames "$small" de-small light de
    frames "$small" de-small-dark dark de
    frames "$small" de-small-accessibility-xxxl light de UICTContentSizeCategoryAccessibilityXXXL
  ) || echo "The smallest iPhone could not be captured." >&2
  xcrun simctl shutdown "$small" || true
fi

ls -l "$out"
if [ "$tests" != 0 ]; then
  echo "The UI tests failed." >&2
  exit "$tests"
fi

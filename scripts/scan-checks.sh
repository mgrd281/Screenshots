#!/bin/bash
# Scan without an iPhone, for review. First the engine on this Mac: the scan's
# fixture tests (Tests/TendederoTests/ScanFixtureTests.swift, and the folded
# sick note and the scanned invoice beside it) on made-up photos and scans of
# made-up papers, keeping each picture before and after and what
# was read on it (SCAN_CAPTURES). Then the app on the simulator, the engine
# built optimized as on a phone: its UI tests (iOS/SnapflyUITests/
# ScanUITests.swift), still frames of the Scan tab, Review, Save and Share
# and the pages' text on the made-up photos (-SnapflyScan), the tab's start with made-up
# documents arriving, without any, with "So funktioniert's" and scrolled
# past its card, with what to ask Claude, and the
# Photos tab's offer to clean a photographed document and the document
# cleaned (-SnapflyDocumentPhoto), in German, light and dark, at the
# largest accessibility text size, on the newest iPhone the runner has and on
# the smallest, and in Arabic and English; then videos of the walks (simctl
# io recordVideo), from Photos to sharing, two photos chosen together,
# cleaning a photo, the name and the hand-over to Claude among them, and walks with
# Reduce Motion. Writes everything to captures/scan and the test results to
# build/scan.xcresult. A failed test fails the run, once the frames are made.
set -euo pipefail

out=captures/scan
derived=build/scan
bundle=de.ghazarian.Snapfly
mkdir -p "$out"

# The engine, with its pictures and numbers. Its photos whole, sharp and
# blurred at the bottom, go into Photos on the simulator, for the walks from
# Photos, and are not published.
engine=0
SCAN_CAPTURES="$PWD/$out" swift test --filter "ScanFixtureTests|ScanFormFixtureTests|ScanInvoiceFixtureTests|OwnLetterFixtureTests|ScanTextFixtureTests" || engine=$?
photo=build/scan-photo.png
blurred=build/scan-photo-blurred.png
mkdir -p build
if [ -f "$out/scan-photo-full.png" ]; then mv "$out/scan-photo-full.png" "$photo"; fi
if [ -f "$out/scan-photo-blurred-full.png" ]; then mv "$out/scan-photo-blurred-full.png" "$blurred"; fi

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
# The blurred one first, so the sharp one is the newest, first in the picker.
if [ -f "$blurred" ]; then xcrun simctl addmedia "$device" "$blurred" || echo "The blurred photo could not go into Photos." >&2; fi
if [ -f "$photo" ]; then xcrun simctl addmedia "$device" "$photo" || echo "The photo could not go into Photos." >&2; fi

# Debug, for the made-up scans, but optimized: the engine's loops are as
# quick as in the App Store's build.
xcodebuild -project iOS/Snapfly.xcodeproj -scheme Snapfly -configuration Debug -destination "id=$device" \
  -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO SWIFT_OPTIMIZATION_LEVEL=-O -quiet build-for-testing
app="$derived/Build/Products/Debug-iphonesimulator/Snapfly.app"

# The UI tests, in light; the walks for the videos skip themselves here.
xcrun simctl ui "$device" appearance light
tests=0
rm -rf build/scan.xcresult
xcodebuild -project iOS/Snapfly.xcodeproj -scheme Snapfly -destination "id=$device" -derivedDataPath "$derived" \
  -only-testing:SnapflyUITests/ScanUITests -resultBundlePath build/scan.xcresult CODE_SIGNING_ALLOWED=NO \
  SWIFT_OPTIMIZATION_LEVEL=-O test-without-building || tests=$?

xcrun simctl install "$device" "$app"

# A frame of a state, as the made-up scans open it, once the pages are made
# ready and covered: on a device, in an appearance and a language, at a text
# size when one is given.
shot() {
  local on=$1 name=$2 state=$3 appearance=$4 language=$5 size=${6:-}
  local arguments=(-SnapflyScan "$state" -AppleLanguages "($language)" -AppleLocale "$language")
  if [ -n "$size" ]; then arguments+=(-UIPreferredContentSizeCategoryName "$size"); fi
  local settle=30
  if [ "$state" = corners ]; then settle=12; fi
  if [ "$state" = warning ] || [ "$state" = sheet ] || [ "$state" = uncovered ] || [ "$state" = list ]; then settle=45; fi
  # Its text is read again on the covered pages once they are ready, which
  # after the UI tests can take this runner the two minutes the tests allow.
  if [ "$state" = text ] || [ "$state" = textpage ] || [ "$state" = textfix ]; then settle=120; fi
  # Three documents arrive a few seconds apart, then their first pages are covered.
  if [ "$state" = recent ]; then settle=75; fi
  xcrun simctl ui "$on" appearance "$appearance"
  xcrun simctl terminate "$on" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl launch "$on" "$bundle" "${arguments[@]}" >/dev/null
  sleep "$settle"
  xcrun simctl io "$on" screenshot "$out/$name.png" >/dev/null
}

# Once to warm up: a first launch takes longer than the frame waits.
xcrun simctl launch "$device" "$bundle" -SnapflyScan editor >/dev/null
sleep 40
xcrun simctl terminate "$device" "$bundle" >/dev/null 2>&1 || true

# Each state, or the ones given.
frames() {
  local on=$1 prefix=$2 appearance=$3 language=$4 size=$5
  shift 5
  local states=("$@")
  if [ ${#states[@]} -eq 0 ]; then states=(tab editor compare warning bw corners sheet uncovered text textpage textfix); fi
  for state in "${states[@]}"; do
    shot "$on" "$prefix-$state" "$state" "$appearance" "$language" "$size"
  done
}
frames "$device" de-light light de ""
frames "$device" de-dark dark de ""

# A photographed document opened from the Photos tab: the offer to clean
# it, and cleaned, its covers found again.
photo_shot() {
  local on=$1 name=$2 state=$3 appearance=$4 language=$5
  xcrun simctl ui "$on" appearance "$appearance"
  xcrun simctl terminate "$on" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl launch "$on" "$bundle" -SnapflyDocumentPhoto "$state" -AppleLanguages "($language)" -AppleLocale "$language" >/dev/null
  sleep 45
  xcrun simctl io "$on" screenshot "$out/$name.png" >/dev/null
}
for appearance in light dark; do
  photo_shot "$device" "de-$appearance-photo-offer" offer "$appearance" de
  photo_shot "$device" "de-$appearance-photo-cleaned" cleaned "$appearance" de
done
# The start: with documents (recent), without (empty), "So funktioniert's"
# (help), scrolled past its card (scrolled).
start=(recent empty help scrolled)
frames "$device" de-light light de "" "${start[@]}"
frames "$device" de-dark dark de "" "${start[@]}"
frames "$device" de-accessibility-xxxl light de UICTContentSizeCategoryAccessibilityXXXL recent empty
frames "$device" de-light light de "" assistant own list
frames "$device" de-dark dark de "" assistant own list
frames "$device" de-accessibility-xxxl light de UICTContentSizeCategoryAccessibilityXXXL tab editor warning sheet list text
frames "$device" de-xxxl light de UICTContentSizeCategoryXXXL editor sheet text
frames "$device" ar-light light ar "" tab editor sheet text
frames "$device" en-light light en "" editor sheet text

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
    -only-testing:"SnapflyUITests/ScanUITests/$test" CODE_SIGNING_ALLOWED=NO SWIFT_OPTIMIZATION_LEVEL=-O -quiet \
    test-without-building || echo "The walk $test did not finish." >&2
  sleep 1
  kill -INT "$recorder" 2>/dev/null || true
  wait "$recorder" 2>/dev/null || true
}
(
  if [ -f "$photo" ]; then record from-photos testRecordFromPhotosToSharing; fi
  if [ -f "$photo" ] && [ -f "$blurred" ]; then record two-photos testPhotosChosenTogetherKeepTheOrderTheyWereChosenIn; fi
  record cleaning-a-photo testRecordCleaningAPhotographedDocument
  record name-and-hand-over testRecordNameAndHandOver
  record start testRecordTheStart
  record reduce-motion-start testRecordTheStart still
  record wipe-and-compare testRecordWipeAndCompare
  record pages-and-warning testRecordPagesAndWarning
  if [ -f "$photo" ]; then record reduce-motion-from-photos testRecordFromPhotosToSharing still; fi
  record reduce-motion-wipe-and-compare testRecordWipeAndCompare still
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
    xcrun simctl launch "$small" "$bundle" -SnapflyScan editor >/dev/null
    sleep 40
    frames "$small" de-small light de ""
    frames "$small" de-small light de "" "${start[@]}"
    frames "$small" de-small-dark dark de "" recent empty
    frames "$small" de-small-accessibility-xxxl light de UICTContentSizeCategoryAccessibilityXXXL recent
    photo_shot "$small" de-small-photo-offer offer light de
    frames "$small" de-small-dark dark de "" editor warning sheet own list
    frames "$small" de-small-accessibility-xxxl light de UICTContentSizeCategoryAccessibilityXXXL editor sheet list
  ) || echo "The smallest iPhone could not be captured." >&2
  xcrun simctl shutdown "$small" || true
fi

ls -l "$out"
if [ "$engine" != 0 ]; then
  echo "The scan's fixture tests failed." >&2
  exit "$engine"
fi
if [ "$tests" != 0 ]; then
  echo "The UI tests failed." >&2
  exit "$tests"
fi

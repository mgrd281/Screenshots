#!/bin/bash
# PDF projects without an iPhone, for review. First the engine on this Mac:
# the PDF tests (Tests/TendederoTests/PDFFixtureTests.swift and
# PDFProjectTests.swift) on made-up files: a three-page invoice with real
# text, the same locked with a password, a signed contract, 300 pages and
# photos of a narrow receipt and a page lying sideways (PDF_CAPTURES keeps
# the numbers). Then the app on the simulator, Debug but optimized: its UI
# tests (iOS/SnapflyUITests/PDFUITests.swift), with the frames counted while
# 300 pages scroll and while a page is dragged; still frames of the Scan
# tab's PDF card, the pages' overview, pages chosen, a page deleted with
# Undo, the editor, Save and Share, a locked and a signed PDF and 300 pages
# (-SnapflyProject), in German, light and dark, at the largest accessibility
# text size, on the newest iPhone the runner has and on the smallest, and in
# Arabic and English; then videos of merging and dragging pages (simctl io
# recordVideo), and the same with Reduce Motion. Writes everything to
# captures/pdf and the test results to build/pdf.xcresult. A failed test
# fails the run, once the frames are made.
set -euo pipefail

out=captures/pdf
derived=build/pdf
bundle=de.ghazarian.Snapfly
mkdir -p "$out" build

# The engine, with its numbers.
engine=0
PDF_CAPTURES="$PWD/$out" swift test --filter "PDFFixtureTests|PDFProjectTests|PDFPageGeometryTests" || engine=$?

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
  -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO SWIFT_OPTIMIZATION_LEVEL=-O -quiet build-for-testing
app="$derived/Build/Products/Debug-iphonesimulator/Snapfly.app"

# The UI tests, in light; the walks for the videos skip themselves here.
# Their numbers ("PDF-NUMBERS") go with the engine's.
xcrun simctl ui "$device" appearance light
tests=0
rm -rf build/pdf.xcresult
xcodebuild -project iOS/Snapfly.xcodeproj -scheme Snapfly -destination "id=$device" -derivedDataPath "$derived" \
  -only-testing:SnapflyUITests/PDFUITests -resultBundlePath build/pdf.xcresult CODE_SIGNING_ALLOWED=NO \
  SWIFT_OPTIMIZATION_LEVEL=-O test-without-building 2>&1 | tee build/pdf-tests.log || tests=$?
{
  echo "Frames counted on the simulator ($(xcrun simctl list devices | grep "$device" | sed 's/ (.*//' | xargs)), not on a phone:"
  grep -o "PDF-NUMBERS .*" build/pdf-tests.log | sed 's/^PDF-NUMBERS //' | sort -u || echo "none"
} >> "$out/pdf-300-pages.txt"

xcrun simctl install "$device" "$app"

# A frame of a state, as the made-up project opens it: on a device, in an
# appearance and a language, at a text size when one is given.
shot() {
  local on=$1 name=$2 state=$3 appearance=$4 language=$5 size=${6:-}
  local arguments=(-SnapflyProject "$state" -AppleLanguages "($language)" -AppleLocale "$language")
  if [ -n "$size" ]; then arguments+=(-UIPreferredContentSizeCategoryName "$size"); fi
  local settle=25
  if [ "$state" = long ] || [ "$state" = editor ] || [ "$state" = export ]; then settle=45; fi
  xcrun simctl ui "$on" appearance "$appearance"
  xcrun simctl terminate "$on" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl launch "$on" "$bundle" "${arguments[@]}" >/dev/null
  sleep "$settle"
  xcrun simctl io "$on" screenshot "$out/$name.png" >/dev/null
}

# Once to warm up: a first launch takes longer than the frame waits.
xcrun simctl launch "$device" "$bundle" -SnapflyProject overview >/dev/null
sleep 40
xcrun simctl terminate "$device" "$bundle" >/dev/null 2>&1 || true

frames() {
  local on=$1 prefix=$2 appearance=$3 language=$4 size=$5
  shift 5
  local states=("$@")
  if [ ${#states[@]} -eq 0 ]; then states=(tab empty overview select deleted editor export uncovered locked signed long); fi
  for state in "${states[@]}"; do
    shot "$on" "$prefix-$state" "$state" "$appearance" "$language" "$size"
  done
}
frames "$device" de-light light de ""
frames "$device" de-dark dark de ""
frames "$device" de-accessibility-xxxl light de UICTContentSizeCategoryAccessibilityXXXL tab overview select editor export
frames "$device" ar-light light ar "" tab overview editor export
frames "$device" en-light light en "" overview export

# Videos of the walk: the motion as it plays, then with Reduce Motion.
# Never a reason to stop.
record() {
  local name=$1 test=$2 still=${3:-}
  xcrun simctl ui "$device" appearance light
  xcrun simctl io "$device" recordVideo --codec=h264 --force "$out/$name.mp4" >/dev/null 2>&1 &
  local recorder=$!
  sleep 2
  env TEST_RUNNER_SNAPFLY_RECORD=1 ${still:+TEST_RUNNER_SNAPFLY_STILL=1} \
    xcodebuild -project iOS/Snapfly.xcodeproj -scheme Snapfly -destination "id=$device" -derivedDataPath "$derived" \
    -only-testing:"SnapflyUITests/PDFUITests/$test" CODE_SIGNING_ALLOWED=NO SWIFT_OPTIMIZATION_LEVEL=-O -quiet \
    test-without-building || echo "The walk $test did not finish." >&2
  sleep 1
  kill -INT "$recorder" 2>/dev/null || true
  wait "$recorder" 2>/dev/null || true
}
(
  record merging-and-dragging testRecordMergingAndDragging
  record reduce-motion-merging-and-dragging testRecordMergingAndDragging still
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
    xcrun simctl launch "$small" "$bundle" -SnapflyProject overview >/dev/null
    sleep 40
    frames "$small" de-small light de "" tab overview select editor export
    frames "$small" de-small-dark dark de "" overview editor export
    frames "$small" de-small-accessibility-xxxl light de UICTContentSizeCategoryAccessibilityXXXL overview export
  ) || echo "The smallest iPhone could not be captured." >&2
  xcrun simctl shutdown "$small" || true
fi

ls -l "$out"
if [ "$engine" != 0 ]; then
  echo "The PDF tests on this Mac failed." >&2
  exit "$engine"
fi
if [ "$tests" != 0 ]; then
  echo "The UI tests failed." >&2
  exit "$tests"
fi

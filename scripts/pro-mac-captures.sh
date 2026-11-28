#!/bin/bash
# The Snapfly Pro window on the Mac, for review without a Mac: builds the
# edition from the website in debug, then opens the window alone on made-up
# prices (-SnapflyPro), in German, light and dark, once in Arabic and once
# in English, with a locked feature, and in every other phase in German and
# light. Snapfly draws the window into a picture itself (-SnapflyProPreview)
# and quits, so no picture of the screen is taken. Writes
# captures/pro-mac-*.png.
# A frame that cannot be made is said and skipped; the script fails only at
# the end, so that the run shows it, and the workflow carries on regardless.
# Usage: scripts/pro-mac-captures.sh
set -euo pipefail
cd "$(dirname "$0")/.."

out=captures
mkdir -p "$out"

# One architecture, this Mac's, is enough to look at. Not the App Store
# edition: the website's is not sandboxed, so it can write the picture here.
if ! STORE="" ARCHS="${ARCHS:-$(uname -m)}" scripts/build-app.sh debug; then
  echo "::warning::The Mac app could not be built, so the Pro window was not captured."
  exit 1
fi
app=build/Snapfly.app
executable=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$app/Contents/Info.plist" 2>/dev/null || echo Snapfly)
binary="$app/Contents/MacOS/$executable"

# Runs a command for at most some seconds, and stops it after that.
within() {
  local seconds=$1
  shift
  "$@" &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$seconds" ]; then
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      echo "Stopped after $seconds seconds." >&2
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

made=0
failed=0

# A frame of a phase, as the sample opens it: in a language, light unless
# -SnapflyProDark follows, with more arguments after it. Snapfly writes the
# PNG and quits by itself; one that hangs is stopped after a minute.
frame() {
  local shot=$1 language=$2 phase=$3
  shift 3
  local file="$PWD/$out/pro-mac-$shot.png" status=0
  rm -f "$file"
  echo "== pro-mac-$shot"
  within 60 "$binary" -AppleLanguages "($language)" -AppleLocale "$language" \
    -SnapflyPro "$phase" -SnapflyProPreview "$file" "$@" || status=$?
  if [ "$status" = 0 ] && [ -s "$file" ]; then
    made=$((made + 1))
  else
    failed=$((failed + 1))
    echo "::warning::The Pro window could not be captured as pro-mac-$shot.png (exit $status)."
  fi
}

frame offers-de-light de offers
frame offers-de-dark de offers -SnapflyProDark
frame offers-ar-light ar offers
frame offers-en-light en offers
# A locked feature, named over the title and marked among the features.
frame order-card-de-light de offers -SnapflyProFeature orderCard
# Every other phase the window can be in, ending with this copy's own: one
# from the website, which cannot subscribe.
for phase in loading unavailable buying pending welcome subscribed keeps elsewhere; do
  frame "$phase-de-light" de "$phase"
done

ls -l "$out"/pro-mac-*.png 2>/dev/null || true
if [ "$failed" != 0 ]; then
  echo "$failed of $((made + failed)) frames of the Pro window could not be made." >&2
  exit 1
fi

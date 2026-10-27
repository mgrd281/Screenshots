# App Review

What to paste into App Store Connect for the Mac App Store edition, and
what each review's findings asked for. Nothing here is sent by a script:
the owner pastes it.

## Notes for the reviewer

Paste into the macOS version page › App Review Information › Notes:

```
Snapfly is a menu bar app: it has no Dock icon and no main window by design.

- After launch, its icon (a small photo on a line) is in the menu bar. Click it for the menu, which also opens Settings.
- On the first launch, a welcome card appears in the middle of the screen.
- Opening Snapfly again from the Applications folder, Launchpad or Spotlight while it runs opens its Settings window.
- If the menu bar has no room for the icon, for example on a MacBook with a camera notch and many menu bar items, Snapfly opens Settings by itself and says so.

To try it: press Control-Option-S, then drag over any area of the screen. The screenshot hangs on a line at the top of the screen. Click its paper plane to paste it into the app in front, with names and other private details already covered.

Snapfly is not offered in China mainland.
```

## October 2026, version 1.0 (204)

- **2.1(a), App Completeness.** The reviewer, on macOS 27, saw no window
  and no menu bar icon. From the first build after this change,
  opening Snapfly again opens Settings, and a launch whose menu bar icon
  cannot be seen opens Settings by itself. The Build Snapfly workflow opens
  the sandboxed App Store edition at every push (`scripts/launch-check.sh`)
  and fails when nothing shows.
- **2.3.7, Accurate Metadata.** The first screenshot said "Kostenlos"
  (free). `1-hero.jpg` no longer has the price line or the download button.
- **5, Legal (China).** ChatGPT is named in the metadata and the app can
  paste into it. The owner takes China mainland out of Pricing and
  Availability, which Apple offers instead of removing the feature.

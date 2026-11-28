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
- If the icon does not show, Snapfly opens Settings by itself and says why. On macOS 26 and later, the icon shows only while Snapfly is turned on in System Settings › Menu Bar, under Allow in the Menu Bar; on a MacBook with a camera notch, a full menu bar can hide it.

To try it: press Control-Option-S, then drag over any area of the screen. The screenshot hangs on a line at the top of the screen. Click its paper plane to paste it into the app in front, with names and other private details already covered.

Snapfly is not offered in China mainland.
```

## When Snapfly Pro begins

None of this applies yet. Until the owner sets `Plan.proStarts`, nothing
is locked, the Pro screen never shows, and the app never asks the App Store
for its products. On that day, in App Store Connect:

1. **The subscriptions.** Under the app's Monetization › Subscriptions, one
   subscription group, "Snapfly Pro", with two auto-renewable
   subscriptions on one level: they open the same features and differ only
   in length.

   | Reference name | Product ID | Length |
   |:--|:--|:--|
   | Snapfly Pro Yearly | `de.ghazarian.Snapfly.pro.yearly` | 1 year |
   | Snapfly Pro Monthly | `de.ghazarian.Snapfly.pro.monthly` | 1 month |

   - The IDs must be exactly these (`ProProducts` in
     `Sources/Tendedero/Shared/ProPlan.swift`). The app asks for these two
     and nothing else; without them, its screen says the prices could not
     be loaded.
   - The Mac and the iPhone share one app record, so this one group opens
     Pro on both, as Guideline 3.1.2(a) asks.
   - Give the group and each subscription a display name and a description
     in every language the listing has.
   - The app shows the App Store's own prices and words, so any price, and
     a free trial as an introductory offer, needs no change in the app. The
     yearly plan says how much it saves only from 5%.
   - Each subscription needs a review screenshot of the Pro screen. The
     `first-run-captures` pre-release has them, `pro-offers-en-light.png`
     (iPhone) and `pro-mac-offers-en-light.png` (Mac), with made-up prices;
     where those differ from the real ones, take it from TestFlight.

2. **With a new version.** The first auto-renewable subscription must be
   submitted with a new app version, together with its group. Set
   `Plan.proStarts` in that version, raise `VERSION` with its
   `CHANGELOG.md` section, and on the version's page, under In-App
   Purchases and Subscriptions, choose both subscriptions before Add for
   Review. Only the first needs a version; later ones go to review on
   their own. The day set must have come by the time of the review:
   before it, nothing is locked and neither About nor More shows the way
   to the Pro screen, so the reviewer could not find it.

3. **Terms of Use (EULA) in every description.** Snapfly uses Apple's
   standard licence agreement (App Information › License Agreement stays
   empty). App Review then asks for a working link to the Terms of Use in
   the description, in every localization of both the iOS and the macOS
   version page: one localization without it is enough for a rejection.
   Add these lines at the end of every
   `docs/store/listing/<language>/ios/description.txt` and
   `macos/description.txt`, then paste them.

   English (`en-US`):
   ```
   Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
   Snapfly's terms: https://mgrd281.github.io/Screenshots/terms.html
   Privacy Policy: https://mgrd281.github.io/Screenshots/privacy.html
   ```

   German (`de-DE`):
   ```
   Lizenzvertrag (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
   AGB: https://mgrd281.github.io/Screenshots/de/terms.html
   Datenschutz: https://mgrd281.github.io/Screenshots/de/privacy.html
   ```

   Arabic (`ar-SA`):
   ```
   شروط الاستخدام (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
   شروط Snapfly: https://mgrd281.github.io/Screenshots/ar/terms.html
   سياسة الخصوصية: https://mgrd281.github.io/Screenshots/ar/privacy.html
   ```

   - The other eight languages take the English lines, with "Terms of Use"
     and "Privacy Policy" in the words their `Localizable.strings` gives.
   - The listing's own rules give way here. `listing/README.md` says
     "nothing about Pro", and `listing/check.py` refuses the words
     "snapfly pro" and "pro version". These lines name neither, but a
     description that names Pro needs both changed first. `check.py`
     also warns when a description passes 2200 characters, which these
     lines make the German ones do; that is a warning, not a failure.

4. **Privacy.** The Privacy Policy URL in App Information stays
   https://mgrd281.github.io/Screenshots/privacy.html. Its Snapfly Pro
   section says what a purchase involves, and the Pro screen links to it.
   App Privacy needs nothing new for Pro: the developer receives nothing
   about a purchase, and the App Store's answer stays on the device.

5. **Notes for the reviewer.** Paste into each subscription's Review
   Information › Review Notes, and add it to the notes on both version
   pages:

   ```
   Snapfly Pro is an optional auto-renewable subscription, yearly or monthly, in the subscription group "Snapfly Pro". One subscription opens Pro in Snapfly on the Mac and on the iPhone with the same Apple account. Snapfly has no account, sign-in or server of its own.

   Where to find it:
   - Mac: click Snapfly's icon in the menu bar, then Settings… › About › Snapfly Pro…. A Pro feature opens it too, for example Edit › Draw on Photo… in a photo's menu (right-click a screenshot on the line). The first time a day, the Snapfly Pro window opens; after that, a short note says the feature is part of Snapfly Pro, and clicking the note opens the window.
   - iPhone: More › Features › Snapfly Pro.

   The screen lists every feature Pro adds and shows each plan's price as the App Store gives it. Before the Subscribe button it says what is billed and when it renews. It has Restore Purchases, and links to the Terms of Use, the Privacy Policy, the Withdrawal Policy, Apple's page to withdraw from the purchase, and the subscription's management.

   Covering private details is free and never part of Pro. Whoever used Snapfly on a Mac or an iPhone before Pro began keeps every feature without subscribing; a fresh install, as yours is, shows the Pro features locked.

   The copy of Snapfly downloaded from the developer's website cannot subscribe. The Mac App Store edition you are reviewing can.
   ```

## October 2026, version 1.0 (204)

- **2.1(a), App Completeness.** The reviewer, on macOS 27, saw no window
  and no menu bar icon. On macOS 26 in CI the sandboxed App Store edition
  opens, shows the welcome, and Control Center shows its icon; why the
  reviewer saw none is not known. Since a later launch shows only the icon,
  an icon turned off in System Settings › Menu Bar (macOS 26 and later) or
  hidden by the camera's notch leaves nothing to see. From the first build
  after this change, opening Snapfly again opens Settings, and a launch
  whose icon is not shown opens Settings by itself, once the welcome and
  the first question are gone, with a note on how to bring the icon back.
  The Build Snapfly workflow opens the sandboxed App Store edition at every
  push (`scripts/launch-check.sh`) and fails when nothing shows, when it
  crashes, or when Settings opens although the icon shows.
- **2.3.7, Accurate Metadata.** The first screenshot said "Kostenlos"
  (free). `1-hero.jpg` no longer has the price line or the download button.
- **5, Legal (China).** ChatGPT is named in the metadata and the app can
  paste into it. The owner takes China mainland out of Pricing and
  Availability, which Apple offers instead of removing the feature.

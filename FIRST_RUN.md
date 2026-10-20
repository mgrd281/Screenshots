# The iPhone's first run

What a new owner sees when Snapfly opens for the first time, why, and how it
is built, tested and measured. The rules for how it looks and moves are in
`DESIGN.md` (iPhone › The first run) and `MOTION_SYSTEM.md`; this file keeps
the reasoning and the record.

## 1. Audit of the first launch before it

What shipped until October 2026 (`WelcomeScreen`, `CoverDemo.swift`, PR #171):

- It showed in the Photos tab only while access to Photos was not yet
  asked, so it was tied to a permission, not to being new. Whoever had
  answered the Photos prompt never saw it again, and nothing could show it
  again.
- It was one card: a made-up contact covered detail by detail in about
  3.5 s, then "Covered before you send" and Allow Access. Good first two
  seconds, but nothing to touch except a replay.
- It covered everything on the card. Nothing showed that useful content
  stays readable, or that the owner chooses what is covered.
- It did not show the scanner, sharing, or that only the covered copy
  leaves.
- It hid the tab bar until Photos access was answered, so a new owner
  could not scan a document first.

What already met the brief, and stays as it is:

- **The real scanner** (Scan tab) is VisionKit's document camera. It finds
  and straightens the page, then opens it in Protect Picture. There Vision
  reads it, the engine finds and covers what Settings chose, the owner
  checks and corrects places, and Copy, Share and Save go once the copy is
  made, read again and checked.
- **Sharing** passes only the checked covered copy, as a PNG named by date,
  to the system share sheet, and deletes the file once the sheet closes.
  Nothing is uploaded silently.
- **The engine** (`Finder`) reads names by their labels and roles, emails
  and IBANs by their shape, and amounts as amounts, all on the device.

## 2. The new journey

```
open → the invoice, readable (0 s)
     → read, found, covered; the amount stays (by 2 s)     "Private stays private."
     → the owner turns Names, Emails, Bank details          "You decide what stays visible."
     → the page before the camera: found, straightened,
       read, covered as chosen                              "Scan. Detect. Protect."
     → a small protected copy and where it could go         "Protected. Ready to share."
     → what Snapfly is for, and Try It Now                  "Share your documents. Not your private data."
Try It Now → the real scanner (Scan tab) → Protect Picture → Share
Skip Demo (any time) / Not Now (at the end) → the app
```

Visible, then detected, then protected, then ready to share: one page
moves through all of it, so it never reads as a slideshow. The Photos
prompt waits for the Photos tab, where a calm card asks for it.

## 3. Storyboard

The story is `FirstRun.script` (in `Shared/FirstRun.swift`): beats on a
story clock in seconds. `FirstRun.state(at:)` gives the state a moment
shows, and CI's still frames use it too. The phases are those of
`FirstRun.Phase`.

| Time (s) | Scene | Phase | What happens |
|---|---|---|---|
| 0 | reveal | initial | The invoice, readable, from the first frame; Skip Demo under it |
| 0.25 | reveal | detecting | The reading light crosses the page (0.9 s) |
| 0.43, 0.47, 0.9 | reveal | detecting | Name, email, IBAN found as the light reaches each |
| 1.15 | reveal | highlighted | All three marked |
| 1.3, 1.47, 1.64 | reveal | redacting | Each covered from the reading side |
| 1.85 | reveal | protected | The shield lands; success haptic |
| 2.2 | control | protected | Names, Emails, Bank details rise in as chips |
| 3.4 | control | revealing | The name comes off, as a tap would do it (unless the owner tapped first) |
| 3.75 | control | protected | |
| 4.8 | control | redacting | The name goes on again |
| 5.15 | control | protected | |
| 6.2 | scan | initial | The stage becomes the camera; the page, printed again, lies in it at 80%, tipped away, the shutter under it |
| 6.8 | scan | detecting | Its edges found, lit and locking on; light haptic |
| 7.6 | scan | detecting | Taken (the shutter pressed, one flash) and straightened |
| 8.2 | scan | detecting | Read: the light crosses it; what is chosen is found |
| 9.2 | scan | highlighted | |
| 9.35, 9.52, 9.69 | scan | redacting | Covered as chosen |
| 9.9 | scan | protected | The shield again (no haptic, so it never buzzes twice alike) |
| 10.4 | share | protected | The page goes small; the share row and "Only the protected copy leaves your iPhone." |
| 13.6 | complete | complete | The message, and Try It Now over Not Now |

- **Paused.** The clock stands still for 2.5 s after the owner's last tap
  and while the app is away. The reported phase is then `paused`.
- **The owner's taps.** A tap changes `chosen`, the one source of truth.
  The covers follow it and the story never changes the categories for
  them again. Rapid taps end where the last one leaves them; every cover
  animates from where it is, so nothing overlaps or races.
- **Skip Demo** ends it at once.
- **The bars** over the story fill scene by scene and stand still with
  it, so it reads as short and as waiting for the owner.
- **Each scene has a line** under its headline: what is found, how to turn
  a category (the chips say nothing of being tappable on their own), what
  the scanner does, that only the protected copy leaves, and at the end
  what Snapfly is for.
- **The tabs behind it** are made once it is over, so reading Photos and
  starting sync never take from its first seconds.

## 4. Components

| Component | Where | What it does |
|---|---|---|
| `FirstRun` | `Sources/Tendedero/Shared/FirstRun.swift` | The story: categories, the sample, the script, the state machine, the scanner's perspective (homography), pure and tested on Linux |
| `FirstRunCoordinator` | `iOS/Snapfly/FirstRunExperience.swift` | Whether it shows (once per version, `firstRunSeen`), replay from Settings, Try It Now and Skip |
| `SnapflyFirstRunExperience` | same | The screen, and the driver that plays the script on the story clock |
| `SampleInvoice` | same | The invoice, printed as a real one (letterhead, Bill To, number and date, items, sums, direct debit, small print) and standing as an A4 page as tall as the screen allows, its details found and covered (the privacy reveal) |
| `PrivacyChips` | same | The interactive categories |
| `ScanCamera`, `CaptureFlash`, `Straightened`, `EdgeLock`, `ReadingLight` | same | The scan demonstration: the camera filling the stage with its shutter, the flash as the page is taken, the perspective correction, the edges locking on, and the light that reads the page |
| `ShareDestinations` | same | The protected copy's destinations, as a picture of the share sheet |
| `SnapflyMotion`, `PressStyle` | `iOS/Snapfly/Motion.swift` | The named motion tokens and their calm answers |

Nothing is duplicated: the old `CoverDemo.swift` is gone, and the scanner,
the editor and the share sheet are the app's own.

**October 2026, the owner's request:** the invoice looked drawn (grey
lines for words) and the scan old (green corner brackets). Now the page is
a real invoice in every word, its finds are lit as selected text is, and
the scan is a camera: the stage turns dark, the edges are lit with
handles at the corners, the shutter takes the page with one flash, and a
light, not a line, reads it.

## 5. The engine and the sample

- The sample is made up: a placeholder name, an address at `example.com`,
  the standard example IBAN and an amount. The rest of the page (a studio
  called Example Studio at www.example.com, its invoice number, the
  items and sums, the small print) belongs to no one either, and holds
  nothing private, so the three categories are all there is to cover. It
  has no postal address and no customer number for that reason.
- Which category covers which detail is a fixture, held to the engine by
  `FirstRunTests`. On the invoice as text, in German and in English:
  - Names covers only the name;
  - Emails covers only the email;
  - Bank details covers only the IBAN;
  - the amount is an amount to the engine, and none of the three covers it.
- So the first run shows nothing the engine would not do.
- It is a demonstration, never proof that a real page was read. The page
  says "Sample", nothing on it is read by Vision, and the real scanner
  uses only what the engine finds there.

## 6. Accessibility

- **VoiceOver:** no story playing. It starts at its end, the invoice one
  element ("Sample invoice", each detail Covered or its value). The chips
  say Covered or Not covered, and each change is announced. The share row
  is one sentence.
- **Reduce Motion and Low Power Mode:** no reading light, no tilt, no
  flash and no growing ink. Covers and scenes cross-fade in 0.15–0.2 s; haptics stay
  where they mean something.
- **Dynamic Type:** the words follow it; the page is printed at its own
  sizes, grown with the page, as paper is. Past what fits, the screen
  scrolls; the chips drop their eyes, then stack.
- **Layout:** safe areas are kept, so nothing sits under the home indicator
  or the Dynamic Island. Every control is at least 44 pt to the finger.
  The page stays left to right in right-to-left languages, as a printed
  invoice does; everything else follows the language.
- **Landscape:** none on the iPhone; the app is portrait-only.

## 7. Tests

- `Tests/TendederoTests/FirstRunTests.swift` (in `swift test` in CI, and
  on Linux) checks:
  - the sample against the engine;
  - that it opens readable and is protected within 2 s;
  - that details are found as the line reaches them, then covered in turn;
  - that the script keeps its order, ends within 15 s and goes through its
    phases in order;
  - turning a category off and on;
  - rapid taps;
  - that the story leaves the owner's choice alone;
  - that the scan finds and covers only what is chosen;
  - the paused and complete states;
  - that with nothing chosen there is no shield;
  - that the perspective's corners map exactly.
- **First Run Captures** (`.github/workflows/first-run-captures.yml`,
  `scripts/first-run-captures.sh`) runs when the first run changes, and by
  hand.
  - It builds the app for the simulator and plays the first run from a
    fresh install while recording it.
  - It checks the app is still running after the story: a smoke test.
  - It keeps still frames at 13 moments in German, light and dark ones,
    Arabic and English, and main's first launch beside them.
  - Everything goes on the `first-run-captures` pre-release.
- **No snapshot comparison.** Snapshot images drift between simulator and
  Xcode versions, so a pixel diff would fail on what nobody changed.
  `swift-snapshot-testing` was left out for that reason; the frames are
  for people to look at.

## 8. Measurements

- The app logs two numbers, as numbers only, under
  `de.ghazarian.Snapfly`:
  - how long after launch the first run showed;
  - how long after that the invoice was protected.
- The captures workflow writes them to `measurements.txt` beside the
  frames. They come from the simulator, so they say how the screen behaves,
  not how fast a phone is.
- The targets:
  - the first visual change within 300 ms of the screen being ready (the
    page is there in the first frame, and the line starts at 0.25 s);
  - the reveal done within 2 s (1.85 s by the script).
- To be measured on devices, with Instruments' SwiftUI and Core Animation
  templates:
  - frame pacing;
  - memory;
  - battery;
  - time to the first interaction, the first successful scan and the
    first protected share.

## 9. Dependencies

None added.

- **Rive** and **Lottie** would bring a runtime of several megabytes and
  an authoring tool for motion that SwiftUI draws here in vectors from the
  app's own tokens, offline, with Reduce Motion handled in one place.
- **Swift Snapshot Testing** would bring baselines that drift (see Tests).

The owner's rule is no unnecessary dependencies.

## 10. Limitations

- **Nobody has watched it on a phone yet.** It was built without an iPhone
  or a Mac. It compiles in CI, and the captures show it on the simulator,
  but haptics, real frame pacing and battery need a device.
- **The 15-second goal is a target, not a result.** Whether people can say
  after 15 seconds what Snapfly does, why they would use it and how they
  would protect a document needs usability tests with new owners. The
  three questions are those, and none has been run.
- **The scan is acted, and says so** ("Sample" on the page). The real
  scanner is VisionKit's, and it detects nothing it did not read.
- **The share row is a picture**: no logos, and no claim that Snapfly
  works with any of those apps; the system's share sheet decides.
- **Existing owners see it once after the update** that brings it (version
  1), then only from Settings.

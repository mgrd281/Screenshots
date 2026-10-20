# Snapfly Live Protection: audit (Run 1)

This is Run 1 of "Snapfly: Live Protection Experience, Implementation Spec
v3": an audit of the iPhone app against the spec, with no code changes. It
says how the app works today, resolves every row of the spec's section 4,
lists every place where the spec and the code disagree with a proposed
solution, and checks the four blockers.

- Line references are to `main` at `cc5579e`, after pull request #186. Its
  files are the same as at #186's head, `f4abfc9`.
- Every statement rests on a line read in this repository, a test, or a CI
  run named in "Evidence". Anything that cannot be checked here is marked
  **not verified**, with the steps to check it.
- "The spec" means Spec v3. "Covering" is the codebase's word for
  redaction; "a look" is its word for a redaction style.

## 0. Verdict

- **No blocker is hit** (section 18). The stages can be observed without
  restructuring the engine; the output is never an edit of the original and
  the original never reaches a share sheet; every look writes opaque pixels;
  every required API is available on iOS 17, except
  `BGContinuedProcessingTask`, which the spec only lets us propose.
- **One serious existing defect.** Protect Picture (the editor) does not fail
  closed when Vision cannot read a picture: it shows "Nothing private found"
  and lets the uncovered picture leave (D1, section 14). The batch, quick
  cover, the share extension and Shortcuts already fail closed (`CoveredCopy`).
- **Three decisions for the owner before Run 2**, each with a recommended
  default that Run 2 follows if the owner just says go on (section 17):
  1. The cover looks. All six are opaque, and by their code none takes a
     pixel from inside a covered place. A test checks one case of it
     (section 5). The spec's premise that blur and pixelation can be undone
     does not hold here.
     Recommended: every look can earn `.protected`; `.obscured` is never
     emitted (C1).
  2. Leaving the app during a run. Recommended: background time only to
     finish writing what is already verified; no covering in the background,
     as the app decided in #184 (C10).
  3. Scope. Recommended: the new verifier also guards every way out of
     Protect Picture, because the panel's review leads there (C18, C19).
- **Seen in this run's simulator captures:** an English invoice comes out
  heavily covered: the title and table rows under "BILL TO" (D13). Nothing
  leaks, but the engine needs a general fix.
- **The reference screenshot of the target home screen did not arrive.**
  Run 3 needs it for the visual comparison.

## 1. Inputs, resolved from the repository

| Input | Value | Evidence |
|---|---|---|
| Deployment target | iOS 17.0 for the app and its share extension; iPhone only. macOS 14 for the Mac app. | `iOS/Snapfly.xcodeproj/project.pbxproj:260,279` (`IPHONEOS_DEPLOYMENT_TARGET = 17.0`), `:319,355` (`TARGETED_DEVICE_FAMILY = 1`); `Package.swift` and CLAUDE.md for macOS 14 |
| Language mode | Swift 5 | `project.pbxproj:265,282` (`SWIFT_VERSION = 5.0`) |
| SDK and CI | Xcode with the iOS 26 SDK on GitHub's macOS 26 runners. `swift test` runs the XCTest suite on macOS; the `iphone` job archives the app unsigned; First Run Captures drives the iOS Simulator. There is no iOS test target. | `.github/workflows/build.yml:32-33`, `.github/workflows/first-run-captures.yml`, `scripts/first-run-captures.sh` |
| State management | `ObservableObject` classes, `@MainActor`, with `@Published` (`BatchCover`, `QuickCoverer`, `PhotoIndexer`, `ProtectSession`, `Library`), mostly as singletons; selection state in views (`@State GridSelection?`). No `@Observable`. Vision work runs on GCD queues bridged with `withCheckedContinuation`. | `iOS/Snapfly/Selecting.swift:13-23`, `AppTabs.swift:129-135`, `ProtectSession.swift:13-60`, `ContentView.swift:30-35` |
| Apple Intelligence | FoundationModels on iOS 26 and later, checked at runtime (`SystemLanguageModel.default.availability`), on by default, a setting turns it off. Optional cloud assistant (the owner's own Claude or ChatGPT key), off unless the owner turns it on. | `Sources/Tendedero/Shared/Protection.swift:19-40` |
| Real iPhone | None here. The owner tests through TestFlight; the iOS Simulator in CI is the only screen we can see. | CLAUDE.md, `first-run-captures.yml` |
| Reference screenshot | Not received. | the spec message |
| Languages | 13: ar, az, de, en, es, fr, gl, hi, ja, ko, pt-BR, tr, zh-Hans, each key `L("English")`, checked in CI. | `scripts/check-strings.swift`, CLAUDE.md |

## 2. Home screen, gallery and the legacy progress bar

**Where things are.**

- The home screen is the Photos tab, `PhotosTab` (`ContentView.swift:11-369`): the
  title, the sync chip, the picture of stacked photos with Protect a Photo,
  the row of what the Mac sent, and the newest screenshots in three rows.
- The grid is `ScreenshotGrid` (`HomeParts.swift:418-553`): three or four
  to a row, pinched (`GridZoom`), cards from `ScreenshotCard`
  (`HomeParts.swift:270-376`).
- See All is `AllScreenshotsView` (`HomeParts.swift:558-713`): search,
  filters, sort, per row, and the same choosing.
- The Protected tab is `ProtectedTab` (`AppTabs.swift:197-240`): the last
  twelve screenshots protected, from `Recent` (`ProtectSession.swift:396-405`).
- Choosing several: Select, then a tap or a sideways sweep (`GridSelection`,
  `SweepToChoose`), then `SelectionBar` (`Selecting.swift:202-276`) with
  Share and Save Covered Copies (n).

**The legacy bar** is the linear `ProgressView` in `SelectionBar`
(`Selecting.swift:217-218`), under "Covering %d of %d …" with a Stop button
(`:213-221`). It is the only linear bar for protection work on the home
screen and in See All, which share `SelectionBar`.

- It is driven by real work, not a timer. `BatchCover.run` sets
  `progress = (index, total)` as each screenshot starts (`Selecting.swift:83`)
  and `(total, total)` at the end (`:120`), then clears it at once (`:68-71`).
  The bar therefore counts screenshots saved or failed alike, and never
  says which. Those skipped after Stop only count in the last value, which
  is cleared in the same turn, so they never show.
- Success is a note for 3 seconds, "n covered copies saved to Photos", and a
  success haptic (`:154-161`). Problems stay in the bar in orange
  (`:244-249`, `:171-173`).
- The bar sits in `.safeAreaInset(edge: .bottom)` (`ContentView.swift:126-131`,
  `HomeParts.swift:623-628`), so it changes the scroll view's bottom inset as
  it comes and goes. The tab bar hides while choosing
  (`ContentView.swift:132`, `HomeParts.swift:629`), and the grid is
  disabled while a run goes on (`ContentView.swift:273`, `HomeParts.swift:584`).

**Thumbnails.**

- PhotoKit makes them: `PHCachingImageManager`, 360 points wide,
  `resizeMode = .fast`, kept in an `NSCache` of 64 MB keyed by identifier,
  width and modification date (`Library.swift:63-110`). The full picture is
  never decoded for a card.
- A card shows a green `checkmark.shield.fill` when the screenshot is in
  `Recent` (`HomeParts.swift:315-324`). `Recent` records the *source*
  screenshot when a covered copy of it is copied, saved, sent or shared
  (`ProtectSession.swift:347-350`, `AppTabs.swift:171`,
  `Selecting.swift:117`, `Intents.swift:36`). The batch's Share and quick
  cover's Share record it as soon as the temporary file is written, before
  any share sheet opens (`Selecting.swift:110-117`, `AppTabs.swift:163-171`),
  so a cancelled share still earns the shield. Nothing checks the written
  copy.

**Other progress displays in the app.** None is part of the home screen's
protection work; R11 keeps them unless the owner says otherwise (C25).

| Where | What | Kind |
|---|---|---|
| `Selecting.swift:217` | the batch (the legacy bar) | linear, real counts |
| `EditorParts.swift:428` | Details: places checked of those to check | linear, real counts |
| `PreparingView.swift:60` | Settings › Faster picture processing: photos prepared | linear, real counts |
| `FirstRunExperience.swift:1224-1240` | the first run's story bars | linear, a story clock by design |
| `EditorParts.swift:225`, `ProtectView.swift:239` | Protect Picture's status and loading | small spinner |
| `iOS/Share/ShareViewController.swift:189-190, 212` | the share extension | large spinner, then a small one |
| `ScanTab.swift:98`, `SendToApps.swift:233,327` | scan and app hand-over buttons | small spinner in a button |
| `ExplainSheet.swift:164, 271` | Explain: waiting for the copy, asking the assistant | spinner with words |
| `AssistantSettings.swift:158` | checking the assistant's key | spinner with words |
| `PhoneSync.swift:109, 366` | fetching from iCloud; pairing and syncing steps | spinner with words |

## 3. The covering pipeline, its stages, and where events can come from

A screenshot covered in a batch goes through these steps:

1. `BatchCover.copy(of:)` waits while the app is not in front, then
   remembers the interruption count (`Selecting.swift:129-142`).
2. `BatchCover.covered` calls `Library.image(of:)`, then
   `Covering.cover` (`Selecting.swift:146-149`).
3. `Covering.cover` calls `CoveredCopy.make` (`Covering.swift:39-41`), which
   runs everything below in one block on a global queue
   (`CoveredCopy.swift:17-37`).
4. The PNG is encoded off the main thread (`Selecting.swift:148`).
5. The PNG is saved to Photos or written for the share sheet
   (`Selecting.swift:95-116`).

| Spec phase | What runs today | Where | Where an event can come from |
|---|---|---|---|
| preparing | PhotoKit returns the picture's data, downloading it from iCloud if needed (`isNetworkAccessAllowed = true`, no progress handler, no timeout); ImageIO turns it upright and caps it at 4096 px | `Library.swift:40-50`, `CoveredCopy.swift:43-59` | before and after `Library.image(of:)` in `BatchCover.covered` |
| recognizingText | barcodes and QR codes (`Timing` step "codes"), the text (Vision `VNRecognizeTextRequest`, blocks read again, small print read again side by side; step "read"), faces (step "faces") | `PrivateText.swift:520, 874, 527, 1422-1449, 1535` | read the text first with `Finder.lines(in:)` and hand it to `Finder.remember(_:for:)` (`PrivateText.swift:1389-1408`); `analysis` then reuses it, as Protect Picture does with a prepared photo (`PhotoIndexer.swift:313-318`) |
| classifying | patterns, labels, names and roles (`DocumentSense`), own rules (step "find"); Apple Intelligence or the assistant (step "intelligence") | `PrivateText.swift:876-882`, `Protection.swift:92-131` | around `Finder.analysis` (`PrivateText.swift:515-538`). Codes and faces are found inside `analysis`, so they fall in this phase unless they are also read first |
| redacting | the covers drawn (step "cover"), then the copy read again and whatever still shows covered too, at most two rounds (step "check") | `PrivateText.swift:634-650, 657-702` | around `Finder.finish` |
| verifying | an in-memory check that the covers changed what showed (`coversHold`, on a copy at most 1200 px on its longer side, about 550 px wide for a portrait screenshot); a look that let something through is drawn again in ink; the PNG is encoded | `ExportCheck.swift:10-45`, `CoveredCopy.swift:26-35, 62-68` | after `finish`; Run 2 adds the check on the written file |

- `Finder.protect` is only `analysis` followed by `finish`
  (`PrivateText.swift:615-631`). Protect Picture already calls the two
  apart (`ProtectSession.swift:144-146, 317-327`). So `CoveredCopy` can
  emit each phase by calling the same public functions in turn, with no
  change to the engine.
- The engine has no fraction for one picture: each phase is one call. R9's
  `wholeImageFraction` is therefore always nil, and the ring moves only
  when a picture finishes.
- `Timing` already marks every step above as an `OSSignposter` interval
  (`Timing.swift:8, 33-44`). The phase events can sit at the same points.

## 4. Reading text, and AI

- **Reading.**
  - Vision text recognition, with blocks read again and up to 12 lines of
    small print (under 20 px, holding a digit, "@" or ":") read again,
    enlarged, side by side (`PrivateText.swift:1356-1359, 1422-1449`).
  - Readings are kept by a fingerprint of the pixels (`Readings`), so a
    picture is read once. They are forgotten when the app goes to the
    background (`ContentView.swift:81-84`) and when a batch copy is made
    again (`Selecting.swift:140`).
- **Failures.**
  - A reading, face search or code search that Vision could not do is
    counted (`Finder.failures`, `PrivateText.swift:1375-1383`, used at
    `:749, :846, :1426`) and never kept.
  - `CoveredCopy.make` refuses a copy made while the count moved
    (`CoveredCopy.swift:19-25`). The count is for the whole process (C6).
- **Coordinates.** Vision's normalized boxes, origin bottom left, are
  turned into pixels with `VNImageRectForNormalizedRect`
  (`PrivateText.swift:561`) and in `cover` (`CoverLook.swift:130-136`).
  Orientation is applied before Vision sees the picture
  (`CoveredCopy.swift:43-59`), so Vision always reads it upright.
- **Apple Intelligence.**
  - It runs where it is available and turned on, and only for the kinds
    chosen that it can name (`Protection.swift:19-40, 50-63`).
  - It reads 60 lines at a time, up to 180, at temperature 0
    (`:204-225`), and the main thread never waits for it.
  - A picture waits at most **20 seconds** for it on a semaphore (`:128`);
    the cloud assistant gets **45 seconds** (`:115`). Answers are kept for
    300 sets of lines (`:230-247`).
  - It only adds places, and only words found in their line (`:70-82`).
  - When it does not answer, nothing says so: the patterns' copy goes out as
    if complete (C5, D5).
- **Reading the copy again.** `stillReadable` reads the covered copy and
  covers what still shows (`PrivateText.swift:657-702`). It is part of
  covering and never taken as proof, which agrees with R2.

## 5. Cover looks (redaction styles)

The setting is `CoverStyle.current` (`CoverLook.swift:9-49`), Ink by
default, picked in Settings with samples drawn by the same code
(`SettingsView.swift:58-72`).

| Look | How it is drawn | Opaque | Takes anything from what it covers |
|---|---|---|---|
| Ink | a fill of white 12% (`#1F1F1F`), corners rounded up to 8 px (`CoverLook.swift:255-268`) | yes | no |
| Labelled | the ink, with the kind's word in white at 92% (`:270-305`) | yes; the word is drawn on the ink | no |
| Blur | the colours just outside the place, carried across it, with soft spots and grain from a generator seeded by the place's position and size (`:307-373`, `Seeded`, `:666-684`) | yes | no: `Surroundings` reads bands just outside the place and leaves out every other covered place (`:533-583`), except shapes drawn by hand (D14) |
| Pixels | tiles in the colours around, shaded by the same generator (`:375-408`) | yes | no, as for Blur |
| Dots | the colours around, with a row of dots (`:410-430`) | yes | no, as for Blur |
| Erased | the colours around, carried across (`:307-317`) | yes | no, as for Blur |

- **Evidence.**
  - The code: the soft looks take their colours only from bands just
    outside the place (`Surroundings`), and their randomness only from the
    place's geometry (`Seeded`).
  - The test: `CoverLookTests.testEveryLookHidesForGood`
    (`Tests/TendederoTests/CoverLookTests.swift:14-25`) covers, in every
    look, two pages that differ only under the cover, and requires
    identical pixels. It runs in `swift test` in the Build Snapfly
    workflow, which passed on `f4abfc9`.
  - What the test leaves out: it is one case, a plain white page with one
    line covered. It does not try faces and codes (whose bands are also
    read at the sides, `CoverLook.swift:149, 560-570`), patterned
    backgrounds, places side by side, or shapes drawn by hand. Run 2's check
    on each picture (C1) covers what the test does not.
- **What Settings tells the owner.** "Every look hides for good: blur,
  pixels, dots and erased are drawn from the colors around what is covered,
  never from it, so it cannot be brought back." (`SettingsView.swift:71`)
- **Ink fallback.** A copy whose covers do not pass `coversHold` is drawn
  again in ink (`CoveredCopy.swift:30-35`, `ProtectSession.swift:324-326`).
  The owner's look can therefore be replaced silently, against R4 (C3).
- **Rounded corners.**
  - Every look is clipped to a rounded rectangle, with a radius of at most
    8 px or a quarter of the place's height. The rectangle's corners lie
    outside the drawn path.
  - **Text.** The found box stays inside thanks to the vertical margin (20%
    of the text's height). Where `room` takes that margin away, a corner of
    the box can sit a fraction of a pixel outside the path, in the
    antialiased edge. This only happens to text under about 23 px, where the
    radius is under 8 px.
  - **Faces.** Faces have a margin of 20% across and 30% up and down
    (`PrivateText.swift:849-852`), which keeps the face box inside, except
    where the picture's edge cuts that margin off.

## 6. Detection settings

| Setting | Default | Where |
|---|---|---|
| Kinds to cover (20 kinds, with Check All, Recommended, Uncheck All); Names, or only patients' or other people's names | the recommended kinds | `SettingsView.swift:24-56`, `Covering.swift:8-33`, `PrivateText.swift:543-556` |
| Cover look | Ink | `CoverLook.swift:36-40` |
| Keep the last four digits | off | `CoverLook.swift:81-87` |
| Strongest protection: whole lines, wider margins | off | `Protection.swift:10-13`, `PrivateText.swift:558-571` |
| Find more with Apple Intelligence | on where available | `Protection.swift:19-22` |
| The AI assistant finds private details (cloud) | off | `Protection.swift:27-29` |
| Also hide (own rules: words, or what follows a label) | none | `SettingsView.swift:239-250`, `OwnRules` |
| Faster picture processing (readings prepared ahead, 60 days) | off | `PreparingView.swift`, `PhotoIndexer.swift` |

The share extension reads the same choice, look and rules through
`SharedChoice` (`Covering.swift:27-32`).

## 7. Review and detail flow

- **Protect Picture** (`ProtectView`, `ProtectSession`) opens from a card,
  a photo picked, or a scanned page.
  - It covers in steps: what the patterns find, then the copy, then what
    Apple Intelligence adds (`ProtectSession.swift:114-170`).
  - It marks places "to check" (`Area.check`, covered though unsure;
    `PrivateText.swift:469-471`). It lists unsure places left uncovered
    (`possible`) and kinds left visible (`spared`).
- **Details** is `ReviewSheet` (`EditorParts.swift:373-433`): places to
  check one by one, and topics with switches.
- **Leaving with places to check.** The owner is asked "%d places still to
  check", with Check Now and Continue Anyway (`ProtectView.swift:138-146`).
  `decide` marks places checked without changing the copy
  (`ProtectSession.swift:186-190`).
- **Opening again.**
  - A screenshot or a picture gets a new `ProtectSession` each time it opens
    (`ProtectSession.swift:66-71`). It covers from the start, reusing a
    reading still kept in memory (`PrivateText.swift:1424`).
  - A scanned page keeps its session while the app runs
    (`ScanTab.swift:205-210`), and `start()` runs once
    (`ProtectSession.swift:94-97`). So it opens as it was left, and a copy
    made with a failed reading (D1) stays with the page.
  - R8's "a new attempt with full re-verification" therefore needs the
    file verifier on every way out, not a new session (C19).
- **A batch does not show doubt.** It saves copies with places to check,
  and leaves unsure places uncovered without saying so (C4).

## 8. Ways out (export and share)

Every way out takes a freshly encoded PNG of the covered copy. None passes
the original's data or file.

| Way out | From | What leaves | Where the file is | Deleted |
|---|---|---|---|---|
| Save Covered Copies | the choice's bar | a new Photos asset per screenshot | Photos (`Covering.swift:58-62`) | — |
| Share (several) | the choice's bar | PNGs `tmp/Snapfly n.png`, complete file protection (`Selecting.swift:106-115`) | tmp | on any completion of the sheet (`:190-192`): D2 |
| Cover and Copy / Share / Save | a card's menu (quick cover) | the clipboard; `tmp/Snapfly.png`, a fixed name (`AppTabs.swift:161`); or Photos | tmp | on any completion (`AppTabs.swift:67-69`): D2, D6 |
| Copy, Share, Photos, Files, Mac, an app | Protect Picture | `session.png` (`ProtectView.swift:557-616`); Share and apps through `Handoff`, `tmp/Handoff/<UUID>/` with complete file protection (`SendToApps.swift:57-145`) | tmp | Handoff: only when the sheet is done, or 30 s after the WhatsApp menu |
| Share PDF, send to an app | the Scan tab | a PDF of JPEG pages (quality 0.82, no text layer, creator "Snapfly"; `ScanPDF.swift:19-74`), or PNGs through `Handoff` (`ScanTab.swift:219-268`) | tmp | the PDF on any completion: D2 |
| Copy, Share, Save | the share extension | PNG; `tmp/Snapfly.png` (`ShareViewController.swift:77-106`) | the extension's tmp | on Done only; Cancel leaves it (`:108-115`): D6 |
| Cover the Latest Screenshot, Cover Private Details | Shortcuts and Back Tap | the clipboard and an `IntentFile` PNG (`Intents.swift:14-61`) | — | — |

- **Metadata.**
  - The PNG is encoded afresh with no properties (`CoveredCopy.swift:62-68`),
    so no EXIF, GPS, TIFF or IPTC is copied over. The colour profile stays.
    **Not verified** on a written file: Run 2 adds a test that reads one back.
  - The PDF's Info dictionary may also get a producer and dates from Quartz.
    **Not verified**.
- **The SHA-256 re-check before a share sheet (R6)** exists nowhere yet.

## 9. Photos saving

- **Always a new asset, never an edit.**
  `PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)`
  (`Covering.swift:58-62`, `ShareViewController.swift:86-89`). There is no
  `PHAssetChangeRequest`, no content-editing output and no deletion anywhere
  in the app or the extension (`grep` in "Evidence"). R5 holds today.
- **The new asset's identifier is not kept.** The creation request's
  placeholder is not read, so nothing links the copy to its source or lets
  it be found again (R7).
- **Whether the written resource comes back byte-identical is not
  verified.** It needs Photos, which we only have in the simulator and on
  the owner's iPhone. Run 2 or Run 4 checks it with a debug-only round trip:
  1. Save a known PNG.
  2. Fetch its `.photo` `PHAssetResource`.
  3. Read it with `PHAssetResourceManager.requestData`.
  4. Compare SHA-256.

  If the bytes differ, the manifest keeps a hash of the decoded pixels
  instead, and the report says so.

## 10. Cancellation, background and state

- **Stop.**
  - `BatchCover.stop()` sets a flag (`Selecting.swift:53-55`). The flag is
    read before each screenshot (`:79-82`) and while waiting (`:131-134`).
  - The screenshot in hand runs to its end, including PhotoKit's download
    (no request id is kept) and up to 20 s or 45 s of AI.
  - The run is an unstructured `Task` made in the view
    (`ContentView.swift:144-149`, `HomeParts.swift:658-663`). Nothing cancels
    it, so the `Task.isCancelled` checks never fire.
  - Stop is a text button with no 44 pt target (`Selecting.swift:220-221`).
- **Leaving the app.** Decided in #184 for safety, because iOS may keep
  Vision from reading in the background:
  - covering waits while the app is not in front (`Selecting.swift:129-134`);
  - a copy whose covering overlapped `willResignActive` is made again from
    a fresh reading (`:45-50, 135-141`);
  - nothing asks iOS for background time;
  - the only background work is the indexer's `BGProcessingTask`, while
    charging (`Info.plist`, `PhotoIndexer.swift:323-355`).
- **Load.**
  - The indexer is held during a batch and while Protect Picture is open
    (`Selecting.swift:67-71`, `ProtectView.swift:166, 172`).
  - It already waits in Low Power Mode, when the iPhone is hot (serious or
    critical) and when memory is short (`PhotoIndexer.swift:182-187`).
  - The batch covers one screenshot at a time.
- **State.**
  - `BatchCover` is a `@MainActor` singleton with `progress`, `outcome` and
    `sharing` (`Selecting.swift:15-25`). Views read `running` from it.
  - The run hands back the screenshots that failed or were not reached, to
    stay chosen (`:121-123`; `ContentView.swift:144-149`).
  - Quick cover is a separate `@MainActor` singleton with its own floating
    note, shown for up to 60 s while it covers (`AppTabs.swift:137-139`).

## 11. Restoration today

- `Recent` keeps the last twelve source identifiers in `UserDefaults`
  (`ProtectSession.swift:396-405`). Nothing records an attempt, its outcome,
  its output or its settings.
- The indexer's store (`IndexStore`, `PrivacyIndex`) keeps prepared
  readings, with the owner's consent. It holds text, so it cannot be the
  manifest.
- `Finder.lookKey` (`CoverLook.swift:110-113`) already fingerprints the look,
  keep-last-four, strongest and AI switches. The chosen kinds, own rules and
  engine version are not in it.

## 12. Logging and instrumentation

- **Logging.** One `Logger` ("de.ghazarian.Snapfly", "line") is used for
  everything (`Shared/Log.swift`). Lines about covering carry milliseconds
  and step names only (`Timing.swift:55-62`, `ProtectSession.swift:134, 152`).
  One line logs `String(describing: error)` in public for the AI assistant
  (`Protection.swift:195`); `AIError.other(reason)` can carry the provider's
  message (D9).
- **Signposts.** `OSSignposter` "Protection" marks each step as an interval
  (`Timing.swift:8, 33-44`).
- **Measurements.**
  - Settings shows the last covering's time. It is set by every
    `Finder.protect` call, batches included (`PrivateText.swift:617-618`,
    `Timing.swift:55-62`).
  - Over the last 50 pictures, Settings shows the median and 95th
    percentile until a picture shows and until its copy is ready. Only
    Protect Picture records these (`ProtectSession.swift:122, 132, 155`;
    `Timing.swift:66-93`; `SettingsView.swift:84-96`).
  - Nothing measures a batch as a whole, memory, hitches or hangs yet.

## 13. Deployment target and the APIs the spec needs

| API | Needs | Status on iOS 17 |
|---|---|---|
| `TimelineView`, `confirmationDialog`, `sensoryFeedback`, `contentTransition(.numericText())` | iOS 15–17 | available |
| `AccessibilityNotification.Announcement`, `accessibilityDifferentiateWithoutColor`, `colorSchemeContrast`, `accessibilityReduceMotion` | iOS 13–17 | available |
| `UIApplication.beginBackgroundTask(withName:expirationHandler:)` | iOS 4 | available |
| `BGContinuedProcessingTask` | iOS 26 | **above the target**: may only be proposed (spec section 7), so not a blocker |
| CryptoKit `SHA256` | iOS 13 | available. Not on Linux: Shared code gates it with `#if canImport(CryptoKit)`, with no new dependency |
| ImageIO decode and properties; `PHAssetResourceManager`; PDFKit text extraction | iOS 4–11 | available |
| `OSSignposter` | iOS 15 | available, in use |
| FoundationModels | iOS 26 | already gated at runtime (`Protection.swift:32-40`) |
| MetricKit hitches and hangs, XCTest `XCTOSSignpostMetric`, `XCTMemoryMetric` | iOS 14 | available; needs a test target (C22) |
| `ProcessInfo.isLowPowerModeEnabled`, `thermalState` | iOS 9–11 | available, in use |

## 14. Existing defects

| # | Severity | Defect | Evidence | Proposed fix |
|---|---|---|---|---|
| D1 | **high** (privacy) | Protect Picture does not fail closed. If Vision cannot read the picture, as when the app goes away while the editor's work goes on, it finds nothing, makes a "ready" copy that is the picture as it was, and lets it leave by every way out. Scans opened in the editor take that copy into PDFs and app hand-overs. One partial safeguard: `finish` reads the copy again (`PrivateText.swift:640-649, 662`), so if Vision works again by then, text the patterns find is covered; faces, codes and what AI finds are not. | `ProtectSession.swift:144-146, 310-342` never reads `Finder.failures`, unlike `CoveredCopy.swift:19-25`; `ScanTab.swift:275-279` | Run 2: per-attempt failure tracking, and a failed reading means `.failed`, never ready |
| D2 | medium | The share sheets of the batch, quick cover and the Scan tab's PDF delete their files on any completion. When an app's own sheet is cancelled, the share sheet stays up without its files (iOS behaviour, **not verified** here; it is why `Handoff` was changed in #186). | `Selecting.swift:190-192`; `AppTabs.swift:67-69` with `ProtectView.swift:646` | Run 2 or 3: delete only when `completed` or when the sheet closes (`activity == nil`), as `SendToApps.swift:74` does |
| D3 | medium (truthfulness) | Green success marks without verification. A card's shield comes from `Recent`, set when a copy left, and for Share as soon as the file is written, so a cancelled share still earns it. The share extension shows a green shield with "Nothing private found". | `HomeParts.swift:315-324`; `Selecting.swift:110-117`; `AppTabs.swift:163-171`; `ShareViewController.swift:204-207` | Run 3: badges only from verified attempts; nothing found is neutral |
| D4 | medium (recall) | A 13–19 digit run that fails the Luhn check is not covered as a card number. It is covered only if a label (as "Kartennummer") or another pattern (as a 12-, 14- or 20-digit tracking number) catches it. | `PrivateText.swift:1665-1666, 2319`; `:382-384`; `:1708` | Run 2: the recall rule (C7) |
| D5 | medium | When Apple Intelligence or the assistant does not answer in time, or fails, nothing is recorded, and the copy goes out as complete. | `Protection.swift:115, 128, 195-196, 220-221` | Run 2: `.needsReview` (C5) |
| D6 | low | Fixed temporary names. A second quick share overwrites the first one's file under its open sheet. The extension's Cancel leaves its copy in tmp. | `AppTabs.swift:161`; `ShareViewController.swift:99, 108-115` | Run 2: a folder per attempt, as `Handoff` does |
| D7 | low | A face or text box at the picture's edge, or text whose vertical margin `room` took away, can leave a sliver, at most a pixel, outside the rounded cover (section 5). | `PrivateText.swift:558-571, 849-852`; `CoverLook.swift:255-268` | Run 2: the verifier checks the drawn path against the found box, and covers that touch the picture's edge get square corners there |
| D8 | low | `Finder.failures` counts for the whole process. A failure in one picture fails any other covered at the same moment, as quick cover from another tab during a batch. This is safe but spurious, and it rules out concurrency 2 as it stands. | `PrivateText.swift:1375-1383`; `CoveredCopy.swift:19-25` | Run 2: per-attempt tracking (C6) |
| D9 | low (R10) | The assistant's error is logged in public with its provider message. | `Protection.swift:195` | Run 2: log the case alone |
| D10 | low (performance) | PNG encoding on the main thread in quick cover, Protect Picture and the extension, about 50–150 ms for a full screenshot (**not measured**). | `AppTabs.swift:144`, `ProtectSession.swift:340`, `ShareViewController.swift:60` | Run 4, measured first |
| D11 | info | Stop has no 44 pt target. | `Selecting.swift:220-221` | Run 3 (section 4 row 6) |
| D12 | info | The final check works on a copy at most 1200 px on its longer side (about 550 px wide for a portrait screenshot) and passes when half of what showed changed. It is weaker than R2, though it keeps the app's own promise. | `ExportCheck.swift:14, 42` | Run 2: the file verifier; `coversHold` stays as an early check |
| D13 | medium (covers too much) | On an English invoice, the lines under "BILL TO" run on into the big title and the table. "Invoice", "DESCRIPTION", "Logo design" and "Business cards, 250 pcs" are covered as the address, and the label itself and the company's name in the header are covered and marked to check: 9 found and 2 to check, where German finds 3. "BILL TO" announces a block of up to six lines, and the next line is taken when the gap is under 1.1 times the taller of the two lines, so a large title qualifies. Nothing leaks, but English invoices come out heavily covered, on the Mac too. | CI capture `editor-en-light.png` on `f4abfc9` (First Run Captures, `first-run-captures` release); `PrivateText.swift:312, 329-333, 1882-1890, 1954-1964` | An engine fix with a `RedactionTests` case: end the block at a line much taller than its own lines (a heading) and at a table's header row; never fitted to this one page |
| D14 | low | Shapes drawn by hand are left out of the places the soft looks avoid, so blur, pixels, dots or erased beside a hand-drawn shape can average colours from under it. Only colours are taken, never the text, and only in Protect Picture. | `CoverLook.swift:130-149` (shapes filtered out before `rects`) | Run 2: count hand-drawn shapes among the places to avoid |

## 15. Features that must keep working

Run 2, 3 and 4 must leave each of these as it is, unless the owner approves
a change. Each run's report ticks them.

- **Home and gallery.**
  - The Photos tab: title, sync chip, picture of stacked photos, Protect a
    Photo, From Mac row, three rows of the newest screenshots, See All.
  - The grid: three or four to a row by pinch, or by See All's menu.
    Rising cards; zoom into Protect Picture (iOS 18); the guide's first-shot
    target.
  - Choosing: Select, a tap, a sideways sweep (iOS 18), Select All and
    Deselect All, Cancel. Failed ones stay chosen. The tab bar steps aside.
  - Save Covered Copies (n) to Photos; Share several; Stop; outcome texts
    and hints.
  - A card's menu: Cover and Copy, Cover and Share, Cover and Save.
  - See All: search by words read ahead of time; show all, with private
    details, protected, not protected; newest or oldest; per row.
  - The Protected tab: the last twelve, opened again or covered from their
    menu.
- **Protect Picture.** Find, cover, check; tap to cover a word; marker,
  box, lasso and eraser; undo and redo; Details and places to check; Don't
  Wait for Apple Intelligence; Explain (AI); Full Screen; the apps beside the
  page; Copy, Share, Photos, Files, Mac, apps; Send to Apps settings; Clear
  Hidden by Hand; Reset to Suggestions.
- **Scan.** The document camera, pages, a page opened in Protect Picture,
  Share PDF, send to an app.
- **Elsewhere.** The share extension (Copy, Share, Save, as chosen in the
  app). Shortcuts and Back Tap (Cover the Latest Screenshot, Cover Private
  Details). Sync with the Mac (from the Mac, send to the Mac, pairing). The
  first run. Faster picture processing in the background while charging.
- **Settings.** Every row in section 6, the AI Assistant, Send to Apps,
  Also hide, Back Tap, Help and Introduction, and the timings shown.
- **The Mac.** It shares the engine (`Sources/Tendedero/Shared`), so every
  engine change in Run 2 also runs the Mac's tests (`RedactionTests` and the
  rest).

## 16. Section 4, row by row

| Row | Here | Resolution |
|---|---|---|
| Several redaction styles → `.obscured` | Six looks, all opaque, none taking a pixel of what it covers by their code (section 5) | The spec's reason for `.obscured` does not apply. Recommended: every look can earn `.protected` once verified, with a check per picture that the cover's pixels don't depend on what is under it (C1). `.obscured` stays in the model, unused, unless the owner chooses the strict reading. |
| A review/detail flow → the panel and badges open it | Yes: Protect Picture with Details (section 7) | The panel opens the first picture needing review; a badge opens its picture, as a card tap does now. While choosing, a tap toggles the card, so review is in the card's menu (spec section 11). |
| PDF export → the PDF rule | Yes, in the Scan tab only: JPEG pages, no text layer (`ScanPDF.swift`) | Pages are already flattened. Run 2 adds the check: no text extractable (PDFKit `string` empty), each page's covers checked in its decoded image within the codec's tolerance, and the SHA-256 of the file. The Info dictionary is checked on macOS CI. |
| Photos saving → the Photos rules | Yes: a new asset, never an edit (section 9) | Keep the new asset's identifier, re-read and hash its resource, and record it in the manifest. Byte identity is **not verified** (section 9). |
| An app-container copy → share from it, else from Photos after a hash check | No lasting copy: temp files only (section 8) | Within a run, share the verified temp file after re-checking its hash. After a restart, share from Photos after hashing the resource (R6, R7). A lasting copy in the app's container is not proposed: it would keep covered copies the owner did not ask to keep. |
| A visible cancel button → keep a compact 44 pt one | Yes: Stop (`Selecting.swift:220-221`) | Keep Stop in the panel at 44 pt; it asks "Schutz abbrechen?" with "Vorgang abbrechen" and "Fortfahren" first (C13). |
| Apple Intelligence → check at runtime | Yes (section 4) | Already checked at runtime. Run 2 adds when it did not answer (C5). |
| Checksum validators → the recall rule | Luhn for card numbers (a failure is not covered as a card); IBANs by shape and length, no mod-97 check | A Luhn failure is covered and marked to check (`Area.check`), so the picture ends `.needsReview` (C7). IBANs stay as they are, which already favours recall. |

## 17. Conflicts between the spec and the codebase

Decisions: **owner** means the owner chooses, and the recommended option
applies if they say go on. **default** means Run 2 or 3 follows the proposal
and logs it, as the spec allows for its defaults.

| # | The spec | The codebase | Proposed solution | Decision |
|---|---|---|---|---|
| C1 | R4: blur and pixelation give `.obscured`; R2: `.protected` needs opaque pixels not derived from the original; section 9's note says blur and pixelation can be undone | All six looks are opaque and, by their code, independent of what they cover (one case tested, section 5); the soft looks take colours from just outside the place; Settings promises they can't be brought back | `.protected` means "not derived from the pixels of any covered place". The verifier draws each picture's covers a second time over a copy whose places are blanked, and requires identical cover pixels. Every look can then earn `.protected`. The reversibility note is left out, because it would be false here. | **owner** (recommended as proposed) |
| C2 | R2: every detected region covered | Settings leave parts visible on purpose: the last four digits, kinds not chosen, other people's names, unsure places left uncovered | `.protected` means every place the current settings say to cover is covered and verified. Unsure places left uncovered give `.needsReview` (C4). No text claims more (R2). | default |
| C3 | R4: never silently replace the chosen style | A copy that fails `coversHold` is drawn again in ink | Keep the ink fallback, because an uncovered copy is worse. It becomes `.needsReview(.lookReplaced)` with the note "covered in ink instead", not silent. | default |
| C4 | R3: any low-confidence candidate gives `.needsReview` | The batch saves copies with places to check (`Area.check`) and leaves unsure places (`possible`) uncovered, unannounced | Either gives `.needsReview(.uncertainPlaces(n))`. The copy is still written and kept. Opening it lands on Details with the places to check. | default |
| C5 | R3: an inconclusive check gives `.needsReview` | An AI that did not answer is silent | When AI was on and asked, and gave no answer for this picture, the result is `.needsReview(.intelligenceDidNotAnswer)`. That needs a per-attempt signal from `intelligentPieces`. | default |
| C6 | R3: no valid output gives `.failed`; section 13: concurrency 2 | `Finder.failures` is process-wide (D8); the editor ignores it (D1) | Track failures per attempt: a token or task-local counter set around each attempt's calls, in place of the global count (read today only by `CoveredCopy` and `ProtectionTests`). A failed reading means `.failed(.couldNotRead)`. | default |
| C7 | Section 6: a checksum failure is covered and flagged `.needsReview` | Luhn failures are not covered as card numbers (D4) | Cover them, with `check = true`. `RedactionTests` gain a case. The Mac changes too: its copies cover such numbers, marked to check. | default (engine change, Mac included) |
| C8 | Section 6: pad each region by at least 15% of its height and at least 2 px | 25% across and 20% up (45% and 35% with strongest), but the vertical margin may shrink to nothing so as not to hide the line above or below (`room`); no 2 px floor | Keep `room`, an existing deliberate rule, and log the deviation. The found box stays inside the cover, which the verifier checks geometrically. Add the 2 px floor where room allows. | default |
| C9 | Section 6: opaque fill, alpha 1, checked per pixel | Rounded covers with antialiased corners; a sliver at most a pixel wide can lie outside at the picture's edge or where `room` took a margin away (D7) | The verifier checks the drawn path, not the padded rectangle, and checks each found box geometrically inside it, pixel centre by pixel centre. Covers that touch the picture's edge get square corners there. | default |
| C10 | Section 7: request background time; at expiry mark unfinished images `.interrupted` | #184: covering waits while the app is away, and a copy overlapping `willResignActive` is made again | Request background time only to finish writing and saving outputs already verified, and the manifest. Never start or trust a covering in the background. Back before expiry, the run goes on by itself (as now). At expiry, unfinished images are `.interrupted`: "Vorgang unterbrochen / Tippe, um fortzufahren." | **owner** (recommended as proposed) |
| C11 | Section 13: concurrency 2 (1 in Low Power Mode or a serious thermal state) | One at a time; AI may hold a picture for 20 s; global failure count | After C6, two at a time, one in Low Power Mode or when serious or critical (as `PhotoIndexer` checks). Run 4 measures memory and hitches on the simulator; the owner's iPhone is **not verified**. Fall back to 1 if needed, and log it. | default |
| C12 | Section 8: a bottom overlay; the gallery's frame never changes | `SelectionBar` sits in a safe-area inset and swaps its content for progress | The panel is an overlay above the bottom. The bar's inset does not change when a run starts or ends: its buttons only turn off. The legacy bar and its label go. | default |
| C13 | Section 8: a tap while running asks to cancel; section 4: keep a visible 44 pt cancel | Stop takes effect after the screenshot in hand, without asking; it is a text button | Stop, 44 pt, in the panel. It and a tap on the panel both open the spec's dialog. A cancel while a picture is in hand keeps that picture's outcome if its verification finished (spec section 5). | default |
| C14 | R1, section 9: "geschützt" only for `.protected`; no success mark before verification | "Protected" names a tab, a filter, a card label and the green shield, all from `Recent` (D3) | Badges and the panel use only the attempts' outcomes. The green shield from `Recent` goes. The tab and filter keep their names and lists, because they are features (R11). Whether to rename them is the owner's call. | **owner** (low; recommended: keep names) |
| C15 | Section 9: German copy with plural variants | 13 languages, literal English keys, singular and plural as separate keys ("1 …" and "%d …"), no `.stringsdict`; German uses "du" and a space before "…" | English keys, German as given (it already fits "du" and the space before "…"), and the other 11 languages translated. Plurals follow the codebase's pattern. Languages with more plural forms, as Arabic, get the same approximation the app already uses. | default |
| C16 | Section 15: tokens #111318, #6E737B, #078760, #07976B, #E9F8F1, dark near #34C38F; a `SnapflyMotion` enum | DESIGN.md wins: `phone-protect` #07875C, `phone-protect-light` #12A572, `phone-surface` #EAF7F0, `phone-protect-tint` (#12A572 at night); text uses the system's `.primary` and `.secondary`; `SnapflyMotion` already exists (`Motion.swift:6-42`) | Map the spec's emerald to `phone-protect` and its soft green to `phone-surface`. Keep system text colours, which follow dark mode and Increase Contrast. Extend `SnapflyMotion` with the new values. New values (the panel's radius 20, shadow, border, ring sizes, track, durations) go into DESIGN.md and MOTION_SYSTEM.md in the same pull request. | default |
| C17 | Section 13: thumbnails downsampled with ImageIO | PhotoKit's caching image manager makes them at 360 pt and never decodes the whole picture | Keep PhotoKit, the right tool for Photos assets, and log the deviation. ImageIO is used where we hold data, for the manifest's re-check. | default |
| C18 | R6: only the verified output, its SHA-256 checked just before the share sheet | No hash anywhere; five different share sheets | One path for every share sheet of a run: write, hash, compare, present. It covers the batch, quick cover, Protect Picture and `Handoff`. The Scan PDF and the extension follow if the owner agrees (scope). | **owner** (scope; recommended: all) |
| C19 | R8: review, correction and retry make a new attempt with full re-verification | Protect Picture's copies are checked in memory only; `decide` checks places without a new copy | A copy that leaves Protect Picture goes through the same file verifier. The result is recorded as a new attempt, linked to the one that needed review. Confirming alone changes nothing (R8). | **owner** (with C18) |
| C20 | R7: restore only when source version, settings fingerprint and output hash match | Only `Recent` ids | A manifest per attempt (section 19). Source version: the asset's modification date and the pixel fingerprint the engine already makes. Settings fingerprint: SHA-256 over the kinds, own rules, look, last four, strongest, AI switches and engine version. Output: the file's SHA-256 and the Photos identifier, re-hashed from Photos at launch. | default |
| C21 | R10: counts and durations only | One public error message (D9) | Fix D9. Signposts already carry step names only. | default |
| C22 | Runs 3 and 4: UI tests, previews of every state, performance tests | No iOS test target; logic is tested with `swift test` on macOS | Shared logic (store, outcome rules, remaining time, copy choice) is tested with XCTest in `Tests/TendederoTests`. A UI test target is added to the hand-written project, with a simulator step in CI; that adds macOS minutes. Previews use `#Preview`, debug-only fixtures. | default (CI minutes noted) |
| C23 | Section 9: "Keine sensiblen Angaben erkannt / Bitte vor dem Teilen selbst prüfen." | The batch counts such a copy as "saved" with a success haptic; the extension shows a green shield | Neutral outcome, no success haptic. The copy is still saved as now, because the owner chose Save. | default |
| C24 | Run 3: delete the legacy bar | Linear bars elsewhere: Details, Faster picture processing, the first run's story | Delete only `SelectionBar`'s bar. The others are not protection progress on the home screen (R11). | default |
| C25 | The panel shows the home screen's work | Quick cover from a card's menu has its own floating note | Quick cover from the home screen and See All becomes a one-picture attempt in the same store, so the panel and the card's badge show it. Its notes (copied, saved) stay. | default |

## 18. Blockers

| Blocker | Hit? | Evidence |
|---|---|---|
| The stages cannot be observed without restructuring the pipeline | **No** | `Finder.protect` is `analysis` then `finish` (`PrivateText.swift:615-631`); both are public, and Protect Picture already calls them apart (`ProtectSession.swift:144-146, 317-327`). The reading can be done first and handed over (`PrivateText.swift:1389-1408`, used at `PhotoIndexer.swift:313-318`). Section 3 names every event point. |
| The output is saved as an edit of the original, or the original reaches the share sheet | **No** | Saving uses `PHAssetCreationRequest` only; there is no `PHAssetChangeRequest` anywhere. Every way out takes the covered PNG (section 8). When nothing is found, the copy is the picture re-encoded without metadata, not the original file. |
| The opaque style does not produce truly opaque output pixels | **No** | Ink fills at alpha 1 (`CoverLook.swift:264-268`) on an opaque screenshot. The cover's straight edges lie on whole pixels (`.integral`, `:133`); only the rounded corners blend, and they lie outside the found box except for the sliver of D7, at most a pixel. Run 2's verifier checks it per pixel on the written file. |
| A required API is above the deployment target with no fallback | **No** | Section 13: only `BGContinuedProcessingTask` (iOS 26), which the spec allows only as a proposal; FoundationModels is already gated at runtime. |

## 19. Proposed shape for Run 2 (names adapted to the codebase)

The spec's names fit: none is taken (`grep` in "Evidence"). The store is
`BatchCover`, the main-actor object the home screen already watches. It is
renamed nowhere.

```swift
// Sources/Tendedero/Shared/ProtectionRun.swift: no UIKit, tested on Linux
// and in swift test.
enum ProtectionPhase { case preparing, recognizingText, classifying, redacting, verifying }

enum ProtectionOutcome: Equatable {
    case protected(redactedRegionCount: Int)
    case obscured(CoverStyle)                 // kept for the strict reading of C1; unused by default
    case noSensitiveDataFound
    case needsReview(ReviewReason)            // the verified covered copy is kept
    case failed(ProtectionFailure)
    case cancelled
    case interrupted
}

enum ReviewReason: Equatable {
    case uncertainPlaces(Int), intelligenceDidNotAnswer, checksumFailed(Int), lookReplaced, verificationDoubt
}

enum ProtectionFailure: Equatable {
    case couldNotLoad, couldNotRead, couldNotCover, verificationFailed, couldNotWrite, couldNotSave, hashMismatch
}

enum ProtectionState: Equatable {          // the spec's ImageProtectionState
    case pending
    case active(ProtectionPhase, wholeImageFraction: Double?)   // always nil here (section 3)
    case finished(ProtectionOutcome)
}

struct ProtectionAttempt: Identifiable, Equatable {
    let id: UUID
    let imageID: String                     // the PHAsset's localIdentifier
    let previousAttemptID: UUID?
    var state: ProtectionState
}

enum ProtectionEvent { case started(UUID), phase(UUID, ProtectionPhase), finished(UUID, ProtectionOutcome) }

/// The run as the panel shows it: counts derived from the attempts, the
/// ring never going back. A pure value, so it is tested without a screen.
struct ProtectionProgress: Equatable {
    private(set) var attempts: [ProtectionAttempt]
    mutating func apply(_ event: ProtectionEvent)
    var ringFraction: Double?               // (finished + Σ fractions) / total, monotonic, nil before a value
}
```

- **Events.** `CoveredCopy` gets a way to make a copy step by step, emitting
  `ProtectionEvent`s into an `AsyncStream`. It calls `Finder.lines(in:)` and
  `remember`, then `analysis`, `finish`, the in-memory check, the PNG, the
  write and the file verifier. `BatchCover` reads the stream on the main
  actor and calls `apply(_:)`.
- **Outcome precedence (R3)**, in this order:
  1. No valid written output gives `.failed`.
  2. Any doubt gives `.needsReview`: unsure places, an AI that did not
     answer, checksum failures, a replaced look, a verifier in doubt.
  3. Otherwise `.protected` when there were places, or
     `.noSensitiveDataFound`.
- **The verifier** (Shared, ImageIO, on macOS and iOS; not on Linux):
  1. Read the written file back.
  2. Decode it at full size.
  3. For each cover: the found box lies inside the drawn path; every pixel
     inside the path equals the expected drawing, ±2 per channel; alpha is
     255.
  4. Draw the covers again over the places blanked; the cover pixels must
     come out identical (C1).
  5. Hash the file with SHA-256.
  6. For Photos: re-read the new asset's resource and compare hashes
     (section 9).
- **The manifest.** One small JSON per attempt, in Application Support,
  with complete file protection, pruned to the last few hundred. It holds no
  pixels and no text: attempt id, previous id, source identifier, source
  version, settings fingerprint, outcome, verified-at, output SHA-256, the
  Photos identifier or the file's name.
- **Run 2's tests.**
  - Linux and `swift test`: the store's reducer, counts and ring;
    outcome precedence; settings fingerprint; Luhn recall.
  - `swift test` on macOS: the verifier against hand-made files, including a
    wrong pixel, a cover moved by one pixel, and a changed byte; PNG
    metadata; the PDF's text and Info dictionary.

## 20. Not verifiable here, and how to check it

| Item | Why not here | How |
|---|---|---|
| Photos returns the saved PNG byte for byte | needs Photos | debug-only round trip in the simulator (section 9); then once on the owner's iPhone with iCloud Photos on |
| Vision with background time | needs a device | on the owner's iPhone: start 20 screenshots, lock the phone, unlock after 10 s and after 60 s; every outcome must be verified or interrupted, none silently passed |
| Two at a time: memory and hitches | needs a device for real numbers | simulator numbers in Run 4, marked as such; the owner's TestFlight build for the rest |
| WhatsApp's `.wai` hand-over and each app's share extension | needs those apps | the owner, through TestFlight |
| The target look | the reference screenshot did not arrive | the owner sends it before Run 3 |

## Evidence

- **Read for this audit** (no files changed): every file named above at
  `f4abfc9`, through `cat -n`, `sed -n` and `grep -n`.
- **Searches, with what they showed:**
  - `grep -rn "PHAssetChangeRequest\|PHContentEditingOutput\|requestContentEditingInput\|deleteAssets\|PHAssetCreationRequest" iOS/ Sources/Tendedero/Shared/`
    shows creation requests only (`Covering.swift:60`,
    `ShareViewController.swift:88`).
  - `grep -n "failures" …` over the app and the engine shows
    `Finder.failures` read only in `CoveredCopy.swift:19, 25`; the tests
    read it in `ProtectionTests`.
  - `grep -rn "ProtectionState\|ProtectionPhase\|ProtectionOutcome\|ProtectionAttempt\|ProtectionEvent\|ProtectionProgress" Sources iOS Tests`
    shows none taken.
  - `grep -n "ProgressView" iOS/Snapfly/*.swift iOS/Share/*.swift` gives the
    table in section 2.
  - `grep -n "IPHONEOS_DEPLOYMENT_TARGET\|SWIFT_VERSION\|TARGETED_DEVICE_FAMILY" iOS/Snapfly.xcodeproj/project.pbxproj`
    gives section 1.
- **CI.** Build Snapfly's `build` and `iphone` jobs passed on `f4abfc9`.
  `build` runs `swift test` (`build.yml:32-33`), including
  `CoverLookTests.testEveryLookHidesForGood`. First Run Captures passed on
  the same commit and made the editor captures used for D13.

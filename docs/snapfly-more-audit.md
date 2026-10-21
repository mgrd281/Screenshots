# Snapfly on the iPhone: the More tab, before Version 2

An audit of the More tab (Mehr) as it shipped in 1.1.0, made before any code
of Version 2 was written. It lists every setting on the page, the key it is
stored under, its default and where the app reads it; maps each to its place
in Version 2; finds out what the floating "…" button is; and checks the
claim the Cover look footer makes. Paths are from the repository root.

The page was one long `Form` in `iOS/Snapfly/SettingsView.swift`, shown as
the More tab (`SettingsView(inTab: true)` in `AppTabs.swift:61`). Nothing
else opens it: `inTab: false` (a sheet with Done) has no caller.

## 1. Every setting on the page

| # | On the page | Stored under | Default | Read by |
|---|---|---|---|---|
| 1 | Hide private details: Check All, Recommended, Uncheck All | `hiddenDetails` (UserDefaults, sorted string array of `PrivateDetail` raw values), through `Choice.details` (`iOS/Snapfly/Covering.swift:18`). The buttons write `Set(PrivateDetail.allCases)` (22), `PrivateDetail.recommended` (13) and `[]` (`SettingsView.swift:33-35`, `choiceButton` at 255). | none: buttons | the same key as row 2 |
| 2 | The 22 kinds in six groups (People 9, Companies and organizations 1, Money 2, Health 1, Documents 6, Passwords and access 3), one switch each (`binding(for:)`, 245) | `hiddenDetails`, as above. Brought up to date once per launch by `PrivateDetail.bringUpToDate` (`PrivateText.swift:131`), which also reads and writes `knownDetails`, `namesParted` and `nameRoles`; `OwnRules.adoptName` runs then too. Setting it calls `Choice.share()`, which copies the choice, the look and the rules to the share extension (`SharedChoice`). | `PrivateDetail.recommended` while the key is absent: names, patientNames, otherPeople, addresses, birthDates, emails, phones, bank, health, ids, codes, keys, barcodes | `AppTabs.swift:145` (quick cover), `Selecting.swift:72`, `Intents.swift:31,56` (Shortcuts and Back Tap), `ScanTab.swift:286`, `ProtectSession.swift:54`; the share extension through `SharedChoice` |
| 3 | Your Name, first under People (`OwnNameRow`, `OwnDetailsSettings.swift:7`), opening `DetailSheet` | the keychain item "Snapfly details" (`OwnDetailStore`, `Shared/OwnRules.swift:280`), kind `.name`, written by `keepName` (`SettingsView.swift:234`) through `OwnRules.all` | none | `Finder` (own details, covered whatever kinds are chosen), Always Hide, the share extension |
| 4 | Cover look: six tiles (`CoverLookPicker`, `Shared/CoverLookPicker.swift`) | `coverStyle` (`CoverStyle.current`, `Shared/CoverLook.swift:38`) | `ink` | `ProtectView.swift:597`, `ProtectSession.swift:56`, `Finder.cover`'s default style, `Finder.lookKey` (`CoverLook.swift:112`), the share extension |
| 5 | Keep the last four digits | `keepLastDigits` (`Finder.keepsLastDigits`, `CoverLook.swift:84`) | off | `PrivateText.swift:720` and `1502`, `Finder.lookKey` |
| 6 | Strongest protection | `strongestCover` (`Finder.strongest`, `Shared/Protection.swift:10`) | off | `PrivateText.swift:594-602` (margins), `958-962` (whole lines), `1196` (text hidden), `720` (it overrides row 5), `Finder.lookKey` |
| 7 | Find more with Apple Intelligence, disabled where it is not available | `intelligenceOff`, inverted (`Finder.usesIntelligence`, `Protection.swift:19`); availability from `SystemLanguageModel` (`Protection.swift:32`) | on, where available | `ProtectSession.swift:89`, `PrivateText.swift:976`, `Finder.lookKey` |
| 8 | Last screenshot (shown once one was covered) | in memory only (`Timing.last`, `Shared/Timing.swift:27`) | none | this page only |
| 9 | Picture shown, Ready to share: "Median … · 95% under …" | `SnapflyTimes.shown`, `SnapflyTimes.ready` (the last 50 times in ms, `Timing.swift:75-82`) | empty: the rows are hidden | this page only |
| 10 | Faster picture processing, On or Off, opening `PreparingView` | `privacyIndex` (`IndexSettings` as JSON: isOn, scope, days, paused, selected; `Shared/PrivacyIndex.swift:143`) | off | `PhotoIndexer.swift`, `PreparingView.swift` |
| 11 | AI Assistant, the assistant's name or Off, opening `AssistantSettings` | `aiProvider`, `aiModel.<provider>`, `aiFindsPrivate`, `aiKeySet.<provider>`; the key itself in the keychain (`Shared/AIAccount.swift`) | Off (no key) | `ExplainSheet.swift`, `EditorParts.swift:302`, `Finder.asksAssistant` (`Protection.swift:27`) |
| 12 | Send to Apps, how many, opening `ChooseApps` | `aiChatOff.<app>` per app, `aiChatsOnPhotosOff` (read once, from before), `chatOrder` (`Shared/Chats.swift:155-192`) | the standard apps on | `SendToApps.swift`, the editor and the scan |
| 13 | Sync: Sync with your Mac, This iPhone, Sync Now, the other devices (`SyncSection`, `PhoneSync.swift:181`), only where the build has an iCloud container | `syncSettings` (`SyncSettings` as JSON: on, originals, originalsSince; `Shared/SyncPolicy.swift:6`), `syncHangSince`, `syncRegistered`, `syncDeviceID` | off | `SyncCenter`, `CloudSync`, `SyncPolicy`, `ContentView.swift:280` |
| 14 | Another Apple account: the Macs joined, Connect to a Mac with a Code, Disconnect (`OtherAccountSection`) | `syncConnections` (`SyncCenter.swift:50`) | none | `SyncCenter` |
| 15 | Advanced › Always Hide (`AlwaysHideView`) | `ownRules` (the rules as JSON) and the keychain details | none | `Finder`, the share extension |
| 16 | Advanced › Double tap the back of your iPhone (`BackTapSettings`) | nothing: three steps of instructions; the App Intent is `Intents.swift` | none | none |
| 17 | Help & Introduction: Start Introduction, Watch the Demo | nothing new: `PhoneGuide.start()`, `FirstRunCoordinator.replay()` (`firstRunSeen` is read at launch only) | none | none |

The texts on the page that are not settings: the People footer (each name
switch covers its own people), the Cover look footer (row 4, checked in
section 4), the Reading and checking footer (every copy is read again before
it leaves), and the AI Assistant and Send to Apps footers.

Nothing on the page is kept anywhere but these keys. Version 2 reads and
writes them through the same accessors (`Choice.details`,
`CoverStyle.current`, `Finder.keepsLastDigits`, `Finder.strongest`,
`Finder.usesIntelligence`, `OwnRules`, `SyncCenter`, `IndexSettings`,
`ChatTarget`, `AIAccount`), so no value is renamed, reset or migrated.

## 2. Where each goes in Version 2

| Now | Version 2 | Rows above |
|---|---|---|
| Hide private details: Check All, Recommended, Uncheck All | What Is Covered: a segmented control Recommended / All / None. It writes what the three buttons wrote (`CoverPreset`), and shows none chosen when the choice is the owner's own. | 1 |
| The six groups of switches | What Is Covered: five groups. People and Companies takes People (9) and Companies and organizations (1); Money, Health, Documents and Access as they were. Each kind a pill. The Mac keeps its six groups (`PrivateDetail.Group` is unchanged); the five are `CoverGroup`. | 2 |
| Your Name under People | Removed there. It stays in Always Hide, where it has always been kept; a card "Your Own Details" at the end of What Is Covered leads there. | 3 |
| Cover look, the two switches | Cover Style: a live preview, the six looks three to a row, the two switches. | 4, 5, 6 |
| Reading and checking: Apple Intelligence, Faster picture processing | Detection | 7, 10 |
| Last screenshot, Picture shown, Ready to share | Detection › Performance on This iPhone: two tiles with the median large and "95% under …" small; the last screenshot under them. | 8, 9 |
| AI Assistant, Send to Apps, Advanced › Double tap the back | More › Features | 11, 12, 16 |
| Sync and Another Apple account | More › Features › Mac and iCloud, one page with the same sections (`SyncSection`), shown where the build has iCloud, as now | 13, 14 |
| Advanced › Always Hide | More › Protection: the tile Always Hide, and the hero's two chips | 15 |
| Help & Introduction | More › Help: Introduction and Watch Demo side by side, then the version | 17 |

Nothing is left out: rows 1 to 17 each have a place. The footers that are
not kept as they were: the AI Assistant and Send to Apps footers (their pages
say what they do in their own sections and footers), and the long People
footer, whose words about the
owner's own name move to the Your Own Details card; the three name switches
are explained under the People and Companies card, by their own subtitles.

## 3. The floating "…" button

It is not a debug or TestFlight tool. It is the iPhone's own tab bar,
minimised. `ContentView` calls `tabBarShrinksOnScroll()` (`AppTabs.swift:65`,
defined at 83), which from iOS 26 sets `tabBarMinimizeBehavior(.onScrollDown)`:
as a page scrolls down, the tab bar shrinks to one round glass button with the
selected tab's symbol, and on the More tab that symbol is `ellipsis.circle`
(`AppTabs.swift:62`), the "…". It floats over the bottom leading corner and
over whatever rows pass under it. Always Hide already hides the tab bar for
this reason (`AlwaysHide.swift:67`, DESIGN.md "Always Hide").

Version 2 keeps the tab bar whole on the More tab (its minimise behaviour is
`.never` while More shows, `.onScrollDown` on the other tabs, as now), and its
pages hide the tab bar as Always Hide does, so the button never covers a row.

## 4. "Every look hides for good"

The Cover look footer says that blur, pixels, dots and erased are drawn from
the colours around what is covered, never from it, so it cannot be brought
back. Checked in code, it holds for all six looks:

- Every look is drawn by one function, `Finder.cover(_:areas:style:)`
  (`Shared/CoverLook.swift:118`). The iPhone's copies come from it through
  `Finder.protect` (`CoveredCopy.swift:20`) and `ProtectSession`; nothing
  else draws a cover: there is no Core Image blur or pixellate anywhere in
  the app (searched for `CIGaussianBlur`, `CIPixellate` and `.blur(radius`:
  only decoration in the first run, the home screen and the Mac's line).
- **Ink** and **Labelled** fill the place with opaque ink, grey 0.12
  (`drawInk`, 264); Labelled writes the kind's word on it (`drawLabel`, 275),
  never the covered words.
- **Blur, Pixels, Dots, Erased** read `Surroundings` (538): bands just outside
  the place, above and below it (and for a face, a code or a part hidden by
  hand, left and right), from the picture as it was, before any cover is
  drawn (the reads are made in one pass first, 147-150). Pixels inside any
  covered place are skipped (`read`, 644), so nothing under one cover goes
  into another. Each stretch of a band is the median of its pixels (655), so
  a letter's tail reaching into it does not darken it.
  - Erased fills the place with a field made from those colours alone
    (`drawField`, 307, opaque).
  - Blur draws that field, then soft spots of a tone made from the mean of
    the surroundings, as long and as many as a seeded random number says
    (`drawSmear`, 319); the seed is the place's position and size
    (`Seeded`, 666), never its pixels.
  - Pixels fills every tile opaque with the surroundings' colour mixed with
    that tone, weighted by position and the same seeded random (375).
  - Dots draws the field, then as many dots as fit the place's width
    (410). Like ink, it shows how wide the place is, not what was in it.
- Every copy is then checked in its pixels (`Finder.coversHold`); a look
  that let something through is made again in ink (`CoveredCopy.swift:27-33`).
- `CoverLookTests.testEveryLookHidesForGood` covers two pictures that differ
  only under the cover in each look and finds the results identical.

One fine point, true of ink as of the others, and of every version so far:
each look is drawn with rounded corners (`corner(of:)`, 255: at most 8 px, a
quarter of the height), so the very corners of the place's rectangle are not
painted. The places carry a margin round the text (`withMargin`,
`PrivateText.swift:598`: a quarter of the text's height across, a fifth up and
down; more with Strongest protection), so text does not reach those corners.
The claim stands; Version 2 keeps the footer as it is.

## 5. Not part of this audit

The Mac's Settings › Privacy pane is not changed. Instruments was not run
here (there is no Mac); see the pull request for what was verified.

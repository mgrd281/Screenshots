# Snapfly as one Mac and iPhone product: audit and road map

The owner asked for Snapfly to become one Apple product across the Mac and
the iPhone (October 2026). This is where it stands, measured against that
brief, and the order the rest is built in. Each line says what exists, what
is partly there and what is missing, and separates what is built, what is
tested and what still needs a real device. `SYNC.md` holds the sync design
and its threat model; this file does not repeat them.

## 1. Baseline

- **Targets.**
  - The Mac app is a SwiftPM executable (`Tendedero`, macOS 14) in two
    editions: the direct download and the Mac App Store (`STORE=1`).
  - The iPhone app (`iOS/Snapfly.xcodeproj`, iOS 17) has one target and no
    extensions. Both apps carry the same bundle ID.
- **Shared code.** `Sources/Tendedero/Shared`, compiled into both apps:
  finding and covering, the protection plan, sync, pairing and the index.
- **Builds.**
  - `build.yml` runs the strings check, `swift test` (68 test files, about
    500 tests, Mac and Shared code), the private-API check, signing and
    notarizing, and an unsigned iPhone archive.
  - `app-store.yml` and `iphone-store.yml` upload to TestFlight.
  - There are no tests of the iPhone-only code and no UI tests.
- **Third-party services.**
  - iCloud (CloudKit) for sync, only when the owner turns it on.
  - A Cloudflare Worker for Copy Link (`share/`).
  - The owner's own Claude or ChatGPT key, only when they set one up.
  - Nothing else.

## 2. Feature inventory

| Area | State | Where |
| --- | --- | --- |
| Finding private details: 21 kinds, own rules, person or company | Built, tested | `PrivateText.swift`, `DocumentSense.swift`, `OwnRules.swift` |
| Printed forms read field by field (label, then the value beside or under it in its column), each value covered only as its kind | Built, tested with made-up forms, on Linux and in Build Snapfly; not yet tried on a real scan; PDFs on the Mac only | `FormFields.swift` |
| Sure, to check, offered (confidence) | Built, tested | `Finder.Area.check`, `possible`; `ProtectionPlan` |
| Cover looks: ink, label, blur, pixels, dots, erase | Built, tested | `CoverLook.swift` |
| Copy read again and covered further; covers checked in the pixels | Built, tested; the pixel check runs on the iPhone only | `Finder.finish`, `ExportCheck.swift` |
| Metadata left out of copies | Built (copies are encoded afresh); no test yet | `Covering.png`, `Capture.swift` |
| iPhone editor, review one by one, Full Screen | Built; not yet tried on a device | `ProtectView`, `EditorParts`, `MarkCanvas` |
| iPhone library: search by words, show by kind, order | Built in this change; search covers screenshots read ahead of time | `LibraryQuery.swift`, `AllScreenshotsView` |
| Shortcuts, Back Tap | Built | `Intents.swift` |
| Share Extension | Built: covers as chosen in the app (kinds, look, own rules, through a shared keychain group), checks, copies, shares or saves; its identifier and profile are made by the upload itself; not yet tried on a device | `iOS/Share`, `CoveredCopy.swift`, `SharedChoice.swift` |
| Widget, Control Center control | Missing | an App Group in the developer portal for the widget's data |
| Handoff, iPhone Quick Look, drag and drop on iPhone | Missing | code only |
| Sync: CloudKit private database, CKSyncEngine | Built; compiles, never run between real devices | `CloudSync.swift`, `SyncCenter.swift` |
| Sync model: ids, revisions, content hash, tombstones, durable queue, backoff, duplicates | Built, tested on Linux | `SyncModel.swift`, `SyncLedger.swift`, `SyncPolicy.swift` |
| Sync of delete, rename, move, restore | In the ledger and tested; not called by either app | `SyncLedger.swift` |
| Conflicts | Both versions kept; no screen to choose | `SyncLedger.choose` |
| Status per screenshot (queued, sending, synced, failed) | Missing; only one status for the whole device | `SyncPolicy.SyncState` |
| Pairing across Apple accounts (six digits, 30 s, sealed) | Built, tested | `Pairing.swift`, `PairingCloud.swift` |
| Devices and disconnecting them | Built for paired accounts; not for a device on the same account | `SyncPane.swift`, `PhoneSync.swift` |
| Nearby transfer (Bonjour, peer to peer) | Missing; not planned before iCloud sync is proven | — |
| Mac workspace folders, categories, search | Built | `WorkspaceModel.swift`, `WorkspaceLibrary.swift`, `Search.swift` |
| Sorting screenshots into categories by themselves | Missing (order details are read: `OrderCard.swift`) | — |
| Share links: 7 days, delete token, rate limit | Built; delete tokens kept in UserDefaults, not the Keychain | `share/worker.js`, `ShareLinks.swift` |
| Timing of every step (signposts, median and 95%) | Built | `Timing.swift` |

## 3. Risks

1. **Sync has never run between two real devices.** Everything above the
   ledger compiles but is unproven, and the production schema step waits on
   the owner (`SYNC.md`). Nothing more is built on sync until one round trip,
   Mac to iPhone and back, is seen working.
2. **No tests of the iPhone-only code.** It is checked by building it, not by
   running it.
3. **Hand-written Xcode project.** A new target, such as an extension, has to
   be added by hand and signed by the iPhone App Store workflow too.
4. **Share-link delete tokens in UserDefaults.** Anyone with the Mac's user
   account can read them. They only allow deleting a link early, but they
   belong in the Keychain.

## 4. Road map

Each stage is one pull request, built, tested and merged before the next.

| Stage | What | Needs the owner |
| --- | --- | --- |
| A | This audit; iPhone library search, filter and order | No |
| B | Status per screenshot on both apps; delete, rename and move synced; a screen to choose between two versions; pause sync | No (proven only on two devices) |
| C | One round trip on real devices: Mac to iPhone and back | Yes: the CloudKit token and Deploy Schema Changes, then one test |
| D | Handoff of the open screenshot; Quick Look and drag and drop on the iPhone | No |
| E | Covers checked in the pixels on the Mac's ways out too; a test that copies carry no location or camera data; delete tokens in the Keychain | No |
| F | Categories suggested by themselves (orders, invoices, chats, documents), always correctable | No |
| G | Share Extension and a widget | Yes: an App Group and a new App ID with its profile in the developer portal |
| H | Onboarding that shows connecting the Mac, and a Devices page | No |

## 5. What is verified

| Criterion | Evidence |
| --- | --- |
| Both apps build | Build Snapfly on every push |
| Automatic tests pass | `swift test` in Build Snapfly |
| Existing Mac features intact | Their tests pass; no Mac code changed in stage A |
| Sensitive regions securely covered | Tests of the covering, the second reading and the pixel check |
| Protected copies shared natively | Share sheet, Photos and Files on the iPhone; not tried on a device in this session |
| Mac and iPhone linked securely | Pairing tests; never run on devices |
| Screenshots sync both ways, offline changes kept, transfers resumed, duplicates prevented, conflicts kept safe, devices revoked | Ledger tests only; **not verified on devices** |
| Accessibility | Labels, Dynamic Type and Reduce Motion in code; **not tried with VoiceOver on a device** |
| Performance on supported hardware | Timings are recorded on the device; **no measurements taken in this session** |

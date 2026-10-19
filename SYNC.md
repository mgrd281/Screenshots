# Mac and iPhone as one: the sync plan

Snapfly on the Mac and on the iPhone are to work as one: a screenshot taken
on the Mac shows up on the iPhone, a copy covered on the iPhone shows up on
the Mac, and nothing private leaves either device unless the owner chose it.
This file holds the audit the work started with, the design, what is built,
what is verified and what the owner has to do at Apple first.

**Where it stands (October 2026).** Phases 1 and 2 are built. The owner
made the iCloud container and gave the app's identifier iCloud and push
(section 5, steps 1 and 2). Builds now name the container where Apple's
profile allows it, and both apps have Sync in Settings, off until turned on:
the Mac sends covered copies of what hangs on the line and hangs what the
iPhone sends, and the iPhone shows what came under From your Mac and has
Send to Mac. Before it can work, the record types must be in iCloud's
production environment (section 5, step 3). Nothing has been tried on a real
device yet.

## 1. Audit (phase 0)

### What the repository holds

| Area | What there is |
| --- | --- |
| Targets | The Mac app, a SwiftPM executable (`Tendedero`, macOS 14, Swift 5 mode, universal), built as the direct edition (Developer ID, notarized) and the Mac App Store edition (sandboxed). The iPhone app, `iOS/Snapfly.xcodeproj` (iOS 17, SwiftUI). Same bundle ID, `de.ghazarian.Snapfly`. Besides them: the website (`website/`), the share-link Worker (`share/`), the promo videos (`promo/`). |
| Shared code | `Sources/Tendedero/Shared`, compiled into both apps: finding private details (18 kinds and the owner's rules), cover looks, protection, the AI account, the Workspace's rules, guides, Convert to SVG, share links, the 13 translations. |
| Storage | Files: the line's photos, the Workspace folder with a folder per category. Application Support: `Sent.json`, `Guide.json`, the Inbox, the shop logo. Settings in UserDefaults, the AI key in the Keychain. No database. The iPhone reads Photos and keeps only its settings. |
| Entitlements | Direct: Apple Events, microphone, hardened runtime, no provisioning profile. App Store: sandbox, files the owner picks, bookmarks, Pictures, Apple Events (with a temporary exception for browsers), network client, microphone. iPhone: none; Photos by permission. |
| Sign-in | None. Snapfly has no accounts. The only keys are the owner's AI key on the device and the repository secrets. |
| Sync | None before this work. |
| Cloudflare | Share links: a Worker and an R2 bucket, public links that expire after seven days. Separate from sync and staying so. |
| Tests and CI | 61 XCTest files with 428 tests, run by `swift test` on GitHub's macOS 26 runners; the strings check; the private-API check. Workflows: Build Snapfly (Mac and iPhone), App Store and iPhone App Store (TestFlight), Website, Share Links. |

### Inventory

**Already implemented**

- Mac: capture and the line, covering private details (18 kinds, six looks,
  strongest protection, Apple Intelligence on the device), Hide Part with
  click to cover and undo, the Workspace with its categories, guides, share
  links, the AI assistant, the guided tour.
- iPhone: screenshots from Photos, covered with the same engine and settings,
  saved as a new picture; Shortcuts actions Cover the Latest Screenshot
  (Back Tap) and Cover Private Details; coach marks.

**Partly implemented**

- Projects: the Workspace's categories exist on the Mac only.
- The privacy editor: complete on the Mac; the iPhone covers by itself with
  no manual correction.
- Safe copies: covered copies are new pixels without the original's metadata
  on both; the iPhone has no editor before saving.
- Apple integrations: two App Intents; no Share Extension, Handoff or links
  into the app.
- Sync: since this work, the foundation (below), not yet connected to either
  app.

**Not implemented**

- Syncing anything; a list of devices; sync settings and status.
- The iPhone gallery (grid, search, projects, several at once), its editor,
  the redesigned settings and onboarding.
- Share Extension, Handoff, deep links, syncing between different Apple
  accounts.

### Technical risks

1. **Apple setup only the owner can do.** CloudKit needs an iCloud container
   and the iCloud capability on the app's identifier, made in the Apple
   Developer website (section 5). No API makes a container. Until then no
   CloudKit code can run.
2. **The direct edition has no provisioning profile.** iCloud needs one, a
   Developer ID profile. Signing changes can break releases, so they come
   behind a switch, one edition at a time.
3. **Nothing can be tried here.** There is no Mac or simulator in this
   workspace. CloudKit code is compiled by CI and can only be tried on the
   owner's devices through TestFlight. Every claim about syncing waits for
   that.
4. **The production schema.** TestFlight and App Store builds use CloudKit's
   production environment, where record types must be deployed in the
   CloudKit Console before anything can be saved.
5. **The privacy promise.** README, the website, `PRIVACY.md` and the
   iPhone's Photos permission text ("Nothing is sent anywhere") say nothing
   leaves the device. Syncing changes that, so it is off until turned on,
   sends covered copies only unless the owner chooses originals, and those
   texts change in the same pull request that lets anyone turn it on.
6. **Photos are not files.** The iPhone has to keep its own copy of what it
   syncs, which takes room.
7. **Background on the iPhone.** Syncing while the app is closed needs Push
   Notifications on the identifier and the remote-notification background
   mode; without them the iPhone syncs when opened.
8. **Different accounts and revocation.** Removing a device from a list does
   not lock it out; signing it out of iCloud does. Syncing between different
   Apple accounts needs CloudKit sharing and its own design.

### Recommended order

1. Phase 1, the shared foundation. **Done.**
2. Phase 2a, the owner's Apple steps. **Done** (section 5, steps 1 and 2).
3. Phase 2b, the builds. **Done**: each edition gets the iCloud entitlements
   and the Info.plist line only when Apple's profile allows them; the direct
   edition fetches its Developer ID profile (`scripts/signing.sh
   cloud-profile`). The schema is `cloudkit/schema.ckdb`, put into
   development by the CloudKit Schema workflow. **Waiting** for the owner's
   token and the deployment to production (section 5, step 3).
4. Phase 2c, the MVP. **Done** in code: Sync in Settings on both (on or off,
   originals too), the devices, the status, Sync Now; the Mac sends covered
   copies of what hangs on the line and hangs what the iPhone sends; the
   iPhone lists what the Mac sent, fetches a picture when it is opened, and
   has Send to Mac. README, `PRIVACY.md`, the website (German) and the
   iPhone's texts say so. Not yet: per-project choices (projects travel, but
   there is no switch for them), choosing between two versions made at once
   (they are kept, the newer shows), a list on the Mac of what came before
   syncing was turned on.
5. Phase 2d: the 14 cases (section 4) on the owner's Mac and iPhone.
6. Then phases 3 to 6 of the brief.

## 2. Design

### Files

| File | What it holds |
| --- | --- |
| `Shared/SyncModel.swift` | The records (device, project, screenshot, version), the clock that orders changes, fields that merge, the record names, the payload with its version, a waiting change, failures and retry delays |
| `Shared/SyncLedger.swift` | What a device knows: every record, its own copies, the changes waiting, what iCloud has; the changes made here, merging what comes from iCloud, conflicts, removal, the file in Application Support and its migration |
| `Shared/SyncPolicy.swift` | The owner's choices, what may leave the device, the status |
| `Shared/CloudSync.swift` | The iCloud side: Apple's CKSyncEngine, the private database, previews, whole pictures on demand, errors and accounts |
| `Tests/TendederoTests/SyncTests.swift` | Two ledgers standing for a Mac and an iPhone, and iCloud between them |

### Records

All of them live in the owner's private CloudKit database, in the zone
`Snapfly`; whole pictures sit in the zone `SnapflyFiles`, which the engine
does not fetch, so a picture is downloaded only when it is opened.

- **Device**: id (made once on the device; it names the device, it proves
  nothing), name, platform, model, registered, last seen, last sync, app
  version, newest schema. Each device writes its own record only, when
  something about it changes and otherwise at most hourly.
- **Project**: a Workspace category, with the category's id, so the standard
  ones are one project on every device. Name, order, whether it syncs,
  whether it was removed.
- **Screenshot**: id, origin device, created, name, project, the versions set
  aside, removal.
- **Revision** (a version): id, screenshot, the version it replaces, device,
  time, kind of change (captured, covered, edited), content (original or
  covered), what was covered (kinds, places, look; never the words), file
  name, SHA-256, size, and a small preview as an asset.
- **File**: a version's whole picture, as an asset.

Record names are `Kind.id`. Each record's contents travel as one JSON
payload with the schema version in an encrypted field, so a record can gain
fields without a schema change in CloudKit; new fields are optional, or the
schema version rises.

### Merging

- Changes are ordered by a hybrid logical clock: a change made after seeing
  another always comes after it, even when one device's clock runs behind.
- Names, projects and settings of a project: the later change wins, on
  every device, in whatever order changes arrive.
- Pictures never merge that way. Versions never change once made; a change
  is a new version that names the one it replaces. Two devices changing the
  same screenshot make two versions with the same parent, and both stay: the
  screenshot shows a conflict until the owner chooses. The other version is
  set aside, not deleted; if it is changed again elsewhere, the owner is
  asked again.
- A record arriving twice changes nothing. When a device knows something
  newer than what arrived, it sends the merge back, so all end the same.
- The same picture brought in twice (same SHA-256) is one screenshot.

### Removing

- **Remove from this device**: only the local copy goes; it stays in iCloud
  and can be fetched again.
- **Remove from the synced screenshots**: gone on every device and kept in
  iCloud for 30 days, so it can be brought back and so a device that was away
  learns of it instead of bringing it back. A version made later on a device
  that had not heard yet brings it back, so no edit is lost.
- **Remove permanently**: the pictures leave iCloud at once and nothing
  brings it back.
- After 30 days a removed screenshot leaves iCloud for good. A device away for
  longer hears of it through the engine's deletions.

### Waiting to go

Every change waits in the ledger's journal until iCloud has it, so nothing is
lost offline or when the app quits midway. One change per record waits; a
newer one replaces it, and removing for good wins over saving. Small records
go before pictures. After a failure it waits 30 seconds, then a minute, two,
up to an hour, or as long as iCloud asked; after 8 failures it stops and
waits for the owner (Sync Now), so it never retries forever. Being offline is
not a failure: the engine sends again once there is a connection. A change
made while its record was being sent goes once more.

### What may leave the device

Decided in `SyncPolicy`, and asked again just before each record goes, so a
setting changed meanwhile counts.

- Nothing while syncing is off, which it is until the owner turns it on.
- Covered copies only, unless the owner also chooses originals; then only
  originals taken from that moment on, never the older ones unasked.
- Nothing from a project set not to sync.
- Only versions made on this device; nothing larger than 50 MB.
- A screenshot with nothing that may go is not even named in iCloud.
- A preview is made from the version itself, so a covered copy's preview
  shows nothing it covers, and carries no metadata.

### Accounts and versions

- Only devices on the same Apple account sync. The first account is
  remembered; another one pauses syncing and asks, and what came from the old
  account leaves the device, while what was made on it stays.
- Signing out of iCloud removes what came from iCloud; the device's own
  screenshots stay.
- If the owner removes Snapfly's data in iCloud's settings, syncing stops and
  nothing is sent back unasked. If iCloud's keys were reset, everything made
  on the device goes again.
- A record from a newer Snapfly is left alone and the status asks for an
  update. A ledger file from a newer Snapfly is left as it is; an unreadable
  one is set aside under another name, never overwritten.

### Status

This device: off, unavailable (no iCloud account, restricted, not in this
build), up to date, syncing (with how many changes wait), waiting for the
network, or needs attention (iCloud full, changes stuck, an update needed,
another account, data removed in iCloud). Other devices show when they were
last there, apart from that: a device can be away while everything it had is
already in iCloud.

## 3. Threat model and what Snapfly claims

- **On the way**: TLS between the device and iCloud, by Apple.
- **In iCloud**: the private database of the owner's Apple account. The
  records' contents are in CloudKit's encrypted fields, whose keys are in the
  owner's iCloud Keychain. Pictures and previews are assets, which Apple
  encrypts in storage; they are end-to-end encrypted only when the owner has
  turned on Advanced Data Protection. **Snapfly does not claim end-to-end
  encryption.**
- **On the device**: files in Snapfly's folder in Application Support (inside
  the sandbox for the App Store edition), protected by the system (FileVault,
  the iPhone's data protection).
- **Who can read**: devices signed in to the owner's Apple account. The
  device list grants nothing. "Disconnect" will mean that a device stops
  syncing and removes what came from iCloud; it does not lock another device
  out, and Snapfly will not say it does.
- **Covered copies by default**: what is covered is burnt into the pixels;
  the covered words are never sent.
- **Share links stay apart**: public, for seven days, made only when the
  owner asks. Sync never makes a link, and links never use sync.
- **Different Apple accounts** (brief 3.2): not built. It would use CloudKit
  sharing with an invitation the other person accepts, and is designed only
  after syncing within one account is verified.

## 4. When things go wrong

| Case | What happens | Checked |
| --- | --- | --- |
| 1. The Mac is off | The iPhone keeps working; the Mac fetches when it starts | Device: waits for 2d |
| 2. The iPhone loses Wi-Fi | Changes wait; status "waiting for the network"; not counted as failures | Unit test; device: 2d |
| 3. Mobile data | iCloud's own setting for mobile data applies | Device: 2d |
| 4. iCloud unreachable | Waits and retries with growing delays, at most 8 times | Unit test; device: 2d |
| 5. Signed out or another account | Pauses, asks; what came from the old account leaves | Unit test; device: 2d |
| 6. Storage nearly full | iCloud full stops and says so; nothing is retried in vain | Unit test; device: 2d |
| 7. Upload cut off | The change stays in the journal and goes again | Unit test; device: 2d |
| 8. App quit while syncing | What was being sent waits again at the next start | Unit test; device: 2d |
| 9. Both edit one picture | Both versions stay; the owner chooses | Unit test; device: 2d |
| 10. Removed while offline | The removal travels and wins over older changes | Unit test; device: 2d |
| 11. Syncing turned off midway | Asked again before each record goes; nothing more leaves | Unit test; device: 2d |
| 12. Permission taken away | No iCloud: "unavailable", local work goes on | Unit test; device: 2d |
| 13. An older app version | Newer records are left alone; an update is asked for | Unit test; device: 2d |
| 14. The local store changes | Versioned file, migration step, newer left alone, unreadable set aside | Unit test |

## 5. What the owner does at Apple

On https://developer.apple.com/account, under Certificates, Identifiers &
Profiles:

1. **The container.** Identifiers, the plus button, iCloud Containers,
   Continue. Description `Snapfly`, identifier `iCloud.de.ghazarian.Snapfly`.
   Continue, Register.
2. **The identifier.** Identifiers, then `de.ghazarian.Snapfly`. Tick iCloud
   (with CloudKit), press Edit or Configure beside it, tick
   `iCloud.de.ghazarian.Snapfly`, Continue. Tick Push Notifications. Save, and
   confirm that the profiles become invalid: the workflows make new ones by
   themselves (`scripts/asc.swift` replaces an invalid profile).
3. **The schema, once.** In the CloudKit Console
   (https://icloud.developer.apple.com), open the account menu at the top
   right, then Settings and Tokens, and make a management token. Paste it in
   GitHub as the repository secret `SNAPFLY_CLOUDKIT_TOKEN`, then run the
   CloudKit Schema workflow (Actions, CloudKit Schema, Run workflow). When it
   is green, open CloudKit Database in the console, choose the container
   `iCloud.de.ghazarian.Snapfly`, and press Deploy Schema Changes, then
   Deploy. From then on, records can be saved by TestFlight and App Store
   builds.

Nothing from steps 1 and 2 goes into GitHub; step 3's token does, as a secret.

## 6. What is verified

| Part | Implemented | Tested here (Linux) | CI (macOS) | Simulator | Real device |
| --- | --- | --- | --- | --- | --- |
| Records, merging, journal, policy, status, ledger file | Yes | Yes, 45 tests | Yes | No | No |
| `CloudSync` (CloudKit) | Yes | Syntax only | Compiles | No | No |
| `SyncCenter`, Mac and iPhone screens | Yes | Syntax only | Compiles | No | No |
| Entitlements and profiles in the three builds | Yes | Shell syntax only | Runs on the next builds | n/a | No |
| Schema import (`cloudkit.yml`) | Yes | No | Waits for the token | n/a | n/a |
| A Mac screenshot reaching the iPhone, and back | Yes | No | No | No | No |

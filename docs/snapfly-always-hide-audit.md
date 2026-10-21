# Always Hide: audit and redesign

The iPhone's "Außerdem verbergen" screen (Also hide) became "Immer verbergen"
(Always Hide) in October 2026, at the owner's request. This file records what
the audit found before the redesign, what changed, and what was checked. File
references point at the code after the change unless they say "before".

## 1. What there was

### Views (before)

- **The screen** was `AdvancedSettings` in `iOS/Snapfly/SettingsView.swift`,
  opened from More › Advanced › Also hide. It was a plain `Form`:
  - "Your Details": a row per detail (`OwnDetailRow`, its symbol on the
    protect green, its name, its value with a number by its last four
    digits), swiped away to remove, and Add Detail, a menu of the four kinds.
    The footer promised the details "stay on this iPhone alone, in no
    backup, and are never sent".
  - "Your Rules": a row per rule (`RuleRow`), its kind as a menu over a text
    field, swiped away to remove, and Add Rule.
- **The sheet** for a detail was `OwnDetailEditor` in
  `iOS/Snapfly/OwnDetailsSettings.swift`: one field for a name ("First and
  last name"), three for an address, the number for a card or an account
  with a name for it, a kept number hidden behind Show Number, and Delete
  Detail.
- Settings › People opened with Your Name (`OwnNameRow`), which used the same
  sheet.
- On iOS 26, the tab bar shrinks to the chosen tab's button while a page
  scrolls (`tabBarShrinksOnScroll`, `iOS/Snapfly/AppTabs.swift`). For More,
  that button is `ellipsis.circle`: the floating "…" over the screen's rows.
- The Mac shows the same details and rules in Settings › Privacy
  (`Sources/Tendedero/SettingsWindow.swift`).

### Data model

`OwnRule` (`Sources/Tendedero/Shared/OwnRules.swift`) is one type for both:

- **Rules:** `word`, `label`, `pattern`, with their `text`.
- **Details:** `name` (`text`), `address` (`text` the street with its house
  number, `postcode`, `city`), `card` and `account` (`text` the digits or the
  IBAN, `caption` an optional name like "Girokonto").
- Decoding is lossy per item (`OwnRules.decoded`), so one rule that cannot be
  read loses no other.

### Where they are kept

- **Rules:** `UserDefaults.standard`, key `ownRules`, as JSON, the details
  filtered out (`OwnRules.save`, `OwnRules.swift:162`). The settings file is
  part of the device's backups.
- **Details:** one keychain item, generic password, service "Snapfly
  details", account "details", holding all of them as JSON (`OwnDetailStore`,
  `OwnRules.swift:263`). On the iPhone its class is
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`OwnRules.swift:355`);
  `kSecAttrSynchronizable` is never set anywhere. On the Mac no class is set
  and the item lands in the login keychain.
- **For the share extension:** `SharedChoice` keeps the chosen kinds, the
  look and `OwnRules.all` (rules and details) in a keychain item of the app
  group, with the same class (`SharedChoice.swift:47`), written by
  `Choice.share()` when the app leaves the foreground
  (`iOS/Snapfly/Covering.swift`).

### How covering uses them

- `Finder.collect` (`Sources/Tendedero/Shared/PrivateText.swift`) adds the
  owner's own places through `own(in:)`: `ruleRanges` (a word as a whole word
  in any case, a pattern as it matches, and every detail through
  `OwnDetails.ranges`) and the label rules.
- These places carry no kind (`kind == nil`). `decided` keeps every one of
  them whatever is chosen, never marked to check
  (`PrivateText.swift:2595`).
- The owner's name, kept as a detail or as a word that reads as a name,
  also feeds `ownWords`, so a name hit made of those words is the owner's,
  never to check, and covered with any of the three name switches on.
- Before the words of a screenshot went to the AI assistant ("Find more
  with Claude/ChatGPT"), `Protection.byAssistant` hid the details in them
  (`OwnDetails.masking`), but not what a word, label or pattern rule covers.

### How "Nach einer Bezeichnung" decided

A label rule looked for lines that begin with the label (anchored, in any
case, without accents counting, and never the start of a longer word). It
then dropped any `: - – tab` after the label:

- Something left on the line → that rest of the line was covered.
- Nothing left → the line below was covered, found by geometry:
  `Finder.line(below:in:gap:)` with a gap of twice the line height, in the
  same column.

So the app decided automatically. That is the new "Automatisch", the first
option and the default for every rule kept before.

### Matching (before)

- **Names:** as typed, surname first, the first given name alone with the
  surname, the initial before or after the surname, the surname alone, and
  the first given name alone from four letters; in any case; with up to
  three characters of space, comma or dot between the words.
  - Each word of five letters or more could be misread by one letter, so
    two words could each be one letter off. A word alone could be misread
    only from seven letters.
  - Matched within a line only.
- **Sheet versus matcher:** the sheet's examples ("Musterfrau, Erika · E.
  Musterfrau · MUSTERFRAU") were written by a different function from the
  matcher's forms.
- **Numbers:** in groups with single spaces, dashes or dots between them;
  an IBAN with an O read for a 0 and the like; within a line.
- **Addresses:** the street with its house number, "Straße" as "Str.", and
  the postcode with the town; exact letters.

## 2. Privacy, as verified in code

| Promise | Holds? | Where |
| --- | --- | --- |
| Only on this iPhone | Yes. ThisDeviceOnly class, never synchronizable; no iCloud key-value store; sync sends covered copies only, never settings or details. | `OwnRules.swift:355`, `SharedChoice.swift:47`, `Shared/SyncPolicy.swift` |
| No backup | **No.** Apple: a ThisDeviceOnly item is "always protected with the UID when being copied from the device during a backup, rendering it useless if it's restored to a different device". It is in the backup, sealed to this iPhone. Only `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` stays out of backups, and it cannot be read while the iPhone is locked nor kept without a passcode, so background preparation could no longer cover the details. | Apple Platform Security, "Keychain data protection"; `OwnDetailStore.staysOutOfBackups` |
| Never sent | Yes. No log, analytics, crash report, export or request carries a detail. The only request with a picture's words is the AI assistant's, and the details are hidden in them first; Explain sends the covered copy only. | `Shared/Protection.swift:191`, `PrivateText.swift:1631` (`Finder.masking`), `iOS/Snapfly/ExplainSheet.swift` |

- **No backup is left out.** The strip shows two promises, and the line over
  a detail's button reads "Bleibt nur auf diesem iPhone und wird nie
  gesendet." Each is shown from a flag next to the keychain code
  (`OwnDetailStore.staysOnThisDevice`, `staysOutOfBackups`, `neverSent`), so
  a change to the store and to what the screen says go together.
- **The old "in no backup" was wrong.** It appeared in the iPhone footer,
  README, PRIVACY.md (English and German), DESIGN.md, the CHANGELOG, the
  German privacy page and two code comments. All now say what is true: kept
  for this device alone, never in iCloud, and in a backup only sealed to this
  same device.
- **Logs:** no `print`, `NSLog` or `os_log` of a rule, a detail or a
  picture's words; `Timing` logs step names and milliseconds only.
- **Analytics and crash reports:** none. No third-party dependency in
  `Package.swift` or the iPhone project; the privacy manifest declares no
  tracking.
- **Exports:**
  - Pasteboard and share sheets: covered copies only.
  - The Mac's Copy Text hides rule and detail places as "•••".
  - Guides drop element names that match rules or details.
  - The iPhone's optional local index keeps read words on the iPhone,
    excluded from backups, and sends nothing.

## 3. What changed

### The screen and its sheets

- **Screen:** `AlwaysHideView` in `iOS/Snapfly/AlwaysHide.swift`. Large title
  "Immer verbergen", its subtitle, the privacy strip, Deine Angaben, Eigene
  Regeln with "N aktiv", the footer, and the empty state.
  - Edit reorders and deletes; a swipe deletes.
  - The tab bar is hidden on it, which removes the floating "…".
- **Sheets** (`iOS/Snapfly/AlwaysHideSheets.swift`):
  - `DetailSheet` replaces `OwnDetailEditor`, here and under Settings › People.
  - `RuleSheet` is new: Wort, Nach Bezeichnung, and Muster only for a pattern
    kept before.
- **The More entry** is "Immer verbergen".

### The data model

- **New fields:** `OwnRule.isEnabled` (default on) and `OwnRule.reach`
  (`automatic`, `restOfLine`, `nextLine`; default automatic). Details are
  always on, whatever the field says (`isActive`).
- **Migration:** rules kept before decode as on and automatic. A reach a
  later version wrote that this one does not know reads as automatic and
  keeps the rule (`AlwaysHideTests`).
- **Two name fields:** "Vorname" and "Nachname" are kept as "Nachname,
  Vorname" in the same `text`, so the Mac, the keychain format and the
  matcher need nothing new. A name kept on one line before opens split by the
  matcher's own rule: the last word with its particles is the surname.

### Matching

- **One list:** `OwnDetails.nameVariants` is what the sheet's chips show
  and what the matcher looks for (`nameForms`, derived from it).
- **Line breaks:** a name, an IBAN or a card number broken over two lines is
  found.
- **Punctuation:** a slash or a semicolon between a name's words is fine
  ("MUSTERMANN/MAX").
- **One misread character at most:**
  - Names: in a word of five letters or more beside the rest of the name.
    A word alone needs seven, so "Mutter" is never read as "Muster".
  - Streets and towns: one letter, from five; never a house number or a
    postcode.
  - IBANs and card numbers: one character, but only when the number adds
    up, since no other valid IBAN or card is one character from it.
- **For sure:** what a detail or rule covers is never marked to check, and
  drops out of the "may be private" list (`Finder.sure`).
- **Rules turned off** cover nothing (`isActive` everywhere the engine reads
  rules) and leave the fingerprint, so copies are covered again.
- **AI assistant:** what goes to it has the rules' places hidden too, not
  only the details, and the details in a few more forms, like a surname in
  small letters (`Finder.masking`).

### Validation

- A card needs 12 to 19 digits that pass the Luhn check, and an IBAN must
  add up (mod 97).
- A name needs a first or a last name.
- `OwnDetails.canKeep` is shared, so the Mac's sheet asks the same.

## 4. Checked

- **Linux:**
  - The engine and its tests run on Linux: `AlwaysHideTests` (23 tests) with
    the existing OwnDetails, Redaction, CategoryFidelity, DocumentSense,
    FormFields and others. See the pull request for the counts.
  - `swift scripts/check-strings.swift` checks the 58 new strings in the 13
    languages.
- **macOS CI:**
  - The Build Snapfly workflow runs `swift test` and archives the iPhone app.
  - The Always Hide Checks workflow (`scripts/always-hide-checks.sh`) runs
    `iOS/SnapflyUITests` on the simulator and captures every screen and
    sheet, light and dark, at XXXL and accessibility sizes, on the newest
    and the smallest iPhone, to the `always-hide-captures` pre-release.

## 5. Left as found

- **The Mac's hand-out:** it skips covering when no kind is chosen, without
  looking at rules or details (`Sources/Tendedero/PrivateDetails.swift:209`).
  With every kind unchecked on the Mac, the owner's details are not covered
  in what leaves the line. The iPhone and Cover Files do look. Outside this
  screen; for the owner to decide.
- **Patterns on the iPhone:** no new ones are made there. A pattern kept
  before shows, switches, changes and deletes as before, and the Mac still
  makes them.
- **A card's or an account's own name** ("Girokonto") is kept and shown in
  its row, but the new sheet has no field for it.

## 6. The Mac, after

At the owner's request, the Mac followed in a pull request of its own:

- Always Hide is a pane of its own in Settings
  (`Sources/Tendedero/AlwaysHidePane.swift`), taken out of Privacy.
- It shows the same rows, chips, switches and "N active" as the iPhone, and
  sheets with First Name and Last Name, the name's forms as they are typed, a
  label's reach and the live example.
- The footer and the sheet no longer promise "wherever and however".
  `OwnDetails.note(for:)`, which said it, is gone.
- What both apps draw alike is in `Sources/Tendedero/Shared/HideParts.swift`.

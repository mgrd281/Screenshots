# Snapfly on the iPhone: What Is Covered, before the live preview

An audit of More › What Is Covered (Was verdeckt wird) as it shipped with
More Version 2 (1.1.0, build 216), made before the page was rebuilt as a
live preview. It lists every category, the key it is kept under, its
default, the values the old preset buttons wrote, and every place that
reads them. Paths are from the repository root.

## 1. Where the choice is kept

All twenty-two categories are kept together, under one key:

- **Key:** `hiddenDetails` in `UserDefaults.standard`. It holds a sorted
  string array of `PrivateDetail` raw values.
- **Accessor:** `Choice.details` (`iOS/Snapfly/Covering.swift:18`). Reading it
  first runs `PrivateDetail.bringUpToDate(["hiddenDetails"])` once per
  launch, which also reads and writes `knownDetails`, `namesParted` and
  `nameRoles`, and `OwnRules.adoptName()`. Setting it writes the sorted array
  and calls `Choice.share()`, which copies the choice, the look and the rules
  to the share extension (`SharedChoice`).
- **Default while the key is absent:** `PrivateDetail.recommended`, the 13
  kinds marked "on by default" below.

Nothing on the page is kept anywhere else. The new page reads and writes
through `MoreStore.choose(_:)` → `Choice.details`, exactly as Version 2 did,
so no value is renamed, reset or migrated.

## 2. Every category

| # | Category (German) | Raw value | Default | iPhone group (`CoverGroup`) | Mac group (`PrivateDetail.Group`) |
|---|---|---|---|---|---|
| 1 | Namen | `names` | on | Personen und Firmen | People |
| 2 | Patientennamen | `patientNames` | on | Personen und Firmen | People |
| 3 | Weitere Personen | `otherPeople` | on | Personen und Firmen | People |
| 4 | Adressen | `addresses` | on | Personen und Firmen | People |
| 5 | Geburtsdaten | `birthDates` | on | Personen und Firmen | People |
| 6 | E-Mails | `emails` | on | Personen und Firmen | People |
| 7 | Telefonnummern | `phones` | on | Personen und Firmen | People |
| 8 | Benutzernamen | `usernames` | off | Personen und Firmen | People |
| 9 | Gesichter | `faces` | off | Personen und Firmen | People |
| 10 | Unternehmen und Organisationen | `organizations` | off | Personen und Firmen | Companies and organizations |
| 11 | Bankkarten und Konten | `bank` | on | Geld | Money |
| 12 | Beträge | `amounts` | off | Geld | Money |
| 13 | Gesundheitsdaten | `health` | on | Gesundheit | Health |
| 14 | Ausweis- und Steuernummern | `ids` | on | Dokumente | Documents |
| 15 | QR-Codes und Barcodes | `barcodes` | on | Dokumente | Documents |
| 16 | Bestell- und Kundennummern | `orders` | off | Dokumente | Documents |
| 17 | Sendungsnummern | `tracking` | off | Dokumente | Documents |
| 18 | Datumsangaben | `dates` | off | Dokumente | Documents |
| 19 | Links | `links` | off | Dokumente | Documents |
| 20 | Passwörter und Codes | `codes` | on | Zugänge | Passwords and access |
| 21 | API-Schlüssel und Tokens | `keys` | on | Zugänge | Passwords and access |
| 22 | IP-Adressen | `ipAddresses` | off | Zugänge | Passwords and access |

All 22 categories are in the brief's table and in its samples; none was
missing, so no sample line was added beyond the brief.

## 3. What the old preset buttons wrote

The segmented control of Version 2 (`PresetControl`, `CoverPreset`) kept
what Check All, Recommended and Uncheck All wrote before it. These are the
values; the tests compare the new menu with this fixture
(`CoverStudioTests.testTheMenuWritesWhatTheOldButtonsWrote`).

| Old button | Writes to `hiddenDetails` |
|---|---|
| Recommended (Empfohlen) | the 13: `addresses`, `bank`, `barcodes`, `birthDates`, `codes`, `emails`, `health`, `ids`, `keys`, `names`, `otherPeople`, `patientNames`, `phones` |
| Check All (Alle) | all 22 |
| Uncheck All (Keine) | `[]` |

A group's All On / All Off changed only that group's kinds
(`CoverSummary.setting(_:on:)`); the new sheets keep that.

## 4. Who reads the choice

- **The covering itself**:
  - `AppTabs.swift` (quick cover);
  - `Selecting.swift`;
  - `Intents.swift` (Shortcuts and Back Tap);
  - `ScanTab.swift`;
  - `ProtectSession.swift`;
  - the share extension, through `SharedChoice`.
- **More, through one `MoreStore` (`@StateObject` in `SettingsView`)**, which
  holds `chosen` as `@Published` and is handed to the page:
  - the hero's count, "Schutz aktiv / aus", the preset badge and its colour
    (`SettingsView.swift`, `hero`);
  - the tile What Is Covered: the meter and "x von 22 aktiv" (`coveredTile`);
  - What Is Covered itself (`CoveredKindsView`).

  All three read `store.summary` (`CoverSummary(store.chosen)`), so they
  always agree. The new page keeps that single source: the stage, the tiles,
  the sheets, the hero and the tile all read the same `MoreStore`.
- **Always Hide** (`OwnRules`, the keychain) is separate. The page's "Eigene
  Angaben" tile only shows its initials, through `store.own`.

## 5. What the page had, and what goes

Removed with the rebuild:
- the header with "x von 22" and the badge;
- the segmented control (`PresetControl`);
- the group tabs;
- the group cards of pills (`KindPill`, `PillFlow`);
- the names note under People;
- the "Your Own Details" card.

Removed strings:
- "%d of %d" stays: the tiles use it;
- "Categories covered in every picture" stays: the hero uses it;
- "All On" and "All Off" go, replaced by "Turn All On" and "Turn All Off";
- "All three together cover everyone’s names." goes, replaced by the sheet's
  footer;
- the rest are listed in the pull request.

The Mac's Privacy pane, its six groups and its switches are not touched.

# Snapfly: covering only what Settings chooses

A fault report on the iPhone, October 2026. Snapfly covered details the
owner had turned off in Settings › Privacy. It also marked the patient's own
name "zu prüfen", although that name was saved in the app. This document
gives the root cause, the fix, the tests and what is not verified.

- Line references are to `main` at `942324d`, before the fix.
- The owner's screenshot is a real medical letter. It is not in the
  repository, and no word of it is in a test. Every fixture here is made up:
  Erika Musterfrau of Kastanienweg 14 and the practice "Radiologie Nordtor"
  do not exist.

## 1. What was seen

Settings on the owner's iPhone:

- **On:** Namen, Patientennamen, Weitere Personen.
- **Off:** Adressen, Geburtsdaten, E-Mails, Telefonnummern.

The other kinds were not named in the report.

The document was a German radiology report laid out as a letter.

| # | Seen | Expected |
|---|---|---|
| 1 | Covered although their kinds were off: <br>• the street, the postcode and the town <br>• the birth date <br>• the place and date in the letter head <br>• the exam's date <br>• the "Referenznummer" <br>• "LWK 5/SWK 1" in the findings <br>• "Weiterer Standort in Hamburg" in the side column | Only kinds that are on are covered |
| 2 | The patient's name, saved in the app, marked "zu prüfen" | Covered as a sure name |
| 3 | A cover over the street name, with the house number left showing | The whole entity covered |
| 4 | With Namen on, the two kinds under it look forced on | Every combination possible, and clear |

## 2. Reproduced

The fixture `CategoryFidelityTests.letter` copies the report's layout:

- the letter column;
- the sender's line;
- the address block: name, street, postcode and town;
- the place and date;
- "Unser Zeichen";
- the subject box: "Musterfrau, Erika" with "geb. …" on its row, and the address;
- the exam line;
- "Referenznummer";
- the findings with "LWK 5/SWK 1" and "Morbus Scheuermann";
- the signatures;
- a side column of headings, doctors and bank details, ending in
  "WEITERER STANDORT / IN HAMBURG".

The engine's text half, `Finder.findings`, was run on it before the fix. It
needs no picture and runs on Linux with the harness in section 6. The
"cover" and "offer" lines below are its output.

With **Namen, Patientennamen and Weitere Personen**:

```
cover names CHECK [Erika Musterfrau]   patient 0.75 birth
cover names CHECK [Musterfrau, Erika]  patient 0.75 birth
cover names CHECK [Lea Probst]         doctor 0.75 signature
cover names CHECK [WEITERER STANDORT]  other 0.3 none
cover names CHECK [IN HAMBURG]         other 0.3 none
cover names       [Jonas Beispiel]     doctor 0.9 title
```

With **Patientennamen alone**, "WEITERER STANDORT" and "IN HAMBURG" were
still covered, as names whose role is unclear.

The street, the dates, the reference number and "LWK 5/SWK 1" were not
covered by the patterns and finders. They come from Apple Intelligence,
which the iPhone runs after the patterns (`ProtectSession.swift:156-166`),
where it is on (section 3.4). Section 5's test
`testAppleIntelligenceCannotCoverWhatItsKindDoesNotFit` gives the engine
the answer such a model gives, and checks what is kept.

## 3. Root cause

### 3.1 Where each detection gets its kind

Every place found is a `Finder.Hit` with one `kind: PrivateDetail?`.

- A nil kind is one of the owner's own rules.
- A name has kind `.names`. Patient names and other people are kept apart
  by the hit's `role` (`NameRole`), not by a kind of their own.

| Source | Where | Its kind |
|---|---|---|
| Patterns (email, IBAN, …) | `patterns(in:_:)` and `patternRanges` (`PrivateText.swift:1611`, `:1636`) | The pattern's kind, one kind at a time |
| A label and its value ("IBAN:", "Patient:") | `labelled` (`:1822`), `parts(of:…)` (`:1900`) | The label's block |
| A form's fields | `FormFields.read`, then `Entity.detail` (`:160`) | The field's entity |
| Names | `names(in:learned:)` (`:2015`) | `.names` |
| A letter's address under a name | `addresses(after:in:)` (`:1151`) | `.addresses` |
| Reference numbers in a medical letter | `references(in:)` (`:1231`) | `.ids` |
| Companies | `organizations(in:)` (`:2183`) | `.organizations` |
| Medicines | `medicines(in:)` (`:2257`) | `.health` |
| Apple Intelligence or the AI assistant | `intelligentHits` (`:923`) | **The kind the model writes in its answer** |
| Codes and what they print | `codes(in:_:)` (`:739`); the printed contents (`:875`) | The first chosen kind a code holds; printed contents always `.barcodes` |

### 3.2 Where the filter for the kinds that are on is applied, and where it is not

- `decided(_:in:_:scope:)` (`:2207`) is the filter. It drops a hit whose
  kind is off, and keeps a name only if its role is one whose names are
  covered. Every hit of the patterns, labels, forms, names and finders goes
  through it (`:1122`), and so does the model's (`:879`).
- **The filter trusts the kind it is given.** For the model's hits, that
  kind is the model's own word. `intelligentHits` checks only that the kind
  is on and that the words are in their line (`:930-932`). Nothing checks
  that the words are what the model says they are.
  - With only the name kinds on, the model is asked for "name" alone
    (`Protection.swift:152`, `askedWords`), and told to "name no other kind".
  - A small model then calls private-looking things "name": the street, the
    town, a date, a reference, "LWK 5/SWK 1".
  - Each passes as a name, and is covered as one, with no mark to check.
  - That is fault 1, apart from "Weiterer Standort", and why those covers
    looked sure.
- The printed contents of a code are always `.barcodes`, even when the code
  was covered for another kind (`:1604`). The final gate in the fix needs
  each place's real kind, so they now take the code's kind.

### 3.3 Is "Patientennamen" "all of the patient's data"?

**No.**

- `resolved(_:)` (`:543`) turns Patientennamen and Weitere Personen into
  `.names` with a `NameScope` of roles.
- The patient's address, birth date and reference get a role
  (`owned(_:by:kind:)`, `:1131`), for the editor's "who and what" list.
- They are covered only by their own kinds: `addresses` (`:1102`), the
  birth-date pattern (`:1755`) and `ids` (`:1104`).
- So no patient data beyond the name came from Patientennamen. It came from
  the model's "name" answers (3.2).

### 3.4 Does an AI classifier return entities outside the requested categories?

**Yes, in effect.**

- Its answer is parsed by `parsePrivate` (`Protection.swift:71`). That
  keeps a row only if its kind is a known word and its words are in the line.
- A row of a kind not asked for is dropped later, because that kind is off
  (`:930`).
- But a row of the asked kind holding words of another kind is kept. A
  street, a date or an anatomical code labelled "name" is one.
- The model decided what was covered, which the report asks never to happen.
- This applies to Apple Intelligence on the device and to the AI assistant
  (Claude or ChatGPT) alike: both answers go through `parsePrivate` and
  `intelligentHits`.

### 3.5 How a saved own name is used, and why an exact match stays "zu prüfen"

- **Snapfly has no own-name feature.** Nothing stores "my name" for
  recognition. Searches for an own, saved or known name in `Sources/` and
  `iOS/` find none.
- What exists is the owner's own rules (`OwnRules.swift`): a word, a label
  or a pattern, covered wherever it appears, whatever kinds are on.
  - A name saved there is covered where it is written in the same order:
    "Erika Musterfrau" (`ruleRanges`, `:1331`).
  - It is not covered as "Musterfrau, Erika", as "ERIKA" on a line of its
    own, or with a letter misread.
  - It was never used to recognise names: `names(in:learned:)` does not read
    the rules.
- **Why "zu prüfen":**
  - `names(in:learned:)` covers a line shaped like a name only once
    something vouches for it: the Natural Language tagger, an email address,
    or a name met elsewhere (`:2063-2077`).
  - An unusual name the tagger does not know is vouched for by none of them.
  - In a medical, banking or shop document such a line is still covered, but
    marked to check (`:2096-2101`). That is the "zu prüfen" seen.
  - The address block under it and the birth date on its row say plainly
    that it is a person, but neither counted as vouching.
- **The same rule covered the side column's headings.** "WEITERER STANDORT"
  and "IN HAMBURG" are two capitalised words each, so they are shaped like a
  name. In a medical letter they were covered and marked, under any name
  kind.

### 3.6 The house number left visible

- A hit covers its `range` (`area(of:in:)`, `:910`).
- The model's hit was the words it wrote, "Schleusberg", so the cover ended
  there.
- No step widened a hit to the whole entity: the street with its number,
  the postcode with its town, the whole name, the whole number.

### 3.7 How "Namen" works with the two kinds under it

- In Settings (`SettingsView.swift:39`, `SettingsWindow.swift:1682`), with
  Namen on, Patientennamen and Weitere Personen show as on and cannot be
  changed. Namen already covers everyone's names, theirs too.
- With Namen off, each of the two can be on or off by itself.
  `resolved(_:)` gives:

| Namen | Patientennamen | Weitere Personen | Names covered |
|---|---|---|---|
| on | either | either | everyone's |
| off | on | off | the patients' |
| off | off | on | doctors, customers, staff, payees, senders, recipients |
| off | on | on | both, so everyone whose role is known; an unclear one covered and marked |
| off | off | off | none |

- **Every valid combination can be chosen**, including "patients' names
  only". Nothing blocks one.
- What is unclear is the way there: a customer has to know to turn Namen off
  first. The text under the group says it ("Ohne „Namen“ …"), but only at
  the end of the group.
- **The smallest fix,** not made, as the settings screen changes only with
  the owner's approval: one line under Namen, "Aus, um nur bestimmte
  Personen zu wählen", in the 13 languages. Nothing else on the screen
  changes.

## 4. The fix

What changed, by the rules in the report.

### 4.1 One kind per place, and a deterministic gate after classification

- Every hit still carries one kind; a name's role picks between
  Patientennamen and Weitere Personen.
- `Finder.allowed(_:_:)` is the last gate. It keeps a place only if its kind
  is on, or if it is one of the owner's own rules. It runs on everything
  found, pattern or model alike: in `analysis` for every copy and editor, in
  `stillReadable` for the second reading, and in `reading(of:)` for Copy
  Text.
- The printed contents of a code take the code's kind, so the gate keeps
  them exactly when the code itself is covered.

### 4.2 The model never decides alone

- `Finder.vetted(_:in:_:)` reads every row of the model's answer again,
  deterministically, by its kind (`Finder.fit`):
  - **A name:**
    - one to five words shaped like a name;
    - no digit;
    - no company;
    - no medical term;
    - not the street or the town of a line that is an address;
    - not the place before a letter's date ("Hamburg, den …");
    - not a place after "in", "aus" or "nach".
    - One word alone, or a line in capitals, is only offered, "zu prüfen".
  - **An address:** a street with its number, a postcode with its town, or a
    line that is one. A town alone is no address.
  - **A date of birth:** a date.
  - **An email:** an email.
  - **A phone number:** six digits or more, and nothing but a number's signs.
  - **Bank details:** an IBAN, a BIC, or eight digits or more.
  - **An ID or a code:** letters and digits holding a digit, never a date
    alone and never a medical term.
  - **A key:** a run of 16 characters or more.
  - **A username:** one word.
  - **Health details:** any words, but not a date or a number alone.
- What does not fit is dropped.
- What only may fit is offered "zu prüfen", and only for a kind that is on.
  So it is never covered silently.

### 4.3 Medical content is never a name or an ID

`DocumentSense.medicalRanges(in:medical:)` finds:

- the spine's segments: "LWK 5/SWK 1", "L5/S1", "HWK 6", "Th12";
- nerve roots: "S1-Wurzel";
- diseases named after a person: "Morbus Scheuermann", "Bechterew-Syndrom";
- ICD codes: "M51.2".

No name, ID, order, code, tracking, bank or phone place may overlap one.
Health details may.

- `decided` drops such a place, whatever found it.
- `fit` drops a model's, and looks at the line above too, for "Morbus"
  ending one line and "Scheuermann" starting the next.
- Long nouns of findings, like "Bandscheibenextrusion" or
  "Lumboischialgie", are no name's words.

### 4.4 Names a document vouches for are sure

- A line shaped like a name is vouched for by:
  - the street or the postcode and town under it, as a letter's address
    writes them;
  - a date of birth on its row or the line under it.
- A line in capitals that nothing vouches for is offered, not covered. A
  letterhead writes its headings so. The Natural Language tagger alone does
  not vouch for words in capitals either.
- A line with "in", "im", "am", "auf", "aus", "für", "und", "mit", "nach",
  "vom", "zum", "zur" or their English kin is not a name.

### 4.5 The owner's own name

- `Finder.ownNames(in:)` takes the owner's word rules that are shaped like a
  person's name: two to five name words, no digits, no company. It uses them
  to recognise that name:
  - in any order;
  - in any case;
  - with commas;
  - split across lines;
  - with one letter misread in a word of five letters or more.
- Such a name is a sure name, never "zu prüfen" for being unsure. Where its
  role is unclear, it is the subject of the document: the patient in a
  medical letter, the customer on an invoice. So it is covered whenever a
  name kind that covers that person is on.
- It never narrows what is covered, and it does nothing with no name kind on.
- The rule itself still covers its exact words whatever is on, as the
  owner's own rules always have (R11).
- It stays on the device. Nothing logs it, and it is sent nowhere it was not
  sent before: the rules are kept in Settings and shared with the share
  extension, as they always were.

### 4.6 The whole entity

`Finder.wholeEntity(_:kind:in:)` widens every place:

- to whole words and numbers, never part of one;
- for an address, to the whole street with its number and the postcode with
  its town, on that line;
- for a model's place:
  - to the whole run of the name;
  - for a number or an email, to the whole match of its kind's pattern.

The cover's margin (`withMargin`) is unchanged.

## 5. Tests

`Tests/TendederoTests/CategoryFidelityTests.swift` holds 19 tests, on the
made-up letter, a short note and a made-up model answer.

| What | Test |
|---|---|
| Each kind alone covers nothing of another kind | `testEachKindAloneCoversNothingOfAnotherKind` |
| All off | `testWithNothingChosenNothingIsCovered` |
| All on | `testWithEverythingChosenTheLettersDetailsAreCovered` |
| The reported settings | `testTheReportedSettingsCoverTheNamesAndNothingElse` |
| Namen alone | `testNamesAloneCoverEveryonesNameAndNothingElse` |
| Patientennamen alone | `testPatientNamesAloneCoverThePatientOnly` |
| Weitere Personen alone | `testOtherPeopleAloneCoverTheDoctorsNotThePatient` |
| Namen covers what the two cover together | `testNamesCoverWhatBothOfItsKindsCoverTogether` |
| Own name saved, in seven forms, under Namen and Patientennamen | `testTheOwnNameIsASureNameHoweverItIsWritten` |
| Own name never covers without a name kind, never narrows | `testTheOwnNameOnlyHelpsAndNeverCoversWithoutANameKind` |
| A short word of it in small letters stays a word | `testAShortWordOfTheOwnNameInSmallLettersIsJustAWord` |
| Own name not saved | `testWithoutASavedNameTheNameIsStillCovered` |
| Which rules count as an own name | `testOnlyANamesWordRuleIsTheOwnersName` |
| A model's "name" for a street, town, date, reference, segment or heading | `testAppleIntelligenceCannotCoverWhatItsKindDoesNotFit` |
| A model's answer checked for every kind | `testAModelsKindIsCheckedForEveryKind` |
| The whole entity | `testAPlaceIsCoveredWhole`, `testNoHouseNumberIsLeftBesideACoveredStreet` |
| No medical term as a name or an ID | `testNoMedicalTermIsCoveredAsANameOrANumber`, `testMedicalTermsAreFound` |

The own name's seven forms:

- "Erika Musterfrau";
- "Musterfrau, Erika";
- "ERIKA MUSTERFRAU";
- "erika musterfrau";
- split over two lines;
- "Erlka …", a misread letter in a five-letter word;
- "… Musterfrav", a misread letter in a long word.

## 6. How this was run

There is no Mac here.

### On Linux

The engine's text half builds in a harness outside the repository
(`/tmp/…/scratchpad/harness`):

- the real files `PrivateText.swift`, `DocumentSense.swift`,
  `FormFields.swift`, `OwnRules.swift`, `Protection.swift`, `FirstRun.swift`,
  `Localization.swift`, without the imports Linux lacks;
- stand-ins for Vision, Core Graphics, the data detector and the Natural
  Language tagger. They read no picture and find nothing on their own.

Swift 6.1.2 from swift.org, in Swift 5 mode, as the app is built.

```
./make.sh RedactionTests DocumentSenseTests FormFieldsTests CategoryFidelityTests FirstRunTests
swift test
```

**Before the fix:**

- The 59 tests of `RedactionTests`, `DocumentSenseTests` and
  `FormFieldsTests` passed.
- The letter gave the output in section 2.

**After the fix:** 96 tests, 0 failures.

| Suite | Tests |
|---|---|
| `CategoryFidelityTests` | 19 |
| `RedactionTests` | 36, one of them new |
| `FirstRunTests` | 17 |
| `DocumentSenseTests` | 13 |
| `FormFieldsTests` | 11 |

Three more runs checked the tests themselves:

- **With the fix taken out again** (the model's answer not checked, the
  letter's layout not vouching, the own name not looked for), four tests
  failed, with six failed checks, as they should:
  - `testAModelsKindIsCheckedForEveryKind`;
  - `testAppleIntelligenceCannotCoverWhatItsKindDoesNotFit`;
  - `testTheOwnNameIsASureNameHoweverItIsWritten`;
  - `testTheReportedSettingsCoverTheNamesAndNothingElse`.
- **With a tagger that calls names, and things that are none, personal
  names** ("WEITERER STANDORT", "Mediale Bandscheibenextrusion",
  "NORDTOR Lindenplatz"):
  - Before the last two changes, four tests failed, with five failed
    checks. The two changes: capitals are not vouched for by the tagger
    alone, and the findings' long nouns are no name's words.
  - After them, all 96 passed.
- **The stand-in tagger, which tags nothing:** all 96 passed.

Not run here: tests that draw a picture and read it with Vision (for
example `ProtectionTests`, `LabelTests`, `PrivateDetailTests`).

### On macOS

CI's `swift test` runs every test, with the real Vision, data detector and
tagger. Its result is in the pull request.

## 7. Not verified here

- **On a real iPhone with Apple Intelligence.** A screenshot of the letter
  covered with only the name kinds on. Expected:
  - only names covered, in full, the house number too;
  - the side column's headings not covered;
  - the patient's name sure if it is saved as a word rule.
- **What the device's model answers for the real letter.** Vetting makes
  that answer matter less, but this was not tested on a device.

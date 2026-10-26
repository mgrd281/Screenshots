# The scan's text, from capture to export

What cleaning does to small grey print and to an umlaut's dots, what was
changed, the guard that keeps what a line says, and what is verified. Parts A
and B of the brief "Schrift" (October 2026); part B is built in stages
(below), part C ("Neu gesetzt") is not built. Last, Reading: the text in
reading order, as Text in Save and Share and in the PDF, in every script.

Everything here is measured on made-up letters. No real letter, name or
health detail is in a test, a picture or a log.

## The problem

A photographed A4 letter with a column of small light-grey print down the
right (about 7 pt, partly blue headings) came out of Scan with the grey print
thin, broken and jagged, and the umlauts' dots gone: "Ärzte für Radiologie"
read "Arzte fur Radiologie". The large black body text was fine.

## The audit

### How it was measured

`scratchpad` scripts (not in the repository) render a made-up A4 letter at
600 dpi with real fonts. The letter has a right column of 7 pt print in 55 %
grey, blue bold headings, an e-mail line, an IBAN-like number and words with
ä, ö, ü, ß and É. The renders are degraded like a phone photo: blur, the
page's share of a 12 MP photo, a warm lamp from one corner, a fold, grain and
JPEG. Each of `ScanClean`'s steps then runs on Linux, built from the
repository's own files, and the page is kept after each step.

There are two photos:

- **Medium:** Liberation Sans at 275 dpi with light blur.
- **Hard:** a light face (Inter Light) at 200 dpi, softer and grainier. This
  is the case that loses dots, as the real letter did.

The truth of where each diacritic is comes from rendering each line with and
without its accents.

The measures are:

- **Dot darkness:** how far under its line's paper a diacritic's three
  darkest pixels lie, of 255, and its share of the line's strokes. "Seen"
  means at least 40 levels and at least half of a stroke.
- **Darkest 30 %:** the middle of the darkest 30 % of the pixels in each
  grey line's box. The brief's target is 70 or darker.
- **Stroke:** the mean width of the grey strokes, as at 300 dpi, and how much
  it varies along a line.
- **Hue:** the blue headings' hue. Printed at 211°.

### What each step did, on main (hard photo)

| Step | Dots seen | Dot darkness | Dot / stroke | Grey darkest 30 % | Body darkest 30 % |
|---|---|---|---|---|---|
| photo | 0 / 22 | 28.4 | 0.54 | 164 | 100 |
| evened | 0 / 22 | 20.8 | 0.40 | 214 | 122 |
| denoised | 0 / 22 | 17.6 | 0.35 | 214 | 125 |
| faint print (strengthened) | 2 / 22 | 24.5 | 0.30 | 191 | 125 |
| sharpened | 2 / 22 | 32.8 | 0.35 | 182 | 110 |
| darkened (curve) | 2 / 22 | 52.5 | **0.26** | 104 | 0 |
| final | 2 / 22 | 52.5 | 0.26 | **104** | 0 |

On the medium photo, main kept the dots (21 of 22 seen, a share of 0.62).
The grey print stayed at 95 to 121, lighter than the 70 the brief asks for.

### What erased the dots

The camera halves a small dot's contrast first: in the hard photo a dot is a
little over half as dark as a stroke (0.54). Cleaning then took away more,
in three places:

1. **Evening the light** took each pixel as its share of 95 % of the paper.
   Everything within 5 % of the paper became white. That is the paper's
   grain, but also a faint dot's rim and much of its core (share 0.54 → 0.40).
2. **Smoothing the grain** averaged anything within 10 levels of its
   neighbours, which took a little more off a dot's rim (0.40 → 0.35).
3. **The curve** made everything under the raised black point black (0.50
   on this page, from the median darkness of all the text read). It is
   steep, so strokes went black while the lighter dots stayed light grey
   (0.35 → 0.26). At a phone screen's scale those dots vanish. The same
   steep curve made the grey print blotchy where strokes cross ("broken and
   jagged"). It also crushed the black body text to 0.

Speck removal and morphological opening, which the brief asks about, are not
in the colour pipeline. Its only threshold is in black and white.

## What changed

Text boxes come from Vision's reading of the flattened page before cleaning,
as before (`ScanCleaner.finished`). Each box is grown by 30 % of its line's
height (`ScanClean.printLines`).

- **Which print is light** (`ScanClean.lightPrint`), judged on the page as
  photographed, box by box:
  - its darkest print, as it would be on white paper, lighter than 100;
  - lighter by 40 levels or more than the page's own dark print (the darkest
    quarter of its lines). A grey column beside black text counts; black
    text that a soft photo left grey does not. On a faded page, whose dark
    print is itself lighter than 140, all of the print counts;
  - neutral once the paper's colour is divided out. A blue heading, a form
    printed in colour and a ballpoint do not count.

  Everything else is cleaned exactly as on main. Where text was read, a
  stroke still never takes a fold's finer light, as on main, whatever its
  shade.
- **The paper is still taken at 95 %** of itself inside light print. The
  first version took it at its own level there, to keep a faint dot's rim;
  that moved a ruled line at the sick note's fold by 0.017 px and is gone
  (below). The toning starts from the evened page, so the dots are kept
  either way; 3 fewer of the hard photo's 22 are "seen".
- **Less smoothing inside light print** (`Tuning.textGrain = 4`): grain
  within 4 levels, not 10.
- **Light print toned line by line** (`ScanPrint.swift`, `ScanClean.toned`).
  Each line is measured in windows four line heights wide: its paper (90th
  percentile), its darkest ink (1st), the grain where no print is near, and
  the ink's colour.
  - **How:** each pixel is darkened by the same share of how far under the
    paper it lies, so a dot is darkened as much as the stroke beside it. The
    ink is taken to 6, at most five times as dark, with the page's gamma.
    Print on a grey fill (paper under 240) is left to the page's curve.
  - **A thin light face** (`ScanClean.drive`): where the body of a line's
    ink, its darkest tenth, would still be lighter than 80, the whole line
    is taken further, up to twice. The strokes' soft edges then come out
    dark as well as their middles: a light face at 7 pt reads a little
    bolder, as dark as the body beside it. A line dark enough already is not
    taken further.
  - **Small marks:** first made as clear as the strokes. An unsharp mask of
    the eight pixels round each, 1.4 times.
  - **The paper's grain:** within 2.5 times its spread of the paper it turns
    white. Near the paper, the mean of the nine is used, so no speck is
    taken darker.
  - **No seams:** windows blend into each other and over the line's edge.
  - Nothing is drawn or moved.
- **The guard** (`ScanCleaner.guarded`, `ScanContent.changed`,
  `ScanContent.says`): the cleaned page is read again. A line read before
  with confidence 0.9 or more, of three letters or more, must still read
  with every character in the same order on its row, each with at least the
  marks it had. Spaces do not count, and a dash or a centred dot may be read
  as another of its kind.
  - **A mark gained is not a change.** Where the photo left an umlaut's dots
    too faint and the reading before said "Arzte", "Ärzte" after cleaning is
    the print made clearer: cleaning only makes pixels darker or lighter and
    never draws a mark. The first guard took the reading before as the
    truth and undid exactly these lines (below). Not over an i or a j: their
    own dot, made darker, was read once as an accent ("praxís").
  - **A line that reads otherwise** is cleaned again and the whole page read
    once more: light print gently (ink at most twice as dark, nothing
    sharpened, not taken further), dark print, which is never toned, as the
    evened page has it within its own box. A line that still reads
    otherwise goes a step further, light print to the evened page and the
    page is read once more; where even that does not bring its reading
    back, the reading differs and not the cleaning, and the line stays as
    cleaned. A line is never judged on a crop of its own: the second Mac run
    showed Vision reads "Rückfragen" alone and "Rückíragen" on its page.

  A dark line is never cleaned again gently, and goes back to the evened page
  within its own box only, without the 30 % margin, so no ruled line beside
  it moves. (Leaving dark lines unguarded let a body line read "Rückíragen".)

  What the guard did is logged ("Cleaning changed the reading of N lines…")
  and kept with the page (`Prepared.guarded`) for the tests. Black and white
  is not guarded: it is two values only, and its menu already says it can
  lose a mark too pale to tell from the paper.

## Results (lab, Linux)

Three made-up photos. The medium and hard ones are drawn as in the audit.
The third is drawn as the Mac's test letter is (`ScanSample.textLetter`):
crisp print in a light face (Inter Light standing in for Helvetica Light)
at 200 and 150 dpi, made about 1.4 and 1.9 times larger as the photo and
the straightening make it, a warm lamp and a little grain.

| Photo | Pipeline | Dots seen | Dot / stroke | Grey darkest 30 % (median, worst line) | Stroke at 300 dpi, variation | Blue hue |
|---|---|---|---|---|---|---|
| hard | main | 2 / 22 | 0.26 | 104, 123 | 4.0 px, 10 % | 211.1° |
| hard | new | 13 / 22 | 0.54 | 14, 22 | 4.6 px, 9 % | 211.1° |
| medium | main | 21 / 22 | 0.62 | 95, 121 | 3.3 px, 11 % | 211.3° |
| medium | new | 22 / 22 | 0.86 | 24.5, 30.5 | 3.7 px, 11 % | 211.3° |
| Mac-like, 200 dpi | main | – | – | 136, 193 | 2.4 px | – |
| Mac-like, 200 dpi | new | – | – | 6, 43 | 3.4 px | – |
| Mac-like, 150 dpi | main | – | – | 129, 176 | 2.5 px | – |
| Mac-like, 150 dpi | new | – | – | 6, 6 | 4.0 px | – |

- The darkest 30 % is taken in the box round each line's own ink. In a box
  as tall as the font's ascent and descent, with paper above and below, the
  Mac-like letter's worst line at 200 dpi is 110 and the median 34.
- No dot is lost on either photo: every one is at least 25 levels under its
  paper. "Seen" asks more, half as dark as its stroke; the six hard-photo
  dots short of it are still over 100 levels dark.
- Specks: paper pixels darker than 230 away from the print, near the grey
  lines, at most 7 in 10,000 (hard photo).
- The dots of the Mac-like letter are not counted (it has no truth of where
  each dot is), but its crops show every one.

Measured with `scratchpad/schrift/measure.py`, `stroke.py`, `dark.py` and
`speck.py`, after `swift build -c release` and the step runners in
`scratchpad/lab4` (this branch) and `scratchpad/lab4main` (main).

The new grey print is bolder than the light face it was printed in: its soft
edges are darkened with its strokes, and a thin face is taken further. The
strokes vary 8 to 11 % along a line, under the 25 % allowed.

Every scan test that runs on Linux passes, 73 of them: `ScanCleanTests`,
`ScanContentTests`, `ScanGeometryTests`, `ScanInvoiceTests`,
`ScanInvoiceFixtureTests`, `ScanLetterTests` and `ScanPrintTests`. Command:
`swift test` in the lab. The letter's dark body is as on main (strokes ×1.11,
main ×1.09; the first version of this change had ×1.17, toning a soft photo's
black text as light print).

## On the Mac, through Vision (CI)

`ScanTextFixtureTests` draws the same kind of letter with Core Text
(Helvetica Light, 7 pt, 55 % grey), at 200 and 150 dpi. It photographs it
(`ScanSample.photographed`), makes it ready as the Scan tab does and reads it
before and after cleaning. It checks:

- every line read surely and as printed before reads as printed after, and
  the letter as a whole reads no worse (the guard's promise);
- at 200 dpi, the body reads as printed and the grey column 99.5 % of its
  characters (the brief's target);
- each grey line's darkest 30 %, in the box round its ink, at 70 or darker
  (Vision's own box is printed beside it), and the blue within 10°.

Its numbers, what each line was read as and what the guard did go to
`scan-text-200.txt` and `scan-text-150.txt`, and its crops (column, umlauts,
e-mail, blue, digits; before and after; 100 % and 300 %) to the
`scan-captures` pre-release, through Scan Checks.

### The first run on the Mac, and what it showed

The first version of this change, on a macOS runner (debug build):

- **Body:** read as printed at 200 and 150 dpi.
- **Grey column, 200 dpi:** 99.0 % of characters right, not 99.5 %. The three
  lines read wrong after cleaning were read wrong before it too, "Ärzte"
  among them.
- **Darkest 30 % of the grey lines:** 71 to 202, not 70. The lightest lines
  (about 200) were the ones Vision misread before cleaning.

Two causes, both fixed above:

1. **The guard trusted the reading before.** Where Vision missed a dot in the
   photo, the cleaned line, dots and all, read "otherwise", so the guard put
   the line back as evened: light grey, as photographed. A mark gained now
   counts as clearer, and a line is only put back where that brings back the
   reading.
2. **A thin light face stayed thin.** The toning took each stroke's middle
   to black but kept its soft edges grey, so in a box with paper round it
   the darkest 30 % was mostly those edges. The lab letter drawn like the
   Mac's showed the same (136 on main, 86 with the first version). The line
   is now taken further where its ink's body stays light.

The test was briefly loosened to pass that run; it now asks for the brief's
targets again.

### The third run

At 200 dpi the guard found "Rückfragen" changed, read the line again on a
crop of its own, found it right, and left the page as it was: Vision reads a
line differently alone than on its page. The guard now reads the whole page
again after cleaning a line again, and never trusts a crop.

### The sick note's fold

The made-up sick note's step at the fold stayed at 2.0154 px, past the 2 px
main keeps, on every run. A diagnostic test cleaned its straightened page
again with the light print's rules turned off one by one (the Mac, 3
runs):

| Rules | Step |
|---|---|
| everything | 2.0154 |
| toning off | 2.0154 |
| paper at 95 %, smoothing at 10 (both off) | 1.9983 |
| paper at its own level only | 2.0163 |
| lighter smoothing only | 1.9971 |
| paper at 97.5 %, lighter smoothing | 2.0025 |

So neither the toning nor the guard moves the line. The paper at its own
level does, by 0.017 px, on a sheet whose print the lamp makes light
throughout (all 40 of its lines count as light print); the lighter
smoothing does not. Limiting it to pixels as light as a light mark did not
help: the sheet's pink rules are light. The paper at its own level is gone,
and the diagnostic with it. **Not verified:** that the step is under 2 px
again; the test runs on the Mac only.

### The second run

With those two fixed (darker drive, up to a body of 60):

- **Darkest 30 % of the grey lines:** 6 in every line, at 200 and 150 dpi,
  in the box round the ink; 6 to 46 in Vision's own box.
- **Grey column, 200 dpi:** 99.75 %. Only "Ärzte" still read "Arzte", as in
  the photo.
- **At 150 dpi** the umlauts the photo hid were read after cleaning ("Ärzte",
  "Übrige", "Musterwall 7a · 20354"), but two lines were read worse:
  "praxis@" as "praxís@" (an i's dot made darker read as an accent) and an
  "f" of "Öffnungszeiten" as "i".
- **At 200 dpi** one body line read "Rückíragen". The body is dark print,
  but that version evened it without main's rule that a stroke never takes
  a fold's finer light; main's rule is back.

So the line's body is now taken to 80 rather than 60, a little less bold,
and an accent read over an i is a change the guard acts on. A line the
guard cleans again is reported by the darkness test rather than held to 70:
what a line says comes first. The time per page was about 150 s in a debug build on a CI
runner, which says nothing about an iPhone 15.

## Not done in this part, and why

- **Upscaling before thresholding (step 3):** colour and greys have no
  threshold any more, since the toning is linear. Black and white still
  thresholds at the page's own resolution. Not changed.
- **Thickening thin strokes (step 6):** no stroke is grown. The grey strokes
  measure 3.6 to 5.2 px at 300 dpi on every photo, well over 1.5; a thin
  light face comes out bolder only by its soft edges being darkened
  (`ScanClean.drive`).
- **300 dpi output (step 9):** the PDF already draws each page at about
  300 dpi (`ScanGeometry.printScale`). The cleaned page itself stays at the
  photo's resolution, so the time per page does not grow. Pictures saved as
  PNG keep that resolution.
- **Speed on an iPhone 15:** not measured, as there is no device here. On
  this Linux machine the whole cleaning of a 2274 × 3215 page takes about
  6 s, single-threaded. The toning itself takes 0.03 s.

## Not verified

- **Vision on the Mac, for this version:** recognition after cleaning, the
  guard's fallbacks on real readings, and the 200 and 150 dpi numbers come
  from CI, not this machine.
- **On a device:** how the owner's own letter comes out, and the time per
  page.

## Part B: capture with enough detail

### Where it stands

Scan Document opens the system's document camera
(`VNDocumentCameraViewController`). Snapfly cannot choose its resolution,
take a burst, check the preview or say a hint while it is open. Part B
therefore needs a camera of Snapfly's own, built in three stages, each
merged on its own:

1. **The engine, on Linux.** Merging a burst, the readiness check on a
   preview, and the readability score with its hint in Review.
2. **The camera** (`PageCamera`, a test in More › Detection, off at first):
   the full photo size with quality first, the preview checked ten times a
   second, the page taken by itself when ready, one hint at a time on
   glass, the burst merged. Below.
3. **The detail shot** (`ScanDetail`, with the camera above): small print
   taken again close up and laid onto the page. Below.

### Several frames, one page (`ScanBurst`)

Each frame is laid over the sharpest one by a shift and a slight turn,
found first by trying every shift within 4 % of the page and every turn
within 1.5° on frames made small, then step by step down to a twentieth of
a pixel at the print's steepest edges. Frames less sharp than 80 % of the
sharpest, frames that still differ once laid over, and a frame with a
reflection the others have not are left out. The merge takes, for each
pixel, the mean of the values close to an anchor: on the print's edges the
sharpest frame's own value, elsewhere the middle of all frames, so the
grain is averaged away and a reflection or a speck in one frame does not
count. Frames are drawn with a cubic curve, which keeps an edge's
steepness.

Made-up burst (`ScanBurstTests`): rows of 7 pt-like letters, four frames
shifted by up to 6 px and turned by up to 0.4°, softened like a lens
(Gaussian 0.8 px), grain of 5 levels:

| | Sharpest frame alone | Merged |
|---|---|---|
| Difference from the printed page (root mean square) | 5.02 | 3.26 |
| Edge steepness where the printed page's are steepest (printed: 79.8) | 80.1 (grain adds to it) | 79.5 |
| A frame shaken by 7 px | – | left out |
| A reflection in one frame | – | gone |

The frames are laid over each other to within 0.25 px and 0.06°
(`testFramesAreLaidOverEachOtherToAFractionOfAPixel`).

**Not verified:** a burst from a real camera; the time on an iPhone (the
merge is written in plain Swift for the tests; the camera will need the
same done with Core Image or vImage to stay within 2.5 s). A comparison of
Apple's single best shot (`.quality`) with this merge needs the camera.

### Ready to take the page (`ScanReadiness`)

Measured on a preview: the sharpest line of text's focus (how steeply its
edges turn against how far they turn within three pixels, 0.35 and more),
the phone still for 0.3 s, the smallest line's x-height at least 16 px in
the full photo (a line read is about twice its x-height), and the paper
without a reflection (1 % of it white out). Ready when all of these hold;
otherwise one hint, the most important first: Ruhig halten, Näher ran,
Spiegelung, Handy leicht kippen, Mehr Licht, Linse reinigen.
`ScanReadinessTests` checks each on a made-up preview. A shake that smears
thin strokes leaves their edges steep and takes their darkness, so motion
is told by the phone's stillness, not the picture.

### Readability score (`ScanReadability`)

The lines up to 1.3 times as tall as the shortest line of a few letters are
the page's small print; the score is the mean of how sure Vision was of
them. Under 0.9, Review shows "Kleine Schrift unscharf" with Näher
aufnehmen (a scanned page: the camera opens to take it again) or Neu
aufnehmen für kleine Schrift (a photo). `ScanReadabilityTests` checks it.
**Not verified:** how often real pages get the hint.

### The camera (`PageCamera`)

Switched on with Schärfere kleine Schrift (Test) in More › Detection; Scan
and Review's Take Again open it instead of the system's document camera.

- **Lens.** The back camera that switches lenses by itself (triple, dual
  wide, dual), so it moves to the close-focus lens near a page; else the
  wide one. Its closest focus is written to the log.
- **Size and quality.** Photos at the largest size the photo format offers
  up to 24 MP (48 MP would take four times the memory and time per page),
  quality first, never the flash.
- **Focus, exposure, white.** On the page's middle as Vision finds it, set
  again when the page moves; the white balance is kept once the page fills
  a third of the view and the phone is still.
- **Readiness**, ten times a second on the preview (`ScanReadiness`): the
  page and its lines of text from Vision, the brightness at about 640 px,
  stillness from Core Motion (still while it turns less than 0.12 rad/s and
  moves less than 0.04 g), and from iOS 26 a smudged lens every 2 s. A hint
  shows once it held for 0.4 s, VoiceOver reads it, and a light tap says
  ready. The page is taken by itself once ready, then again only once the
  page leaves the view or lies elsewhere. The shutter takes it by hand at
  any time. The torch (at 15 %) is a button at the top.
- **Several frames or one.** Where the photos are no larger than 12 MP, four
  frames at the same exposure are merged (`ScanBurst`); larger, one photo
  of the best quality, which the iPhone itself makes of several. The frames
  stay in memory only.
- **Its pages** are whole photos: the page is found in them as in a photo
  from Photos, and the smudge check reads the photo.

Its timings (taken, made) are written to the log.

**Not verified:** all of it on an iPhone. The build compiles it; nothing
here has run on a device. The 2.5 s from shutter to cleaned page, the
comparison of Apple's single best shot with the merge, and the hints'
thresholds on real paper need the owner's iPhone:

### The detail shot (`ScanDetail`)

With the camera on, Näher aufnehmen on "Kleine Schrift unscharf" in
Review's list opens it for a close-up instead of taking the page again: a
card "Kleine Schrift näher aufnehmen" over the preview, no whole page needed
in view, the letters 24 px tall at least, and it closes once taken.

The close-up is found on the straightened page around the small print's
place: every size from 1.2 to 4 times as large (each 8 % more than the
last) and every turn of −3° to 3° on both made small, by how the print's
steepest edges correlate; the best four closer; then the best on the page
itself, step by step down to 0.05 of a pixel. It is laid only where it
matches with a correlation of 0.6 and more. Its light is brought to the
page's by the paper and the mean, which a soft page keeps as a sharp one
has it; it is made as small as the page, each colour apart, and fades in
over 12 px. The page is then cleaned and checked again, and kept only where
its small print reads more surely, by 0.02 of Vision's certainty at least,
with no line or letter fewer (`ScanDetail.better`); otherwise the page stays
as it was and a note says "Detailaufnahme nicht übernommen".

Made-up close-up (`ScanDetailTests`): a page of small print, its lens soft
(Gaussian 1.6 px), and a close-up 2.4 times as large, turned by 0.6°, lit
darker, with grain:

| | Measured |
|---|---|
| Found off by, at the small print's corners and middle | 0.30 px (target ≤ 1 px) |
| Size found | 2.399 (taken at 2.4) |
| Difference from the printed page inside the small print | 11.5 before, 9.4 laid |
| Edge steepness there (printed with a lens of 0.8 px: 77.5) | 30.9 before, 109.6 laid |
| A close-up of other print | not laid |

The page's synthetic print picks each letter's shape and width by a hash of
its place, as real text has no repeating stretch; a print that repeats
exactly can be matched a few letters off, which the correlation threshold
and the reading check are there to catch.

**Not verified:** a real close-up. A close-up taken at a slant (not flat
over the page) is laid by size, turn and place only, not perspective.

### On the iPhone (for the owner)

Switch on Schärfere kleine Schrift (Test) in More › Erkennung, then scan a
made-up page with small print (the first run's sample invoice printed, or
any printed page without private details) in each of these:

1. **Normal light**, held at a comfortable distance: the page is taken by
   itself within a few seconds, without a hint.
2. **Dim light** (one lamp across the room): "Mehr Licht" shows; the torch
   button helps.
3. **A lamp at an angle** making a shine on the paper: "Spiegelung, Handy
   leicht kippen" shows, and goes once the iPhone is tilted.
4. **A shaky hand**: "Ruhig halten" shows, and nothing is taken until the
   iPhone is still.
5. **7 pt print at arm's length**: "Näher ran" shows until the letters are
   large enough; then it is taken, and Review shows no "Kleine Schrift
   unscharf".

6. **The detail shot**: on a page whose Review says "Kleine Schrift
   unscharf", tap Näher aufnehmen, hold the iPhone close over the small
   print: it is taken by itself, and a note says whether it was used.

For each, say whether the hint was right and how long it took from the
picture to the cleaned page.

## Reading: the text in order, in every script

What a scan says, as a person reads it: copied, kept as a TXT file, heard,
and found in the PDF. October 2026.

### What was wrong

- The lines came in Vision's order, top to bottom across the whole page:
  two columns were read across each other, a letterhead's side column (the
  hours, the bank) broke into the letter, and a table's cells came one
  under another.
- Every line of print was a line of text: a paragraph came apart at each
  line's end, and a word broken there stayed broken ("Bildschirm-",
  "foto").
- The PDF's invisible words were in Helvetica's Western encoding. A word
  with a Turkish ğ, and every word in Arabic, Greek, Cyrillic, Chinese,
  Japanese or Korean, was left out, so it could not be found.

### Reading order (`ScanReading`)

The page is cut as a reader takes it in, by the gaps between its lines,
measured in the line's own height (the page's width to height kept):

1. **A letterhead down the side** comes off first: where white space runs
   down the whole of a part, wider than 1.2 lines, and one side is a column
   of words (not numbers) set at most 0.7 times as tall as the print beside
   it, each side three lines or more, the sides are read one after the
   other, from the reading side. So a letter's text is not cut band by band
   with the letterhead beside it.
2. **Bands**, across the page, where the gap between two lines is
   wider than 0.6 of a line, or than one and a half times the usual space
   between lines plus a quarter of a line. Only spaces under one and a half
   lines count as usual, so the space between blocks does not widen it, and
   1.5-spaced paragraphs stay whole.
3. **Then columns**, down a band, where a gap is wider than 1.2 lines.
   An **address** first among them (two to six lines, the last a postcode
   and a place: "20095 Hamburg", "D-20095 Hamburg") shares no table's rows
   with what stands beside it: it is read whole, then the rest, as a
   letter's details beside its address are.
4. Columns side by side are **a table** when at least 75 % of their rows
   reach into two or more of them, no column is prose (four lines or more
   with half of them 30 characters or longer) and no column after the
   first names its own value ("Datum: 14.10.2026", as the details beside a
   DIN 5008 address do). A table is read row by row, its cells parted by a
   tab. A single row across columns is one line.
   **Cells set close**, as a receipt's items and the prices Vision reads
   apart from them, are a table too: two lines or more of cells, a corridor
   of white at least 0.4 of a line down them, numbers in a column. Among
   lines that are not cells (the shop's address over the items) they are a
   band of their own.
5. What is left is cut into **paragraphs**: a new one where the print's
   size changes more than 1.3 times, or after a short line ending in ".",
   "!" or "?". A paragraph's lines run on when it is at least 0.45 of the
   page wide or half its lines hold 32 characters, and 70 % of its lines
   before the last fill 0.7 of its width; otherwise (an address, a list)
   each line stays a line. A line that names what follows ("Anwesend: …",
   "IBAN: …": up to three words from a capital to a colon) or is a number
   alone (a date, a time) never runs on. Short lines over a paragraph's
   first full one (a subject line, a salutation) stand on their own when
   three lines or more run on after them. One or two lines at least 1.3
   times as tall as the usual line, and as the lines around them, are
   **a heading**: a letter's closing set larger than its letterhead's small
   print is none.
6. A page mostly in Arabic or Hebrew letters is read **from the right**:
   its columns right to left, and so a table's cells.

A word broken at a line's end is **joined** where the lines run on:
"Bildschirm-" and "foto" are "Bildschirmfoto". A part of two letters keeps
its hyphen ("E-" and "mail" are "E-mail"), a part going on with a capital
keeps it too ("E-Mail"), and one before "und", "oder", "bis" and the like
keeps its space ("Haus- und Hofladen").

### Covers

Nothing under a cover is read. A word more than 5 % under a cover is
dropped, its line split there, and each cover is a mark of its own at its
place: "███" in the text, "verdeckt" read aloud. So the text says where
something is covered and nothing of what. A cover taller than two and a
half lines covers a picture (a photo, a signature) and is left out. With
covers, the text is read again on the covered pages; what was read on the
original is never used. Without covers, it is what was read on the cleaned
pages, under the warning.

### The PDF in every script (`ScanFont`)

The words are set in a font made for them, written byte by byte: TrueType,
624 bytes, two glyphs (an empty .notdef and a glyph without outlines),
each half an em wide. The PDF names it a Type0 font with Identity-H, its
glyphs a CIDFontType2 whose CIDToGIDMap draws every code with glyph 1, and
a ToUnicode map in which each two-byte code is the UTF-16 unit it stands
for (248 ranges, a hundred at most at a time, the surrogate halves left
out). Each word is written as its UTF-16 units, invisible (3 Tr), its size
its box's height, its baseline a fifth of that above the box's foot, and
stretched (Tz) to the box's width. Only a word with a character beyond
those units (an emoji) or a control character is left out of the text; it
stays in the picture.

**Right to left.** Arabic and Hebrew words are written in reading order,
each at its place. Apple's
PDFKit, which the iPhone's Files and the Mac's Preview read with, takes
them in that order (`testPDFKitFindsTheWordsInEveryScript`, on the Mac in
CI). Readers that turn right-to-left text round themselves, because most
PDFs hold it in the order it is drawn, show such a word backwards: on
Linux, pdftotext (poppler) and pypdf 6.17.0 do; pdfminer.six reads it in
order. Chrome's and Firefox's readers are said to do as poppler does (not
tried). Latin, Greek, Cyrillic, Chinese, Japanese and Korean read alike in
every reader tried.

### What it does with the text

- **Small print in columns is not a table.** Columns of words side by side
  are a table only if some column holds numbers (a digit and hardly a
  letter in at least 60 % of its cells, two cells at least) once the print
  is at most 0.8 of the page's usual line. A letter's foot (company, bank,
  court) is therefore read a column at a time, as it was set; an invoice's
  table in smaller print has its prices and stays a table. In ordinary
  print every candidate is a table as before, which keeps label and value
  pairs together ("Name  Lena Hoffmann"). Found by writing the layouts of a
  DIN 5008 letter, a bank statement, a contract, a form and an article
  down, not on a real document.
- **Cells Vision read as one line.** A line whose words stand a column's gap
  or more apart (1.2 of the larger of its own and the page's usual line)
  is parted there before the page is cut, so a table's row read whole can
  still be told from the columns; the parts of one row are read as the one
  line again where nothing else parts them.
- **Rows set far apart stay a table.** Invoices set with room or rules
  between their rows have gaps wider than any band gap, which cut each row
  out of its table. Three lines or more at an even pace, two of them in
  cells, that share a corridor of white running down through all of them
  are rows: the white between them is no band. The pace breaks where the
  space is more than twice its usual (an address and the table under it),
  and the rows end with the last line of cells.
- **A cell that wraps joins its row.** A line in one column that goes on a
  cell of the row above, nearer to it than the rows are to each other or
  starting in small letters ("inklusive Schulung"), is part of that cell. A
  title standing over its rows ("Hardware") is not.
- **Boxes that hug the letters.** Vision's boxes follow the letters: a line
  without a tail (g, j, p, q, y) is a fifth shorter than one with. The
  layout tests read every page twice, with boxes that fill the line and with
  boxes that hug it, and a paragraph of lines unlike in height stays whole.
  The size at which print counts as larger (1.3 times) is close to that
  difference; the CI log of `ScanReadingFixtureTests` shows what Vision's
  boxes really do, to set it by.
- **Unsure.** A line whose confidence is under 0.9 (`ScanContent.sure`, the
  guard's threshold) flags its words. They are washed in orange in the text,
  counted, and outlined on the page; nothing in the text is changed, copied
  with a mark or left out for it. Vision gives a confidence per line, not
  per word, so a flagged line is flagged whole. How often Vision gives less
  than 0.9 on a real page is what the first CI run of
  `ScanReadingFixtureTests` shows (it logs the confidences).
- **Corrections.** A paragraph or a cell is corrected by hand, against the
  part of the page it was read from. A correction is kept under the text
  as it was read, in memory with the scan: the same text is corrected the
  same again, another block with a different text never is, and the
  corrected text is no longer flagged. It is in the text that is copied,
  saved and shared and in the spoken text; it is not in the PDF's text
  layer, whose words keep the places they were read in. Typing the text
  as read again removes the correction; the menu undoes all of them.
- **Tables to a spreadsheet.** Copy puts the rows on the clipboard with
  tabs between the cells, which Numbers and Excel paste into cells. Share
  makes a CSV: RFC 4180 (a cell with the delimiter, a quote or a line break
  in quotes, quotes doubled, rows parted by CRLF), UTF-8 with its byte
  order mark so Excel reads the accents, a semicolon where this iPhone
  writes numbers with a decimal comma (as Excel's German list separator),
  else a comma. A cell that would run as a formula ("=...", "@...", "-A1",
  "+SUM(") gets an apostrophe in front; "-12,50" and "+49 30 1234" are left
  alone. A covered cell is "███".
- **Finding.** Letters are found whatever their case and accents ("uber"
  finds "Über"), in paragraphs and cells, in reading order; the matches are
  marked, counted, stepped through, and the view follows them. A cover is
  "███" and is not found by the words it hides, as they are not there.
- **Speaking.** The pages are cut into pieces: a paragraph, or a table's
  row, with a pause between. A cover is said as "verdeckt" (the app's
  language) and a line break or a cell's end is a comma's pause. The voice
  is the best one installed for the text's language (premium before
  enhanced before standard, the region of the iPhone first, simplified
  Chinese the mainland's); a paragraph of 24 characters or more whose own
  language the recognizer is 80 % sure of is said in that one. Where none
  is installed for the text's language, a note says so and nothing is said
  in another voice. The word being said is found in the shown text by a map
  from each spoken unit to the characters it stands for (tested on
  Linux, a cover included). Speed is 0.75 to 2 times the voice's own, kept.
- **Translating.** The system's own translation sheet (iOS 17.4), given the
  text as it is, covers as "███". It is Apple's, not Snapfly's: Snapfly
  sends nothing itself.

### On the iPhone

- **Save and Share** has a third format, Text ("TXT, 1 file"): Copy puts
  the text on the clipboard, Save keeps a .txt in Files, Share hands on a
  .txt file. Show Text opens it whole first.
- **Review's menu** has Show Text, for the page open, covered.
- **The text** (`ScanReadingSheet`): page by page, a heading larger, a
  table a grid with a menu, every word to select; the menu searches,
  corrects, translates; Seite shows the pages; Copy, Read Aloud with its
  player and Share. Read Aloud is the iPhone's own voice
  (`AVSpeechSynthesizer`), a cover read out as "verdeckt", other sound
  turned down while it speaks. Without covers, the warning comes first.

### Results

- **Linux**, `swift test` on the scan's files in a package outside the
  repository: `ScanReadingTests` 18, `ScanPDFTests` 12 and `ScanFontTests`
  5, all passing, with a check of the lab's own that writes a sample PDF.
- **The font**: fontTools 4.53.1 opens all eleven of its tables: two
  glyphs, both 500 wide.
- **A sample PDF** with "Rechnung", "Straße", "Grüße", "Doğan", "İstanbul",
  "مرحبا", "بالعالم", "Москва", "東京都" and "서울": pdftotext, pypdf and
  pdfminer.six find every word; the two Arabic ones as said above.
- **Strings**: `check-strings.swift` passes in all 13 languages.

### Checked on the Mac in CI, not here

- PDFKit finds every script, and a right-to-left word by search
  (`testPDFKitFindsTheWordsInEveryScript`); Core Graphics and Core Text
  open the font.
- Vision reads the made-up invoice in order, its items row by row, each
  with its price, and with the customer covered, a mark where the name was
  and the name nowhere (`testTheInvoiceReadsInOrderRowByRow`).
- On the simulator (Scan Checks): the Text format and the text from Save
  and Share and from Review, a bar where a cover is and never what it
  hides, and without covers the warning first (`ScanUITests`); frames of
  the text in light and dark, Arabic and English, at the largest text
  sizes, on the newest iPhone and the smallest.

### Also checked on Linux

- `ScanReadingToolsTests` 26: the unsure stretches (the text is the same
  with or without them, a joined word is unsure if a part was), where an
  unsure line lies, corrections (they land on the text they were made on and
  on nothing else, drop the unsure flag, keep the place, a cell stays one
  cell, an emptied block leaves the text), a table as tabs and CSV (quotes,
  CRLF, the delimiter, a cover cell, formulas defused, numbers left),
  finding (case, accents, Arabic, Cyrillic, Chinese, no overlap), matches in
  reading order, the speech pieces and the map from a spoken range back to
  the shown text (a cover, a pause, an emoji and an accent).
- `ScanReadingVisionTests` 5: what Vision gave on a Mac in CI for five
  made-up pages, each line and each word's box as the log has them, read
  in order here. A receipt whose prices Vision read apart from their items
  is a table; an invoice reads its address whole, then its details as a
  table of labels and values, its items and its totals; "IBAN: …" and
  "Telefon: …" stay lines of their own, and a page turned on its side
  reads its three lines as three; a letter with a letterhead of small
  print down its side reads its text through, then the letterhead.
- `ScanReadingLayoutTests` 12, each page read with filled and with hugging
  boxes: a DIN 5008 letter from the sender's line to its three-column foot,
  an invoice whose rows Vision reads whole, one whose rows are set far apart,
  one whose descriptions wrap under a title row, a bank statement, numbered
  clauses, a form, a headline over two columns, two columns whose paragraphs
  do not line up, a long paragraph of lines unlike in height, and a
  justified line that is not parted.

### Not verified

- Read Aloud on an iPhone: the voice, its language, the word marked as it
  is said, pause and skip, other sound turned down.
- VoiceOver over the text, the orange washes, the page's outlines and the
  correction sheet.
- The system's translation on a device, and how much it needs downloaded.
- A CSV opened in Excel and Numbers (the BOM, the delimiter, the accents).
- How Vision groups the lines of real documents: what it gave for five
  made-up pages is checked (`ScanReadingVisionTests`); for real ones it is
  not, by rule. A made-up letter whose lines were broken short by hand
  keeps them as lines rather than running them on.
- Phrase search in right-to-left text: a reader that orders a line by
  where its words stand would take an Arabic line's words from the left.
  Single words are what the checks search for.
- Real documents: none, by rule. Everything here is made up.

# The scan's text, from capture to export

What cleaning does to small grey print and to an umlaut's dots, what was
changed, the guard that keeps what a line says, and what is verified. Part A
of the brief "Schrift" (October 2026); parts B (capture) and C ("Neu
gesetzt") are not built yet.

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

- **The paper at its own level inside text** (`Tuning.textHeadroom = 1`):
  inside text boxes the paper is no longer taken as 95 % of itself. A faint
  mark keeps all of its contrast; the grain there is left to the toning and
  the curve.
- **Less smoothing inside text** (`Tuning.textGrain = 4`): grain within 4
  levels, not 10.
- **Light print toned line by line** (`ScanPrint.swift`, `ScanClean.toned`).
  Each line is measured in windows four line heights wide: its paper (90th
  percentile), its darkest ink (1st), the grain where no print is near, and
  the ink's colour.
  - **Which lines:** light neutral print only, ink lighter than 100 and fully
    from 140. Dark print, coloured print (a blue heading) and print on a grey
    fill (paper under 240) are left to the page's curve as before.
  - **How:** each pixel is darkened by the same share of how far under the
    paper it lies, so a dot is darkened as much as the stroke beside it. The
    ink is taken to 6, at most five times as dark, with the page's gamma.
  - **Small marks:** first made as clear as the strokes. An unsharp mask of
    the eight pixels round each, 1.4 times.
  - **The paper's grain:** within 2.5 times its spread of the paper it turns
    white. Near the paper, the mean of the nine is used, so no speck is
    taken darker.
  - **No seams:** windows blend into each other and over the line's edge.
  - Nothing is drawn, moved or thickened.
- **The guard** (`ScanCleaner.guarded`, `ScanContent.changed`): the cleaned
  page is read again. A line read before with confidence 0.9 or more, of
  three letters or more, must still read with every character in the same
  order on its row; only spaces may differ. A line that does not:
  - is cleaned again gently, its ink at most twice as dark, nothing
    sharpened, and read on its own;
  - if it still reads otherwise, is kept as the evened page has it: the light
    evened, the paper white, the ink as photographed.

  Each fallback is logged ("Cleaning changed N lines…"). Black and white is
  not guarded: it is two values only, and its menu already says it can lose
  a mark too pale to tell from the paper.

## Results (lab, Linux)

| Photo | Pipeline | Dots seen | Dot / stroke | Grey darkest 30 % (median, worst line) | Stroke at 300 dpi, variation | Blue hue |
|---|---|---|---|---|---|---|
| hard | main | 2 / 22 | 0.26 | 104, 123 | 4.0 px, 10 % | 211.1° |
| hard | new | 16 / 22 | 0.56 | 38, 55 | 4.7 px, 9 % | 211.1° |
| medium | main | 21 / 22 | 0.62 | 95, 121 | 3.3 px, 11 % | 211.3° |
| medium | new | 22 / 22 | 0.80 | 39, 68.5 | 3.8 px, 11 % | 211.3° |

Measured with `scratchpad/schrift/measure.py`, after
`swift build -c release` and the step runner in `scratchpad/lab4`.

The six hard-photo dots still short of "seen" are dark (over 100 levels under
the paper). They are not yet half as dark as their strokes.

Every scan test that runs on Linux passes, 70 of them: `ScanCleanTests`,
`ScanContentTests`, `ScanGeometryTests`, `ScanInvoiceTests`, `ScanLetterTests`
(body strokes ×1.17, under the 1.2 allowed), `ScanPrintTests` and
`ScanQualityTests`. Command: `swift test` in the lab.

The new grey print is bolder than the light face it was printed in: its soft
edges are darkened with its strokes. It is as dark as the body text, as the
brief asks.

## On the Mac, through Vision (CI)

`ScanTextFixtureTests` draws the same kind of letter with Core Text
(Helvetica Light, 7 pt, 55 % grey), at 200 and 150 dpi. It photographs it
(`ScanSample.photographed`), makes it ready as the Scan tab does and reads it
before and after cleaning. It checks:

- no line read surely before reads worse after (the guard's promise);
- at 200 dpi, the body reads as printed and the grey column 99.5 % of its
  characters (the brief's target);
- each grey line's darkest 30 % at 70 or darker, and the blue within 10°.

Its numbers go to `scan-text-200.txt` and `scan-text-150.txt`, and its crops
(column, umlauts, e-mail, blue, digits; before and after; 100 % and 300 %) to
the `scan-captures` pre-release, through Scan Checks.

## Not done in this part, and why

- **Upscaling before thresholding (step 3):** colour and greys have no
  threshold any more, since the toning is linear. Black and white still
  thresholds at the page's own resolution. Not changed.
- **Thickening thin strokes (step 6):** the grey strokes measure 3.8 to 4.7 px
  at 300 dpi on both photos, well over 1.5. Not needed, not built.
- **300 dpi output (step 9):** the PDF already draws each page at about
  300 dpi (`ScanGeometry.printScale`). The cleaned page itself stays at the
  photo's resolution, so the time per page does not grow. Pictures saved as
  PNG keep that resolution.
- **Speed on an iPhone 15:** not measured, as there is no device here. On
  this Linux machine the whole cleaning of a 2274 × 3215 page takes about
  6 s, single-threaded. The toning itself takes 0.03 s.

## Not verified

- **Vision on the Mac:** recognition after cleaning, the guard's fallbacks on
  real readings, and the 200 and 150 dpi numbers. These come from CI, not
  this machine.
- **On a device:** how the owner's own letter comes out, and the time per
  page.

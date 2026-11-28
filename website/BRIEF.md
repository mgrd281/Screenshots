# Surface brief: the Snapfly website

Development notes for whoever works on `website/`. Never shipped: `build.py`
does not copy this file into the site.

## Scope

- **Pages:** the landing page (Persuade); the privacy policy, the terms of
  use (`terms.html`, AGB in German), the right of withdrawal
  (`withdrawal.html`, Widerruf) and support (Read). See "Legal pages"
  below.
- **Languages:** English at the root, German under `/de/`, Arabic (right to
  left) under `/ar/`.
- **Host:** GitHub Pages. App Store Connect links to the privacy and support
  pages; once Snapfly Pro begins, the store descriptions link to the terms
  too (`docs/store/app-review.md`).
- **Audience:** Mac users who send screenshots into chats every day. Apple's
  reviewers read the privacy and support pages, and the terms.
- **Action:** Download for Mac, free. It links to the notarized
  `Snapfly.zip` on the `latest` release. An App Store badge comes later,
  once Apple approves the app.
- **Contact:** mgrdegh@gmx.de, which the owner chose to publish.
- **Three looks,** chosen with a switch in the menu bar: the airmail
  envelope (the default, the direction contract below); at the owner's
  request, the classic Mac desktop the site had before
  (`static/classic.css`); and the bold colour look the owner chose as a
  luxury, modern third (`static/bold.css`; see "The bold colour look" in
  `DESIGN.md`).
- **Constraints:**
  - System fonts only, and nothing loaded from another host (no Google
    Fonts, no analytics, no cookies).
  - UI labels come from the app's own `Localizable.strings`.
  - No invented claims: no ratings, user counts or prices other than free.

## Legal pages

The terms and the withdrawal page (November 2026) are there for Snapfly
Pro, the subscription Apple will sell in the apps; the Pro screen in each
app links to them in the language Snapfly shows (`ProLinks`). They are
documents like the privacy policy, and every footer links to both, right
after Privacy.

- **Job:** say plainly who sells what. Snapfly is free; Pro is optional and
  sold by Apple Distribution International Ltd.; covering private details
  is never part of it. Apple's own terms govern the purchase, and the
  pages say what they hold for withdrawing and cancelling.
- **The terms** (eleven sections): scope and provider, Snapfly is free,
  Snapfly Pro, renewal and cancelling, withdrawal, licence (Apple's
  standard EULA, the source on GitHub), what can be promised, liability,
  privacy, law and disputes, changes.
- **The withdrawal page** (eight sections) puts Apple's two pages first,
  under its summary, as buttons: withdraw from the contract online at
  Apple (the accent pill) and cancel the subscription (the quieter one).
  Then who sells Pro, the 14 days, the steps online, the other ways with
  the EU model withdrawal form, the refund, when the right ends early,
  cancelling, and where to ask.
- **Words:** the three languages say the same in the same order and are
  numbered alike; German says du; Apple's pages are linked in the reader's
  language where Apple has one; `LEGAL_UPDATED` in `content.py` is the
  day they last changed, written out in each language.
- **Not settled by the site:** the maker's postal address (there is no
  Impressum), and the reasons for a price rise, which Apple's terms ask an
  app's own agreement to give. Both wait for the owner.

## Direction contract

The owner asked for a completely new look with a clear identity, kept the
three brand themes, and chose the airmail direction from three sketched
first views (airmail, a folding sheet, a departure board).

THESIS: The page is an airmail envelope. The chevron edge of an airmail
envelope, in the theme's two colours, frames the browser window the whole
time; every screenshot on it is a perforated stamp clipped to the line; and
sending is posting, so what lands in the chat is struck with a postmark that
carries the time. It refuses what the site was before, and what the
category ships: a gradient wallpaper under glass, with centred headings over
a wash.

OWN-WORLD: Aerogramme paper is the ground: lavender blue for Original Sunset,
mint for Emerald Petrol, warm white for Signature Orange, and a night sheet
of the same ink in dark, with a fine fibre grain. The chevron edge runs coral
and violet, teal and petrol, orange and black. Postal ink (violet, petrol,
deep orange) prints the labels, postmarks and handstamps:
- white stamps with perforated edges, held by steel clips;
- round postmarks with wavy cancellation lines and the time in SF Mono;
- rectangular, double-ruled handstamps, struck a little crooked;
- the airmail label in every language at once: BY AIR MAIL · LUFTPOST ·
  بالبريد الجوي · PAR AVION.
Headlines are heavy SF Pro in ink; postal labels are tracked capitals. Mac
windows stay native: they are what the envelope carries.

STORY: Each screenshot hangs on the line as a stamp. One click copies it;
the paper plane posts it into the chat, where it lands postmarked. Private
details are covered before anything is posted, and nothing else leaves the
Mac. The visitor downloads it.

FIRST VIEWPORT: The chevron edge frames the window. Inside it, the paper
header carries the name, links, the theme swatches (each striped like its
edge) and the language. Under the header the line runs edge to edge with
five stamps; a postmark is struck across the second with today's date and
the visitor's time. The airmail label is stuck rotated under the line's
trailing end, above the chat. Lower start side, right under the line: the
headline at display size in ink, the subline, the download badge in postal
ink inside a paper ring, the requirements. Lower end side: the chat window,
with a dashed flight path from the line to it and one photo already posted
in it, postmarked.

FORM: Airmail envelope, first of seven (airmail envelope, origami folding
sheet, airport departure board, darkroom drying line, gallery hang with wall
labels, metro map, courtyard washing line). The signature interaction: a
photo posted into the chat lands with a postmark struck across it, stamping
the time it was sent. Motion grammar: things are struck (a short thud, from
118% to rest while turning onto their rest angle) or flown, never floated.
seed: none (unavailable)

FINISH: unreviewed and undocumented is unfinished; this build ends with the
finish review, the verdict, DESIGN.md, and every shipping raster carrying its
provenance

## Raster provenance

- `static/favicon.png`, `static/icon-64.png`, `icon-128.png`, `icon-180.png`
  and `icon-256.png`: the app icon `assets/icon.png`, resized by
  `make-images.py`.
- `static/og.png`: the brand wallpaper with the app icon, drawn by
  `make-images.py`.
- Everything else is inline SVG drawn in `build.py`: the synthetic
  screenshots (invoice, map, chart, calendar, sunset), the icons and the
  line-style tiles.

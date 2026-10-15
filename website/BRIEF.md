# Surface brief: the Snapfly website

Development notes for whoever works on `website/`. Never shipped: `build.py`
does not copy this file into the site.

## Scope

- **Pages:** the landing page (Persuade), the privacy policy and support
  (Read).
- **Languages:** English at the root, German under `/de/`, Arabic (right to
  left) under `/ar/`.
- **Host:** GitHub Pages. App Store Connect links to the privacy and support
  pages.
- **Audience:** Mac users who send screenshots into chats every day. Apple's
  reviewers read the privacy and support pages.
- **Action:** Download for Mac, free. It links to the notarized
  `Snapfly.zip` on the `latest` release. An App Store badge comes later,
  once Apple approves the app.
- **Contact:** mgrdegh@gmx.de, which the owner chose to publish.
- **Constraints:**
  - System fonts only, and nothing loaded from another host (no Google
    Fonts, no analytics, no cookies).
  - UI labels come from the app's own `Localizable.strings`.
  - No invented claims: no ratings, user counts or prices other than free.

## Direction contract

THESIS: The page is the Mac screen the app lives on. A menu bar carries the
navigation, Snapfly's line hangs under it with real-looking screenshots, and
the chat window sits in front. It refuses the category default: a headline
beside a laptop mockup, over a grid of feature cards.

OWN-WORLD: The brand gradient (amber, coral, violet) is the desktop
wallpaper, and only the ground. Everything on it is native macOS:
- a frosted menu bar;
- a grey rope with steel clips;
- white glass photo cards (16 pt, 4 pt inset, 12 pt image);
- accent-blue paper planes;
- cover-ink redactions;
- context menus, segmented controls and window chrome drawn to Apple's
  proportions;
- SF Pro through the system stack.

Light and dark follow the visitor, like a dynamic wallpaper.

STORY: Screenshots hang at the top of the screen instead of piling up on the
Desktop. One click copies one, the paper plane sends it into the chat, and
private details are covered before anything leaves. Nothing leaves the Mac.
The visitor downloads it.

FIRST VIEWPORT:
- At the top, a full-width menu bar holds the navigation and the language
  switch.
- Under it, the line spans the whole width with five crooked screenshots
  swaying on clips.
- Lower start side: the headline (the app's tagline) at display size, the
  subline, then a white "Download for Mac" pill with the requirements under
  it.
- Lower end side: a chat window in front, cropped by the fold, with one
  incoming question.

FORM: Mac desktop as the page (first of seven). The wallpaper stays fixed
under the whole home page, as a Mac's desktop does, with a wash below the
first view. Every demo is a native object on it:
- the keycaps;
- the Desktop's files, which fly up onto a rope;
- Snapfly's own Settings window, on its Privacy and Line panes;
- the photo's menu opening from a card on a line.

The signature interaction is the paper plane. It flings a hanging screenshot off the line and into the
chat, where it lands as a sent image, and the line closes the gap. Holding a
screenshot opens its real context menu. The menu doubles as the feature list.
seed: none (roll not run: the impeccable launcher is not installed in this
repository)

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

# Snapfly brand identity

What Snapfly is, how it looks and how it speaks, in one place. This file
describes the brand that already exists in the app, the website and the
promo video. It does not invent a new one.

**Where values live.** This file explains; it does not set values.

- `DESIGN.md` sets every colour, size, radius, shadow and motion value, and
  wins over this file. Where a value is quoted here, change it in
  `DESIGN.md` first.
- `PRODUCT.md` holds the product truths: who uses it, what it promises.
- `BRAND_GUIDELINES.md` says how to apply the brand to new work.
- `MOTION_SYSTEM.md` names the motion values as tokens and holds the motion
  concepts that are not built yet.
- The owner's brief for a task comes before all of them.

## 1. Positioning and personality

- **What it is.** A macOS menu bar app that hangs every screenshot on a line
  at the top of the screen, one click from any chat.
- **Tagline.** "Screenshots, one click from any chat." It is one of the
  app's strings, so it exists in all 13 languages (German: "Bildschirmfotos,
  einen Klick von jedem Chat entfernt.", Arabic: "لقطات الشاشة، على بُعد نقرة
  من أي دردشة.").
- **The idea that sets it apart.** The line itself: a physical metaphor that
  sits out of the way above every app and comes down when needed. Sending is
  the main act; private details are covered before anything leaves; nothing
  leaves the Mac.
- **Who it is for.** People who send screenshots into chats every day, a
  person or ChatGPT, often of orders and invoices. The owner, who works in
  German and Arabic, is the first of them.
- **Personality.** Quiet, precise, native, private, quick. It should feel
  like something Apple might have shipped, with one piece of character: the
  line and the paper plane.
- **What it is not.** Not a dashboard, not a cloud service, not playful for
  its own sake, not loud.
- **Evidence.** There are no testimonials, user counts or benchmarks. Never
  invent them. Claims stay to what the app does, as `README.md` describes.

## 2. Name, logo and app icon

- **Name.** Snapfly: one word, capital S, the rest lower case. Never
  "SnapFly", "Snap Fly" or "snapfly" in text (the lower-case form is only for
  file names, keys and URLs). It is not translated or transliterated: Arabic
  text writes "Snapfly" in Latin letters.
- **There is no separate logo or wordmark.** The app icon is the mark. Next
  to it, the name is set in the system font, Semibold.
- **The app icon** (`assets/icon.png`, drawn by `scripts/make-icon.py`): a
  screenshot card taking off up and to the right, with speed lines behind
  it, on the macOS squircle, over the brand gradient from amber through
  coral to violet.
  - It stays the same in every theme, appearance and language. It is never
    recoloured to match a theme.
  - The website's PNGs (`website/static/icon-*.png`, `favicon.png`,
    `og.png`) come from it, through `website/make-images.py`.
- **The menu bar icon** is the SF Symbol `tshirt`: clothes on a line. It
  fills (`tshirt.fill`) while the line is showing and becomes `stop.circle`
  while the screen is recorded. It is a template symbol, so macOS colours it.
- **Credit.** The About pane keeps "Based on Tendedero by Alejandro Buján,
  under the MIT License". The license requires it.

Usage rules for the icon are in `BRAND_GUIDELINES.md`.

## 3. Colour architecture

Three layers, each with its own job.

1. **The app: the system's colours.** Snapfly follows macOS. Its one accent
   is the user's own accent colour (`Color.accentColor`). Every other colour
   has a semantic job: pin orange, count red, search yellow, cover ink,
   record red, permission green and orange, island black. See "Colors" in
   `DESIGN.md`.
2. **The brand gradient: amber `#FFC45C`, coral `#FF5E62`, violet
   `#B234D6`.** It belongs to the icon and the About pane in the app. It is
   never an interface colour there: no gradient buttons or panels.
3. **The website: one brand, three themes.** The site is an airmail
   envelope: aerogramme paper inside a chevron edge, with postal ink for
   labels and postmarks. The visitor can choose one of three themes (below),
   each a colouring of the same envelope. Each works in light and in dark.

### One brand, three themes

The themes are three moods of the same Snapfly, not three brands. They live
on the website only; the app has no theme setting and follows macOS.

| Theme | Idea | Palette |
|---|---|---|
| **Original Sunset** (default) | The icon's coral and violet on a lavender-blue aerogramme | Paper `#ECEBFA`, edge coral `#FF5E62` and violet `#5B2BB8`, postal ink `#5B2BB8`, type `#1F1646`; a night sheet `#15122B` in dark. |
| **Emerald Petrol** | The same envelope in mint, with petrol ink | Paper `#E6F2EE`, edge Refined Teal `#168176` and Deep Petrol `#062F31`, ink Emerald `#07514E`; deep petrol paper at night. |
| **Signature Orange** | One confident colour, used with precision | Warm Neutral paper `#FAFAF8`, edge Primary Orange `#EC632C` and Premium Black `#171717`, ink Deep Orange `#C7461C`; Premium Black paper at night. |

- **What every theme keeps:** the name, the app icon, the system font, the
  envelope and its parts (the chevron edge, the stamps on the line, the
  postmark, the airmail label, the handstamp), windows and their traffic
  lights, system controls' shapes, status colours, the screenshots'
  content, the paper plane, the voice and the motion.
- **What a theme may change:** the paper, the edge's two colours, the postal
  ink, the accent on the site, links, the shadow tint, the rope, the
  download badge, and the small brand tiles. All of it through tokens; see
  "Brand themes" in `DESIGN.md`.
- **Light or dark is the system's,** in every theme. Six looks in all.

## 4. Typography

- **The system font only.** SF Pro (and SF Arabic) in the app and on the
  website. Nothing is fetched from another host, and no web fonts.
- **Rounded with tabular digits** for keycaps and counts (SF Pro Rounded).
- **In the app, weight before size.** Hierarchy comes from Semibold against
  Regular and from secondary colour, not from large type. The app has no
  display sizes and no words under 11 pt.
- **On the website, display sizes are allowed:** the hero to 5.6 rem,
  section heads to 3.5 rem, heavy (800) with tight tracking (−0.035 em,
  −0.03 em) and none in Arabic. Postal labels are tracked capitals; the
  postmark's time is SF Mono.
- **In the promo video,** which is rendered off the Mac, the fonts travel
  with it: Inter and Noto Sans Arabic (SIL Open Font License) in
  `promo/fonts/`, so every render draws the same frames.

## 5. Iconography

- **SF Symbols** in the app, at the weight and size of the text beside them:
  `paperplane.fill` to send, `lock.fill` for a covered photo, `pin`,
  `magnifyingglass`, `timer`, `xmark`, `play.fill` and so on.
- **On the website,** icons are inline SVG drawn in `website/build.py` to
  match SF Symbols' proportions: one stroke weight, round caps, no fills
  where the symbol has none.
- **One icon, one meaning.** The paper plane always means "send". The lock
  always means "private details covered".
- **No emoji as icons,** and no decorative icons without a job.
- **App icons drawn on the site** (the Dock in the desktop demo) share one
  style: 48 pt squircles, a top-lit gradient, a 10% hairline, one shaded
  glyph.

## 9. Graphic motifs and illustration language

The brand's motifs all come from the product. Use them; don't add others.

- **The line.** A rope (or the glass shelf, the island, the card stack)
  across the top, with photos hanging on clips. It is the signature shape.
- **The photo card.** In the app, a screenshot in a thin frame of glass,
  16 pt corners, hanging slightly tilted, swaying a little. On the website
  the same card is a postage stamp: white paper with a perforated edge.
- **The paper plane.** A card that takes off up and to the right, like the
  icon, and lands in a chat.
- **The airmail envelope.** On the website the page is an envelope: the
  chevron edge round the window, aerogramme paper, stamps on the line, a
  postmark with the time on what is sent, the airmail label in every
  language at once, a rubber handstamp where details are covered. Demos are
  native Mac objects carried in it: keycaps, files, Settings, a context
  menu, a whole desktop to try Snapfly on.
- **Cover ink.** Opaque, near-black blocks over private details. It reads as
  redaction, never decoration.
- **Illustration** is drawn, not photographed: flat, precise, in the
  system's proportions, like a well-made screenshot. No stock photos, no 3D
  renders, no people.

## 10. Brand voice and tone

- **Plain and short.** Say what happens, in the fewest words that are
  still friendly. "Copied", "Sent to Lena", "Screenshot taken".
- **Concrete over abstract.** Name the thing: "WhatsApp or ChatGPT", "your
  invoice", "⌃⌥V".
- **Calm and honest.** No hype words, no exclamation marks in the interface,
  no invented numbers, no promises the app doesn't keep.
- **Private by default, said plainly.** "Snapfly collects no data. It runs
  entirely on your Mac."
- **Per language:**
  - German addresses the reader as "du", with a space before "…"
    ("Suchen …").
  - Arabic reads right to left; Snapfly stays in Latin letters.
  - Every label the app shows comes from its `Localizable.strings`, and the
    website and video reuse them, so all three say the same thing.

## 12. Motion identity

Calm motion with meaning: movement explains where something came from or
went. A capture flies in, a sent photo takes off like the paper plane, a
stack spreads, a hanging photo sways a little on its clip. Nothing blinks,
pulses or moves just to decorate, and Reduce Motion always leaves a quick
fade. The tokens, the existing moves and the concepts for future work are
in `MOTION_SYSTEM.md`.

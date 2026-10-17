---
name: Snapfly
description: Screenshots on a line at the top of the screen, one click from any chat.
colors:
  accent: "#007AFF"            # Color.accentColor: follows the user's macOS accent; the hex is the default
  brand-amber: "#FFC45C"       # icon gradient, start
  brand-coral: "#FF5E62"       # icon gradient, middle
  brand-violet: "#B234D6"      # icon gradient, end
  pin-orange: "#FF9500"        # Color.orange: a pinned photo
  count-red: "#FF3B30"         # Color.red: the count on a closed card stack
  search-mark: "#FFCC00"       # Color.yellow: search highlights, 45% fill and a solid edge
  cover-ink: "#1F1F1F"         # covers over private details in a photo; the ink tiles in Settings
  tile-paper: "#EBEBEB"        # the ink tiles in the dark, their symbol in #1A1A1A
  island-black: "#000000"      # the island line style
  # Draw on Photo's inks, drawn into the copy's pixels, so fixed in light and dark.
  draw-red: "#FF3B30"          # the first ink; white words and numbers on it
  draw-yellow: "#FFCC00"       # the highlighter's first ink; dark words on it
  draw-green: "#34C759"        # dark words on it
  draw-blue: "#007AFF"         # white words on it
  draw-black: "#1C1C1E"        # also the dark words on the light inks
  draw-white: "#FFFFFF"        # a step's rim on the other inks
  # Website only (website/static/site.css). Light value first, dark after the slash.
  web-button: "#0071E3"        # the accent as a button fill: white text on it is 4.7:1
  web-link: "#0066CC"          # links; #3D9BFF in dark
  web-ink: "#1D1D1F"           # text; #F5F5F7 in dark
  web-ink-2: "#5E5E63"         # secondary text, 5.9:1 on the ground; #A1A1A6 in dark
  web-ground: "#F5F5F7"        # page ground; #161618 in dark
  web-surface: "#FFFFFF"       # windows, panes, keycaps; #232326 in dark
  web-bubble-in: "#E9E9EB"     # incoming chat bubble; #3A3A3C in dark
  window-red: "#FF5F57"        # traffic lights on drawn windows
  window-yellow: "#FEBC2E"
  window-green: "#28C840"
typography:
  field:
    fontFamily: "SF Pro, system-ui"
    fontSize: "17pt"
    fontWeight: 400
  title:
    fontFamily: "SF Pro, system-ui"
    fontSize: "13pt"
    fontWeight: 600
  body:
    fontFamily: "SF Pro, system-ui"
    fontSize: "13pt"
    fontWeight: 400
    lineHeight: "+2pt"
  label:
    fontFamily: "SF Pro, system-ui"
    fontSize: "12pt"
    fontWeight: 500
  caption:
    fontFamily: "SF Pro, system-ui"
    fontSize: "11pt"
    fontWeight: 400
  numeric:
    fontFamily: "SF Pro Rounded, system-ui"
    fontSize: "11pt"
    fontWeight: 700
rounded:
  mark: "2pt"
  cover: "3pt"
  keycap: "6pt"
  tile: "10pt"
  inner: "12pt"
  card: "16pt"
  floating: "20pt"
  shelf: "24pt"
  island: "30pt"
  full: "999pt"
spacing:
  hairline: "2pt"
  inset: "4pt"
  xs: "6pt"
  sm: "8pt"
  md: "12pt"
  lg: "16pt"
  xl: "24pt"
  shadow-margin: "28pt"
components:
  photo-card:
    rounded: "{rounded.card}"
    padding: "{spacing.inset}"
  photo-image:
    rounded: "{rounded.inner}"
  floating-card:
    rounded: "{rounded.floating}"
    padding: "{spacing.lg}"
    width: "380pt"
  search-bar:
    rounded: "{rounded.card}"
    height: "50pt"
    width: "440pt"
    typography: "{typography.field}"
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "#FFFFFF"
    typography: "{typography.body}"
  corner-button:
    rounded: "{rounded.full}"
    size: "20pt"
  send-button:
    backgroundColor: "{colors.accent}"
    textColor: "#FFFFFF"
    rounded: "{rounded.full}"
    size: "22pt"
  pin-button:
    backgroundColor: "{colors.pin-orange}"
    textColor: "#FFFFFF"
    rounded: "{rounded.full}"
    size: "20pt"
  count-badge:
    backgroundColor: "{colors.count-red}"
    textColor: "#FFFFFF"
    typography: "{typography.numeric}"
    rounded: "{rounded.full}"
    height: "22pt"
  tag:
    rounded: "{rounded.full}"
    width: "26pt"
  settings-button:
    minWidth: "128pt"              # every button at a settings row's trailing edge
  sidebar-tile:
    rounded: "{rounded.keycap}"
    size: "24pt"
  inspector:
    width: "340pt"                 # Hide Part's trailing column, a grouped form over a footer
  canvas:
    margin: "{spacing.xl}"         # around the picture in Hide Part, on NSColor.underPageBackgroundColor
    minWindow: "760pt × 480pt"
  draw-tool:
    rounded: "{rounded.keycap}"
    size: "34pt × 28pt"            # a tool in Draw on Photo's row; chosen: the accent at 16% behind the accent glyph
  draw-swatch:
    size: "18pt"                   # an ink, with a 1pt hairline of .primary at 18%; chosen: a 2pt accent ring 3pt out
  draw-handle:
    size: "9pt"                    # white, a 1.5pt accent edge, at a chosen mark's ends or corners
  draw-mark:
    line: "0.25%, 0.4% or 0.65% of the unit"   # Thin, Medium, Thick; the unit is √(width × height), at least 640 px
    step: "2%, 2.8% or 3.8% of the unit"       # a numbered circle across, its rim 8% of that
    words: "1.6%, 2.2% or 3% of the unit"      # semibold, on a label rounded 30% of its height
  time-stamp:
    backgroundColor: "#F7F7F7"     # a band above the picture, gray 0.97
    hairline: "#D1D1D1"            # gray 0.82, between band and picture
    titleColor: "#141414"          # gray 0.08
    detailColor: "#525252"         # gray 0.32
    codeColor: "#666666"           # gray 0.4
    size: "0.95% of the image's width, at least 11 px"
---

# Design System: Snapfly

## Overview

Snapfly is a native macOS utility. It should feel like something Apple might
have shipped: quiet, precise, made of the system's own materials. It should
not look like a web dashboard put in a window. Its one piece of character is
the line itself, the place the screenshots hang. Everything around the line
stays out of the way.

**Principles**

1. **Native first.** Use system materials, SF Pro, SF Symbols, the user's
   accent color and standard controls. Reach for a custom look only when
   the system has no equivalent, and then match its proportions.
2. **The photo is the content.** Chrome around a screenshot is thin glass and
   one radius. A control appears where the hand already is: on hover, in the
   corner, or on the tag.
3. **Refined minimalism.** One accent, the semantic colors listed here, no
   decoration without a job. Each style shows its one idea with conviction:
   the rope, the glass, the island or the stack.
4. **Never steal focus.** Floating surfaces (the line, the text card, the search
   bar) are non-activating panels. Design them to be operated with the mouse
   while another app keeps the keyboard. The search bar is the exception: it
   takes the keyboard without activating the app.
5. **Calm motion with meaning.** Movement explains where something came from
   or went: a capture flies in, a sent photo flies out, a stack spreads. It
   never runs just to decorate.

### Accessibility

- **Labels.** Every icon-only control has a spoken label
  (`accessibilityLabel`, or `TagArea(label:)` on the tag) and a tooltip
  where the pointer can rest.
  - On a photo, `GrabView` gives tooltips for its two hot spots.
  - SwiftUI controls use `.help`.
- **VoiceOver on photos.** Each photo is one button, named after its file.
  - Press copies it, and Show Menu opens its menu.
  - What the pointer finds on hover is offered as actions: send, pin or
    unpin, take down.
  - Decorative overlays drawn on the photo are hidden from it.
- **Contrast.** Text meets WCAG AA (4.5:1). Glyphs on glass use `.primary`,
  never a fixed grey. White on the accent, orange or red is for glyphs and
  short labels only.
- **Reduce Motion.** Springs, swings, the stack fan and the photo flights fall
  back to quick fades.
  - SwiftUI reads `accessibilityReduceMotion`.
  - AppKit code reads `Motion.reduced`.
  - `Motion.spring(response:damping:reduced:)` gives a spring, or a 0.15 s
    ease-out.
  - Any new motion goes through them.
- **Reduce Transparency.** Materials and Liquid Glass turn opaque by
  themselves. Our own see-through surface with text on it is the photo badge
  (`PhotoBadge`): with Reduce Transparency it is the cover ink, solid. Never
  put text on a custom translucency that has no opaque fallback.
- **Increase Contrast.** Frosted glass draws a firmer, darker edge (the
  `GlassFrame` modifier).
- **Keyboard.** Return confirms and Escape cancels in every window and panel
  that takes the keyboard. The search bar, Hide Part and the shortcut recorder
  already do.
- **Right to left.** Arabic must read right to left: align and order by
  reading direction, not by fixed left and right. The text card already
  aligns RTL results.
- **Size.** Pointer targets are at least 20×20 pt and spaced so they don't
  touch. Touch sizes (44 pt) do not apply on the Mac.

## Colors

Colors come from the system first. Name them by their role, never by a
literal value in a view.

### Primary
- **Accent** (`Color.accentColor`) marks the one primary action or selection
  in view. That covers Send, the picked ring and check, the chosen style tile,
  the search count and links. It follows the user's System Settings accent,
  so never hardcode the blue.

### Brand
- The **amber, coral and violet gradient** belongs to the app icon only. It
  is not an interface color: no gradient buttons, no gradient panels, no
  monograms.

### Semantic
- **Pin orange** means "kept on purpose". It is used only for the pin badge.
- **Count red** is only for the closed stack's count, as on a Dock badge.
- **Search yellow** is the highlighter on words found by Search.
- **Cover ink** is the opaque block over private details. It reads as
  redaction, not decoration.
- **Photo badge** is black 55% with a white glyph or text, over a picture: the
  lock, the paper plane of a photo sent before, the PDF capsule, and the size
  while an area is chosen. With Reduce Transparency on, it is the cover ink
  instead (grey 12%, solid).
- **Record red** (`Color.red`) is only for the stop button while the screen
  is recorded, as macOS marks recording.
- **Allowed green** and **not allowed orange** (`.green`, `.orange`) are only
  for a permission's state, and the orange for a rule's pattern that cannot
  be read, with a symbol beside the word, never color alone.
- **Island black** is pure black, to blend into the notch and the menu bar
  above it.
- **Drawing inks** (`Drawing.Ink`) are the six colours Draw on Photo draws
  in: red (the first), yellow (the highlighter's first), green, blue, black
  and white. They go into the copy's pixels, so they are fixed values, never
  system colours that change with the appearance. Words and numbers on them
  are white on red, blue and black, and black on yellow, green and white.
  They appear only in the picture and in the window's swatches.
- **Ink tiles** (`InkTile`): cover ink with a white symbol in the light,
  paper (grey 0.92) with the symbol in ink (grey 0.1) in the dark, never a
  colour. Behind the Settings sidebar's symbols and the Support pane's rows.

### Neutral
- Text uses `.primary`, `.secondary` and `.tertiary`.
- Fills use `Color.primary.opacity(0.045–0.12)`, so they work in both light
  and dark.
- **Canvas** (`NSColor.underPageBackgroundColor`) is the desk a page lies on
  in Hide Part, light and dark from the system, as Preview has it.
- **Surfaces split by role.**
  - **Content** is the photos and the text card's reading panel. It stays
    frosted material: `glassFrame()` (`.ultraThinMaterial`) around photos, and
    `.regularMaterial` behind the text card.
  - **Floating controls** are the tag, corner buttons, the play badge, the
    "Copied" capsule, the empty-line hint and the search bar. They take Liquid
    Glass on macOS 26 through `controlGlass()` (`glassEffect(.regular)`), and
    the same frosted glass before it.
  - The shelf line style is Liquid Glass too.
  - This follows Apple's rule that glass is for the layer that floats above
    content, not for the content.

### Named Rules
- **One accent per surface.** A second saturated color needs a semantic job
  from the list above.
- **Light and dark are equals.** Every color is a system color, a material or
  `.primary` with an opacity, so both appearances work without branching.

## Typography

The face is SF Pro, the system font. Keycaps and counts use the rounded
design with monospaced digits.

### Hierarchy

| Role | Size | Weight | Used in |
|---|---|---|---|
| Field | 17 pt | Regular | Search bar input |
| Title | 13 pt | Semibold | Card headers ("Translation", "Description") |
| Body | 13 pt, +2 pt leading | Regular | Translations, descriptions, settings rows |
| Label | 12 pt | Medium | Language menu, result count, keycaps |
| Caption | 11 pt | Regular, or Semibold when selected | Notes under results, style tiles, "Copied" |
| Glyph | 8–10 pt | Bold | SF Symbols on corner buttons and the tag |

### Named Rules
- **Weight before size.** Hierarchy comes from Semibold against Regular and
  from `.secondary` against `.primary`, not from big type. Snapfly has no
  display sizes.
- **Never below 11 pt for words.** Glyphs may be 8–10 pt. Text may not.
- **Long words.** Labels must survive German (lineLimit plus
  `minimumScaleFactor(0.8)` on tight tiles) and Arabic.

## Layout

- **Grid.** Spacing follows a 4 pt rhythm: 2, 4, 6, 8, 12, 16, 24. A photo
  card has a 4 pt inset of glass around the image.
- **The line** spans the screen's visible width.
  - The strip's height is `photoMaxHeight + 106` at the chosen size: Small
    0.8×, Medium 1×, Large 1.35×.
  - Photos sit `cardWidth + 24` apart, and how many fit follows from the
    width.
  - A longer line scrolls only with Keep on line. Otherwise photos move closer
    together.
  - One function, `Layout`, places photos for the view and for every flight.
    Never position a photo anywhere else.
- **Floating panels.**
  - The text card is 380 pt wide; the search bar is 440 pt.
  - Each keeps a 24–28 pt transparent margin so its shadow isn't clipped.
  - Each is clamped 8 pt inside the screen's visible frame.
  - Each opens under the photo it belongs to, or under the line.
- **Settings** is a sidebar window, at least 640 × 440, using grouped
  `Form`s. Group rows into sections with headers; no free-floating controls.
  - It opens at 760 × 560, can be resized from its edges and zoomed with
    the green button, and remembers its size and place.
  - The sidebar names each pane after a 24 pt tile, rounded 6 (the keycap
    radius), as System Settings does, but all six tiles are ink
    (`InkTile.fill`, the cover ink) with the symbol knocked out in white
    (`InkTile.glyph`); in the dark, paper with the symbol in ink. One
    colour, so the sidebar stays quiet. They are fixed colours on purpose:
    `.primary` and `.background` go vibrant in a sidebar and wash out.
  - A button on a row sits at the trailing edge, in a `LabeledContent` whose
    label says what the button is for, and is a `SettingsButton`: regular
    `.bordered`, at least 128 pt wide, so the buttons down a pane line up as
    one column. A longer label still gets its room. A row in a list is
    removed with a borderless `minus.circle` and its help tag, never a
    worded button.
  - General names the screenshots folder under "Screenshots folder", from
    the home folder down ("Pictures › Snapfly"), with Show in Finder beside
    it; watched folders are named the same way.
- **Screens and devices.** Snapfly is macOS only; there is no mobile layout.
  It must handle these instead:
  - several displays: the line goes to the screen with the pointer;
  - full screen Spaces;
  - a line moved down with its grip;
  - all three sizes;
  - all eight styles.

## Elevation & Depth

There are two levels: things on the line, and things floating over other
apps.

### Shadow Vocabulary
| Element | Shadow |
|---|---|
| Photo card at rest | black 18%, radius 10, y 5 |
| Photo card on hover | black 26%, radius 14, y 8, with a 1.035× scale |
| Tag, closed stack | black 18%, radius 6, y 3 (frosted glass only; Liquid Glass carries its own depth) |
| Floating card, search bar, shelf, island | black 14–35%, radius 14–20, y 6–10 (the lighter end under Liquid Glass) |
| Small badges (pin, count, send) | black 20–25%, radius 2–3, y 1 |

### Named Rules
- **A shadow means it floats.** Inner blocks, rows and chips are flat and use
  a faint fill instead.
- **One shadow per object.** Never stack shadows, glows or outer borders on
  the same element.

## Shapes

- **Concentric corners.** An inner radius equals the outer radius minus the
  inset. A card is 16 with an image of 12; a floating card is 20 with inner
  blocks of 12.
- **Continuous corners** (`style: .continuous`) everywhere.
- **Circles and capsules** are for controls only: corner buttons, send,
  badges, the tag and chips.
- The island has rounded shoulders (12) where it meets the menu bar, and
  30 pt bottom corners.

## Components

### Buttons
- **Native first.**
  - Primary is `.borderedProminent`; secondary is `.bordered`.
  - Both are `.controlSize(.large)` in floating cards and regular in
    Settings.
  - A link-style button is for "Open System Settings…"-type escapes.
- **One primary per surface.** A primary is a verb with an SF Symbol: Send,
  or Send with Photo.
- **Labels say what happens.** For example "Copy", which turns into "Copied"
  with a checkmark.
- **Corner buttons on a photo** are 20–22 pt circles. They show on hover only,
  except the pin, which always shows.
  - Top leading: discard (cross, or eye-slash for files outside Snapfly's
    folder) or unpin.
  - Bottom trailing: send.
  - Each draws in SwiftUI and is hit-tested in `GrabView`.

### Photo card
- Glass frame, a 4 pt inset and a 12 pt image corner.
- States:
  - picked: accent ring and check;
  - covered: lock badge, shown only when something was covered. Resting on
    it shows a tip naming what was, kinds in Settings' order joined by " · ",
    then "Your own rules" and "Hidden by hand": "Covered: Names · Emails".
    The same line is the photo's accessibility value, and the first item of
    its menu, disabled, with `lock.fill` from macOS 26, over a separator;
  - a PDF: a "PDF" capsule with its page count, in the lock's corner and
    style (9 pt bold white on black 55%, 18 pt high). A PDF brought in from
    elsewhere leads the capsule with a mini white spinner while its pages
    are covered, then the 8 pt bold `lock.fill` once something is. The
    capsule takes the lock badge's place, so a card never shows both;
  - sent before: an 18 pt photo badge circle with an 8 pt bold
    `paperplane.fill`, 4 pt after the lock in reading order (in its place
    when nothing is covered), fading in over 0.2 s; still, without sound.
    It shows while Mark photos sent before is on (Settings › Line, under
    Take photos down once sent, on at first, off without a history) for a
    photo whose print (`TextPrint`) matches a send in the History. Resting
    on the corner says "Sent to WhatsApp · Today at 14:05" under the lock's
    line; the menu has it disabled with `paperplane` from macOS 26, after the
    lock's line and before the separator, mark or no mark; VoiceOver hears
    both lines as the value;
  - pinned: orange pin;
  - copied: "Copied" capsule below;
  - search: dimmed and desaturated when it isn't a match, yellow marks when it
    is;
  - dragged: 45% opacity in its slot. Dragged along the line (within the
    cards' height and 24 pt more), its slot moves to where the pointer is,
    past each neighbour's middle, and the others step aside with the line's
    order spring; let go there, it stays rather than flying back. A closed
    stack does not reorder. VoiceOver has Move Earlier and Move Later.

### Drop slot
- While photos or PDFs from another app are dragged towards the top of a
  screen, the line comes down there and keeps a place for them where the
  newest photo hangs. The others make room with the line's order spring
  (0.42 s, 0.8 damping).
- The slot is a card's outline: a glass frame the card's width and 72% of a
  photo's tallest height, with a 1.5 pt dashed border (6 on 4) in
  `.secondary` at 70%, and `arrow.down.doc` at 20 pt medium in `.secondary`.
- While the files are over the line it lights up: the border and the symbol
  turn to the accent, the border to 2 pt, and the slot grows to 104%, over
  0.15 s ease-out.
- Under it, a capsule like the empty line's hint (12 pt medium rounded,
  `.secondary`, control glass) says what letting go does: `lock.fill` with
  "Drop here – private details get covered" while Hide private details is
  on, else `arrow.down` with "Drop here to hang it". The empty line's own
  hint steps aside meanwhile.
- The menu bar icon takes the same files, with its pressed highlight while
  they are over it.
- Let go, each file flies in from where it was dropped, 80 ms apart, the way
  a capture does.

### Tag
- A 26 pt wide capsule of SF Symbol tools: grip, combine, search, send and
  take down. While photos are picked, PDF takes search's place, so it never
  holds more than five.
- It is clipped to the rope on the clothesline and sits inside the holder on
  the shelf and the island.
- Tools show only when they can act.
- Under the pointer, a tool's glyph sits on a 22 pt circle of
  `.primary` at 10%, or white at 18% on the island, fading in over 0.12 s.

### Navigation
- **Menu bar icon.** Snapfly's own mark, drawn in code as a template
  (`LineIcon.swift`) on an 18 pt square: a line sagging 1.7 pt across the
  width (1.25 pt stroke), and a photo hanging from it by a 1.4 × 3.4 pt
  clip, turned −7° together. The photo is 10 × 8.6 pt at a 1.8 pt radius
  with a 1.45 pt stroke, a 1.8 pt sun and a hill (1.2 pt stroke) inside so
  it reads as a picture. It fills, with the sun and hill cut out, while
  copied images are hung, and becomes `stop.circle` while the screen is
  recorded. The Line pane in Settings shows the same mark; the website's
  drawings use it at 24 units.
- **Menu bar menu.** In groups, by purpose, as Apple's menu bar extras are.
  - First what hangs, as a disabled line ("3 photos on the line", "Nothing
    on the line"), and the main act: Paste into <the app in front>, with
    the send shortcut, enabled while something hangs.
  - Then the ways onto the line: Take Screenshot, Take Screenshot with
    Timer, Capture Whole Page, Record Screen (Stop Recording while it runs),
    Add Files… (⌘O).
  - Then the line: Show or Hide line, Search…, History…, Take everything
    down; the last three enabled only when they can act.
  - Then two switches with a checkmark: Hide private details, which keeps
    the kinds chosen when turned off and brings them back when turned on
    (the recommended ones when none were kept), and Screenshot Button.
  - Then Settings… (⌘,), Open screenshots folder, Help & Support… (the
    website's support page, in German or Arabic where the Mac speaks them)
    and, outside the App Store, Check for Updates…. Quit last.
  - Permissions Needed… comes first of all, only once a permission was
    refused.
  - SF Symbols on macOS 26 only, as the photo context menu: `paperplane`,
    `camera.viewfinder`, `timer`, `scroll`, `record.circle` (`stop.circle`
    while recording), `folder.badge.plus`, `arrow.down.to.line` or
    `arrow.up.to.line`, `magnifyingglass`, `clock.arrow.circlepath`,
    `eye.slash`, `hand.raised`, `camera.circle`, `gearshape`, `folder`,
    `questionmark.circle`, `arrow.down.circle`. None on Quit, as in Apple's
    menus.
- **Finder's Services menu.** Send Safely with Snapfly and Hide Private
  Details with Snapfly, for photos and PDFs, translated like the app
  (`ServicesMenu.strings`). Open With lists Snapfly as an alternative, never
  as what opens them. Hide Private Details opens Hide Part for one file, to
  save a copy beside it.
- **Photo context menu.**
  - Grouped by intent: copy and send; translate, describe and Order Details;
    open and edit; take down.
  - **Keep on Top** (`pip`) follows Quick Look for a photo: it floats over
    every app in a utility panel with a transparent title bar and its close
    button, the photo filling it, its longer side 360 pt at first and never
    larger than the photo. It keeps the photo's shape when resized (120 pt
    at least), moves when dragged anywhere, never takes the keyboard, and
    shows on every Space. It opens 16 pt below the photo on the line, the
    next 24 pt down and along from the last, kept 8 pt inside the screen,
    and fades in over 0.15 s. Up to three float; a fourth closes the
    oldest. It shows the screenshot as it is, for the user alone.
  - **Order Details** opens the text card with `list.bullet.rectangle` and
    the order's parts as rows on the reading panel's fill: the part's name
    in 12 pt `.secondary` in a 104 pt column, the value in 13 pt,
    selectable, and a borderless `doc.on.doc` that turns into a checkmark
    once copied, with a divider between rows. The note says it is read as
    the screenshot shows it, not covered. Its footer has Copy Row and Copy
    All (the primary); it sends nothing.
  - **Save for Bookkeeping** (`folder.badge.plus`) and **Email to
    Bookkeeping…** (`envelope`) follow it. The first asks for the folder
    once with an open panel, then saves and says so in a note above the
    Dock; the second opens the system's new email with the copy attached.
  - **Settings › Line › Bookkeeping**: the folder's name in `.secondary`,
    truncated in the middle, with a Choose… `SettingsButton`, and the
    address in a field with a prompt. Then Monthly pack: a menu of the
    months the table has receipts for, newest first and named as people
    say them, and a Make PDF `SettingsButton`, both off until there is one.
    It works under a working note above the Dock and shows the PDF in the
    Finder.
  - **The monthly pack** is an A4 PDF in the system font, black on white.
    Its first page has the title (20 pt semibold), a 9.5 pt grey note that
    it is a help for the tax advisor, then the list: 8.5 pt semibold grey
    headings over a 0.5 pt rule, rows 18 pt high in 10 pt (the fingerprint,
    16 hex digits, in 8 pt monospaced), hairlines between them, amounts and
    pages aligned to the numbers' side, and a receipt not found in grey with
    a dash for its page. The count, the sum and what was not found close
    it in 10 pt medium. Each receipt follows on a page of its own under a
    9 pt grey caption, as large as fits; every page has "n / total" at the
    foot in 8 pt grey. In right-to-left languages the columns run from the
    right.
  - **Send with Shop Header** (`storefront`) follows Paste into … for a
    photo. It works under a working note above the Dock, then sends as
    Paste does. With no shop name or logo yet, a note says where to add
    them.
  - **The shop's band** sits above the covered screenshot, as wide, white,
    with a hairline of grey 86% between them. Its sizes grow with the
    picture as the time stamp's do (a font of 1.25% of the width, 13 px at
    least): the logo leads in the reading direction as a square the band's
    height less its padding, filled and with corners of 22% of its side,
    then the shop's name (semibold, grey 8%) over the order and the day
    (regular, grey 36%), centred as a block and cut short with an ellipsis.
  - **Settings › Line › Shop header**: the name in a field with a prompt;
    the logo as a 24 pt square with 5 pt corners, a borderless
    `minus.circle` to remove it and a Choose… `SettingsButton`; and a
    preview of the band's leading end, at twice its size, with 6 pt corners
    and a 0.5 pt edge of `.primary` at 12%.
  - SF Symbols on macOS 26 only, as Apple's own menus have.
- **Settings sidebar.** General, Line, Privacy, Permissions, Support and
  About, each on its tile (see Layout).

### Dialogs, sheets and panels
- **Floating card** (`TextCard`) for results that belong to a photo:
  - a header with symbol, title and close, the symbol in the accent on a
    circle of the accent at 12%;
  - one content block on a faint fill;
  - an optional note;
  - footer actions on the trailing edge.
- **Search bar.** One field, a result count chip and close.
- **Full windows** (Hide Part, Settings) for focused work. They are standard
  titled windows with Cancel and Done bound to Escape and Return.
  - Hide Part (`HideEditor.swift`) is a resizable window of two columns,
    never smaller than 760 × 480, opening as large as the picture needs and
    at most 80% of the screen (`HidePartLayout`), so a tall page opens a
    wide window.
    - The **canvas** on the leading side, `underPageBackgroundColor`, holds
      the picture centred with a 24 pt margin, as large as fits and never
      larger than itself, under the floating card's shadow (black 18%,
      radius 14, y 6): the one thing in the window that floats. For a PDF,
      a 36 pt row under it turns the pages: `chevron.backward` and
      `chevron.forward`, small, each with its help tag, around "Page 2 of 5"
      in callout `.secondary` with monospaced digits. Each page keeps its
      own boxes, and saying what to hide reads the page showing.
    - The **inspector** on the trailing edge, 340 pt, is a grouped `Form`
      over a footer. First "Say what to hide": a rounded field after
      `sparkles` (or `text.magnifyingglass` without Apple Intelligence) in
      13 pt semibold `.secondary`, a Hide button and a small spinner while
      it works; with Apple Intelligence, three examples under it as small
      `.bordered` buttons, in a row where they fit, else stacked; the
      section's footer says what it did. While the field has the keyboard,
      Return runs it; empty, Return is Done. For a copy, "Hide in this
      copy" follows (below). Last, "By hand": the drag hint as a row's
      subtitle, Remove All on its trailing edge.
    - The **footer**, under a divider, holds Cancel and Done on the
      trailing edge.
  - Hide Private Details in a copy (from Finder) is the same window with
    "Hide in this copy" in the inspector: Check All, Recommended and Uncheck
    All, small, sharing the row in equal parts (stacked where they don't
    fit), a footer saying the copy has no place or camera details, then the
    sixteen kinds as switches in the three groups Settings has, named as
    Settings names them, starting with what Settings hides. The primary
    button reads Save Copy… and opens a save sheet in the folder of the
    original, under the name "… (covered)". A small spinner shows in the
    footer while the copy is written, and the window closes only once it is.
- **Draw on Photo** (`DrawEditor.swift`) is Hide Part's window, laid out
  the same (`HidePartLayout`), for arrows, boxes, highlights, numbered steps
  and words drawn on a photo, and the part of it to keep.
  - The **canvas** shows the picture with what Hide private details covers
    and the parts hidden by hand, then the marks drawn by the same code as
    the copy (`Drawing.draw`), so what you see is what goes. A highlight
    multiplies into the picture, so words under it stay as dark as they
    were.
    - A chosen mark has a dashed accent outline (1 pt, 4 and 3) 4 pt out,
      and a 9 pt white handle with an accent edge at an arrow's ends or a
      box's corners. The canvas keeps 12 pt round the picture so handles at
      its edges show whole.
    - Outside a crop is dimmed, black 60%, with a white hairline round
      it. While cropping it is 45%, with thirds in white at 35% and 18 pt
      white corners, 3 pt and rounded, to drag.
    - The pointer is the arrow for Select, the I-beam for Text, and the
      crosshair for the rest.
  - The **inspector**: first "Tool", a row of seven 34 × 28 pt tools,
    `cursorarrow`, `arrow.up.right`, `rectangle`, `highlighter`, `1.circle`,
    `textformat` and `crop`, each with its help tag and its key (V, A, R, H,
    N, T, C), the chosen one in the accent on the accent at 16%, rounded 6;
    the section's footer says how to use the tool. Then Color, six 18 pt
    swatches, and Size, a segmented Thin, Medium, Thick; they change the
    chosen mark and the next one, and the highlighter keeps an ink of its
    own. A chosen mark gets a section with its name and Delete (⌫), and for
    words a rounded field to type them in, which takes the keyboard when
    words are put down. Crop shows the pixels kept and Keep Whole Photo.
    Last, the number of drawings, with Remove All on the trailing edge and a
    subtitle saying they are drawn on what is sent.
  - The **footer** holds Undo and Redo (⌘Z, ⇧⌘Z) as icons on the leading
    edge, and Cancel and Done on the trailing. While the words' field has
    the keyboard, the letters, Delete and Return are typing: Return and
    Escape end it, and the next Return is Done.
  - Marks are flat: no shadow, no glow. A step is a circle of the ink with
    a white rim (a black one on white) and its number in SF Pro Rounded
    bold; words sit on a label of the ink, a white one with a hairline. An
    arrow narrows towards its tail under a solid head. Drawing explains and
    never hides: blur and pixelate are not offered, and nothing drawn counts
    on the lock.
- **No modal alerts** for things that can be said inline in the card.
- **Privacy pane.** Grouped form. First a row of three small `.bordered`
  buttons, Check All, Recommended and Uncheck All, sharing the row in equal
  parts, under the header "Hide private details" and over the footer that
  says what is checked is covered.
  Then the sixteen kinds in three sections named for their group: People;
  Money, identity and health; Orders and documents. Then a section of its
  own with one toggle, Cover everything in AI chats (off at first), over a
  footer naming ChatGPT, Claude and Gemini and saying every kind above is
  covered there, checked or not. Then one with a menu picker, Check before
  sending: In AI chats and unknown apps (at first), Every time or Never,
  over a footer saying what the card shows and that Return sends and Escape
  keeps the photos. Then one with Plain file names (off at
  first), over a footer saying pictures leave as fresh files without notes
  on when, where or with what they were made, and are named "Image" with it
  on. Then "Also hide", the
  owner's own rules: one row per rule with a 160 pt menu picker for its kind
  (Word, After a label, Pattern), a rounded field with a prompt for that
  kind, and a borderless `minus.circle` to remove it; an Add Rule button
  under them; a footer that says how a word and a label are covered. A
  pattern that cannot be read shows `exclamationmark.triangle.fill` in
  not-allowed orange beside the field and a callout line under it. Rules are
  saved 0.8 s after the typing stops, and at once when one is added, removed
  or the pane leaves, since every change reads the photos again. Then
  "Cover a folder": a toggle, Cover what lands in a folder (off at first;
  turned on, it asks for any folder not chosen yet and stays off without
  both), and two rows, Watched folder and Save copies in, each with the
  folder's name in `.secondary`, truncated in the middle, and a Choose…
  `SettingsButton`. Two folders that are the same or one inside the other
  are refused with a note. Its work is said in one note above the Dock two
  seconds after the last file of a run: how many copies were saved, up to
  three names where nothing was found, and what could not be read. Then
  "Test": Test on a Sample, a `SettingsButton` on the trailing edge
  ("Testing…" and off while it runs), over a footer that it covers a
  made-up order and speaks for that sample only; once run, the covered
  sample above it (at most 280 pt high, 10 pt corners), what was covered on
  it, and in `.secondary` what is checked and not on it. A new choice of
  kinds puts the result away. Last the Preview. The iPhone's Settings use the same three groups.
- **About pane.** The icon at 128 under its shadow, the name in 34 pt
  rounded bold, the tagline in title3 `.secondary`, the version in callout
  `.tertiary`. Then one line, "Made by" in `.secondary` before the maker's
  name in semibold, and "© year name" in callout `.tertiary` under it;
  Check for Updates… (direct edition only) as a regular `.bordered` button.
  No monogram, no card, nothing else: help lives in Support.
- **Support pane** (`Support.swift`), between Permissions and About, with
  `lifepreserver.fill` in the sidebar. A grouped form of rows, each a 28 pt
  ink tile (7 radius) with its symbol, the name with a callout line on what
  it does, and a `SettingsButton` on the trailing edge: Help & Support
  (Open: the website's support page in the Mac's language), Report a
  Problem and Suggest a Feature (Write…: an email to the support address
  with the subject and the diagnostic details filled in, room left above
  them for what happened), then Diagnostic details (Copy, reading Copied
  for two seconds): the version and build, macOS and the Mac, the language,
  and each permission's state; nothing personal. No licence credit anywhere
  in the interface: the notice lives in `LICENSE`, inside the app bundle.
- **Permissions pane** (`Permissions.swift`), in Settings between Privacy and
  About, with `lock.shield` in the sidebar.
  - A summary row first: `checkmark.shield.fill` in allowed green once all
    is given, else `lock.shield` in `.secondary`, over the promise that
    everything stays on the Mac.
  - One grouped section per permission. A row is a 24 pt symbol (or the
    browser's own icon), the name with a callout line on what it is for, and
    on the trailing edge the state and one regular button.
  - States: Allowed (`checkmark.circle.fill`, green), Not allowed yet
    (`exclamationmark.circle.fill`, orange), Not asked yet or Not open
    (`circle.dashed`, `.secondary`), in callout medium.
  - The button says what happens: Allow…, Open System Settings… once
    refused, or Open and Allow… for a browser that is not open. None shows
    once allowed.
  - Help appears only where it is needed: Reopen Snapfly under a refused
    Screen Recording, and how to add Snapfly with + under a refused
    Accessibility.
  - It reads the states every second while open, so a switch turned in
    System Settings shows at once.
  - The menu bar shows Permissions Needed… with `exclamationmark.triangle`
    at the top only after something was refused, and it opens this pane.
- **History window** (`HistoryWindow.swift`), a standard titled window
  (760 × 540, at least 480 × 360) for what left the line.
  - Day headers in 13 pt semibold `.secondary` ("Today" and "Yesterday" come
    from the system's relative date format), each over an adaptive grid of
    cards 150–200 pt wide, 16 pt apart, 24 pt around.
  - A card is the photo fitted on a 12 pt rounded fill of `.primary` at 5%,
    112 pt high, with its time under it (11 pt, `.secondary`, monospaced
    digits). On hover it lifts (1.02 and a photo card's hover shadow) and a
    22 pt accent circle with `arrow.uturn.up` says a click hangs it again.
    Its menu: Hang on the line, Send Again (it hangs, the window closes, and
    once the app in front before it is back, the photo goes in, covered;
    else it stays copied with a note), Copy, Open, Show in Finder, and
    Remove from History.
  - **Orders** groups the photos with an order, invoice or customer number
    (the first one read, top to bottom) under that number, as a `number`
    label in the day headers' style, selectable, over the same grid; the
    order with the newest photo comes first.
  - The toolbar holds a segmented Photos | Orders | Sent picker in the middle, then
    the search, Export… (`square.and.arrow.up`, Sent only) and Clear
    History…, which clears both. Empty, each page uses
    `ContentUnavailableView` (Sent with `paperplane`).
  - **Sent** is a standard `Table`, newest first: Date (day, month, year,
    hour and minute, monospaced digits), Photo, Sent to, Covered (the kinds'
    titles in `.secondary`) and Message. Its context menu has Remove from
    History. Export… opens a save panel for "Sent with Snapfly.csv".
- **Chat button** (`ChatButton.swift`), the one control that floats over
  another app's window. It shows only while photos hang and a chat app or a
  browser is in front, and it sits just above the chat's own send button.
  - A `controlGlass` capsule with a 4 pt inset. It holds the newest photo
    (26 pt, 7 pt corners, the one before it leaning behind), the count
    (13 pt semibold rounded, monospaced digits), and the paper plane in white
    on an accent circle of 28 pt, which turns into a checkmark once sent.
  - Over an AI chat with Cover everything in AI chats on, a 9 pt bold
    `lock.fill` in `.secondary` leads the count, 3 pt before it, fading in
    over 0.2 s, in both looks. The tip adds "Everything is covered in AI
    chats" on a second line, and VoiceOver hears it as the button's value.
  - A 16 pt transparent margin keeps its shadow; only the capsule takes the
    pointer.
  - Over chats it knows (`ChatLayouts.swift`), it sits at the measured spot
    of their send button: the trailing end of a centered message box (with
    the sidebar left out in windows 900 pt wide or more) or the window's
    trailing edge, above the box's top. A new chat in a browser, told by its
    address, puts it in the middle of the page. A drag wins, then the
    message box from Accessibility, then this, then the generic spot.
  - It never becomes key. A click sends, as the tag does; a drag moves it,
    remembered per app, and for a new chat apart; a press and hold (0.45 s
    without moving) opens the message bar; a right-click offers Send with a
    Message…, Put it back and Settings.
  - **Message bar** (`CaptionBar.swift`), 6 pt above the button, its
    trailing edge on the button's: a 340 × 44 capsule of the search bar's
    glass and shadow, with a 20 pt margin for it. A plain 15 pt field (Add a
    message…), the count of photos in a 12 pt semibold rounded chip on
    `.primary` at 8%, and a 30 pt circle in the chat button's own tint and
    glyph. It takes the keyboard without activating Snapfly, as the search
    bar does: Return sends the photos and then the message, Escape or a
    click elsewhere closes it. VoiceOver reaches it as an action on the
    button.
  - On macOS 15 and later a language menu sits between the field and the
    count: `globe` at 13 pt `.secondary`, or the chosen language's two
    letters in an 11 pt semibold rounded chip like the count's. Its menu
    holds As typed, then the Mac's languages, the user's own first. With
    one chosen, Return first translates the message in place, on this Mac,
    while the send circle shows a small spinner; the next Return sends what
    the field shows. The choice is kept for each chat.
  - While the field is empty, the saved messages (`bookmark`, no cross),
    then the last five messages sent (`RecentCaptions`,
    newest first, kept on the Mac) stand 6 pt above the bar in a list of the
    same width and glass with 12 pt corners and 4 pt inset: rows 28 pt high,
    `clock.arrow.circlepath` at 11 pt `.secondary`, the message in 13 pt on
    one line, truncated, and on hover a fill of `.primary` at 8% (8 pt
    corners) and an `xmark.circle.fill` in `.tertiary` that removes it. A
    click puts the message in the field, a saved one with its blanks filled
    from the newest photo (a covered kind's blank reads "…"); ↑ and ↓ step
    through the recent ones. The bar keeps its place when the list goes.
  - **Settings › Line › Saved messages**: one row per message, a rounded
    field with an example as its prompt and a borderless `minus.circle`;
    Add Message under them; a footer naming the blanks. Saved 0.8 s after
    the typing stops, like the owner's rules.
  - Hover scales it to 1.04 through `Motion.spring`, and it fades in over
    0.15 s.
  - **Settings › Line › Send button over chats** chooses:
    - where it sits: above the chat's send button, the window's bottom or
      top corner, or the screen's edge;
    - its look: photo and count, or the count and the glyph alone (a 30 pt
      circle);
    - the glyph: paper plane, arrow, share or photos;
    - **chat button tints**: the accent (the default), or system blue, green,
      purple, orange or pink, with a white glyph; or graphite, which is
      `labelColor` with a `windowBackgroundColor` glyph so it holds in light
      and dark. The owner picks it, so it is the one place a color other than
      the accent may mark a primary action.
  - Settings shows a live preview of the button.
  - In a browser it shows only on the chat websites listed in Settings, a
    grouped list of toggles with a remove button each and a field to add
    one. The chat apps are a list too: each app's 20 pt icon and name, a
    toggle and a remove button, and Add App… to choose another.
- **Check before sending** (`SendCheck.swift`), a floating card in the text
  card's look (380 pt, 20 pt corners, `.regularMaterial`, 28 pt margin) that
  shows before photos are pasted into an AI chat, or an app or website not
  in the chat lists, as Settings › Privacy chooses.
  - Header: `checkmark.shield` in the accent on its 12% circle, "Send to
    ChatGPT?" in 13 pt semibold on one line, truncated in the middle, and
    the close button.
  - One block on the reading panel's fill: the copies as they will go, up
    to four, each fitted in 76 pt with 6 pt corners and a 0.5 pt edge of
    `.primary` at 12%, 8 pt apart, then "+2" in the count's chip; under
    them, after a 10 pt semibold `.secondary` glyph, the covered line
    (`lock.fill`: "Covered: Names · Emails", "Nothing private found" or
    "Hide private details is off.") and, for photos like ones sent before,
    `paperplane.fill` with "Sent to WhatsApp · Today at 14:05", or "Sent
    before: 2 of 3" for several.
  - A caption note says why it shows: AI chats can keep what they are
    sent, or Snapfly doesn't know the place as a chat; none for Every time.
  - Footer: Don't Send (`.bordered`, Escape) and Send with `paperplane.fill`
    (`.borderedProminent`, Return), both large, on the trailing edge.
  - It takes the keyboard without activating Snapfly, as the message bar
    does, and hears Return and Escape without a focused control. A click in
    another app puts it away unsent. It sits 6 pt above the send button
    over the chat, trailing edges lined up, when that shows; else centred
    under the line's strip on the screen with the pointer, 8 pt inside it.
    It fades in over 0.15 s. Escape, Don't Send or the cross leave the
    photos hanging; Send closes it, gives the keyboard back to the chat and
    pastes 0.15 s later.
- **Capture overlay** (`Capture.swift`), the one surface that covers the
  whole screen. It shows the screens still, captured a moment before.
  - It takes the keyboard without activating the app, as the search bar does.
    Return takes the whole screen, and Escape or a right-click cancels.
  - **At rest**, the still screen is dimmed by black at 12%, and the window
    under the pointer is tinted with the accent at 22%.
  - **While dragging**, everything outside the area is dimmed by black at
    35%, and the area has a 1 pt edge of white at 90%.
  - **The size** of the area, in points, sits in a capsule under its trailing
    corner: 11 pt medium monospaced digits, white on black at 55%, 20 pt high.
  - **A hint** sits in a `controlGlass` capsule above the Dock on the screen
    with the pointer, and hides once a drag begins. It says what the choice
    is for: a screenshot, a timed screenshot or a recording.
  - The cursor is the crosshair.
- **Screenshot button** (`CaptureButton.swift`), a 40 pt circle with a glyph
  (17 pt semibold), floating
  over every app at the trailing edge of the main screen, 60% up its
  visible height, until dragged elsewhere (remembered).
  - A tag's shadow (black 18%, radius 6, y 3; none on glass under Liquid Glass) in a
    12 pt transparent margin; only the circle takes the pointer.
  - Hover scales it to 1.08 through `Motion.spring`.
  - It never becomes key. A click takes a screenshot as Settings says; a
    drag moves it; a right-click offers Choose an area, Take the whole
    screen, Record Screen, Hide Screenshot Button and Settings.
  - **Settings › Line › Screenshot button** chooses the glyph, from twelve
    in two rows of six (`camera.viewfinder`, `viewfinder`, `dot.viewfinder`,
    `plus.viewfinder`, `rectangle.dashed`, `rectangle.dashed.badge.record`,
    `crop`, `scope`, `camera.aperture`, `camera.fill`, `bolt.fill`,
    `sparkles`), and the circle: glass (`controlGlass`, `.primary` glyph)
    or one of the chat button tints with its glyph color and a 0.75 pt edge
    of white at 25%. The accent at first, so it stands out at the screen's
    edge. Settings shows a live preview.
  - While recording it is a record red circle with a white `stop.fill`
    (13 pt bold), and a click stops.
  - It is never in what is taken. Settings › Line › Screenshot button and
    the menu bar's Screenshot Button turn it on and off.
- **Capture capsule** (`Recording.swift`), for a timed screenshot and a
  recording. A `controlGlass` capsule with a 4 pt inset, centered 16 pt
  above the Dock, with a floating card's shadow (black 25%, radius 14, y 6;
  14% under Liquid Glass) and a 16 pt transparent margin for it. It fades in
  over 0.15 s.
  - **Countdown**: the `timer` symbol (13 pt semibold, `.secondary`), the
    seconds left (15 pt semibold rounded, monospaced digits, counting down
    with a numeric content transition), and a cross in a 22 pt circle of
    `.primary` at 8%.
  - **Recording**: a 22 pt record red circle with a white `stop.fill`, and the
    time so far (13 pt semibold rounded, monospaced digits, minutes and
    seconds).
  - **Note** (`Notice`): when something fails, the
    `exclamationmark.triangle.fill` symbol (13 pt semibold, `.secondary`) and
    one line of 13 pt medium text say what went wrong. It goes after 4 s or
    on a click, and VoiceOver announces it. While something is being made,
    like a GIF, a small spinner takes the symbol's place and the note stays
    until it is done.
  - **Notes, not beeps.** A failure the user would otherwise have to guess
    at gets a note. A beep is kept only for a key that does nothing where
    the keyboard is taken (the capture screens, the shortcut recorder,
    Return in a search with no results), as macOS does.
  - It never becomes key and is never in what is taken. A click anywhere on
    it cancels or stops; it is one button for VoiceOver, with a tooltip.
  - While recording, the menu bar item turns into `stop.circle`, and its menu
    starts with Stop Recording.
  - **Recording edge**: around a recorded area, just outside it, a 1 pt line
    of white at 90% inside a 1 pt line of black at 35%, so it shows on light
    and dark screens. It lets the pointer through.

### Forms and lists
- Grouped `Form` sections.
- A toggle label plus a secondary description line, as in the `Toggle` init
  with two `Text`s.
- Pickers: segmented for 2–3 choices, menu for more, and a visual tile picker
  where the choice is visual (line style).

### Time stamp

Evidence of when and where a screenshot was taken, when Stamp the date
and time is on. Drawn into a copy saved next to the screenshot, onto the
photo that hangs and into the copy that leaves the line: never into the
screenshot itself.

- **Where.** A band above the picture, as wide as it; the image grows by
  the band's height, so nothing of the screenshot is covered.
- **What.** The app icon leads in the reading direction, then up to four
  lines:
  1. the user's own words, a middle dot, then the date and the time to the
     second with the time zone, in the Mac's own format: SF Pro Semibold
     with monospaced digits, in the title colour;
  2. where the time came from: the PTB's atomic clock, or the Mac's clock
     when it could not be reached (regular, 0.86×, detail colour);
  3. the page open in the browser in front, if one was (the same);
  4. the screenshot's SHA-256 fingerprint (SF Mono, 0.8×, code colour).
  A line too long for the image ends in "…".
- **Size.** The text is 0.95% of the image's width, at least 11 px; each
  line is 1.4× its text size, the padding 0.9× and the gap after the icon
  0.7× the title size. The icon is at most three title sizes tall. A
  hairline, 1/16 of the title size and at least 1 px, separates band and
  picture.
- **Right to left.** The icon moves to the right and the lines align right.
- **No shadow, no rounded corners.** It reads as a document's letterhead,
  not as something floating.

### Signature: the line styles
- **Clothesline**: rope, clips and swing.
- **Glass shelf**: Liquid Glass, with upright photos.
- **Island**: black, from the notch.
- **Card stack**: fanned in the corner, spreading on approach.
- **Wire**: a taut, straight wire (grey 0.32, 0.9 pt, a 0.3 pt glint), the
  photos upright on clips and still; the tag clipped on as on the rope.
- **Floating**: nothing behind the photos; they float upright in a row,
  each on its own glass, the tag on its own glass after them.
- **Filmstrip**: a dark strip (grey 0.09, radius 12) with a 16 pt band of
  holes (9 × 6, 17 apart, grey 0.82) along its top and bottom; the photos
  sit between as frames, the tag's tools light on it as on the island.
- **Fan**: no holder; the photos arc down from the middle, 6 pt × the
  square of their places out (44 at most), each leaning out 4° a place
  (14° at most), like cards held in a hand.
- Settings shows them four to a row, each as a small picture.

Each style changes only what holds the photos and how they lean. Everything
else is shared.

## Do's and Don'ts

### Do:
- **Do** use system materials, SF Symbols, `Color.accentColor` and semantic
  colors.
- **Do** keep one primary action per surface, and put it on the trailing edge.
- **Do** keep corners concentric and continuous, and keep the 4 pt rhythm.
- **Do** design the empty, working, done and failed states of every surface.
  The text card shows the pattern: placeholder lines, then the result, then a
  note.
- **Do** check every change in light and dark, in German and Arabic, at all
  three sizes and in all eight line styles.
- **Do** keep new motion short (0.15–0.55 s springs or ease-out) and honour
  Reduce Motion.

### Don't:
- **Don't** make cards oversized; a card is as big as its content.
- **Don't** make buttons large without a reason. Large control size belongs
  in floating cards only.
- **Don't** put colored vertical accent stripes or side rails on cards or
  rows.
- **Don't** nest containers: no card in a card in a card. One fill level
  inside a surface.
- **Don't** exaggerate shadows or add glows. Follow the shadow table above.
- **Don't** add gradients that do no work. The brand gradient is for the icon
  only. The one exception is the tiny glass-edge highlight.
- **Don't** add badges beyond the semantic ones: pin, count, lock, copied,
  and the play button and PDF capsule that say what kind of file it is.
- **Don't** space ad hoc. Use the 4 pt rhythm, and set gaps on the stack, not
  as margins on each child.
- **Don't** use colors outside this file, or hex in views. Add a token here
  first.
- **Don't** use generic dashboard templates: no KPI tiles, no hero numbers, no
  sidebar-plus-cards web layouts.
- **Don't** add decoration without a job: no emoji as icons, no ornamental
  dividers, no confetti.
- **Don't** steal focus from the app in front, or block with a modal what a
  card can say.

## iPhone

The iPhone app (`iOS/`) is a plain SwiftUI app that follows iOS, as the Mac
app follows macOS: system fonts, colours, materials and controls, the
system's accent, Dynamic Type and Dark Mode as they come. It adds no tokens
of its own.

- Screenshots sit in a grid in the shape of a phone's screen, 10 pt corners.
- A covered screenshot shows at full width with 12 pt corners; Copy, Share
  and Save sit under it on the bar material, as bordered buttons.
- The icon is the Mac icon's picture, full bleed and opaque, since iOS rounds
  it (`scripts/make-icon.py --ios`).
- Settings opens with Check All, Recommended and Uncheck All as small
  bordered buttons sharing a row, under "Hide private details", then the
  three groups, then "Also hide": a row per rule of the owner's own, its
  kind as a menu over a field with the kind's prompt, swiped away to remove,
  and Add Rule. A pattern that cannot be read says so under its field with
  `exclamationmark.triangle.fill` in orange. Rules are kept as they change,
  and the Mac's and the iPhone's are the same kind of rule.

## Website

> **Airmail removed (October 2026).** The owner asked to drop the airmail
> look. The Mac desktop is now the default, the look switch offers it and bold
> colour, and `<html data-look>` is always set. The airmail passages below
> describe the base styles in `site.css` that those two looks restyle.

The site in `website/` (GitHub Pages) sells the app and hosts the privacy
policy and support pages that App Store Connect links to. It extends this
system to a web page. The brief and direction contract are in
`website/BRIEF.md`. Everything below is taken from what ships in
`build.py`, `static/site.css` and `static/site.js`.

- **The page is an airmail envelope.** Aerogramme paper is the ground, the
  chevron edge of an airmail envelope frames the browser window the whole
  time, every screenshot on the line is a perforated stamp held by a steel
  clip, and sending is posting: what lands in the chat is struck with a
  postmark that carries the time. Mac windows stay native on it; they are
  what the envelope carries. There is no wallpaper, no wash and no scrim:
  words sit on the paper in ink.
  - **The chevron edge** (`body::after`): fixed over the whole window at
    z-index 300, `--edge` thick (12 px; 8 px at 640 px and below), drawn as
    a ring by a mask, so the page scrolls under it and nothing is clicked
    through it. Stripes run at −45°: `--stripe-a` 18 px, `--stripe-gap`
    9 px, `--stripe-b` 18 px, `--stripe-gap` 9 px (a 54 px repeat). The
    menu bar sits `--edge` down from the top, inside it. Print leaves it
    out.
  - **Paper and grain**: the body is `var(--grain)` over `--ground`
    (`--paper`). The grain is an inline SVG fractal noise (base frequency
    0.9, two octaves, a 220 px tile), tinted with the theme's ink at 10%
    alpha on light paper and white at 7.5% on dark. `--paper-2` is the
    paper a shade deeper: the envelope's flap and the background behind the
    icon stamp.
  - Below the first view, sections sit straight on the paper, 96 to 168 px
    apart (`clamp(96px, 12vw, 168px)`), 72 px on phones.
  - Each demo is a native object on that paper:
    - keycaps, with a postmark struck across them;
    - Desktop files that fly onto a rope and become stamps as they land;
    - Snapfly's own Settings window, on its Privacy and Line panes, with
      the line-style tiles;
    - the photo's menu opening from a stamp on a line;
    - a whole Mac desktop to try Snapfly on (below);
    - the Hide Part window, said in a sentence (below).
  - **How a screenshot travels** (`section_story`), between the send
    section and the desktop to try: five moments of one screenshot, each a
    title (`clamp(1.5rem, 2.4vw, 2rem)`, 800) and a line beside a small Mac
    screen, the sides alternating; one column at 960 px and below, the words
    above the screen.
    German only for now, at the owner's request (`NEW_PARTS_LANGS` in
    `build.py`).
    - **The screen** is drawn at 460 × 280 and scaled as a whole to its
      column, 460 wide at most: `scale(tan(atan2(100cqw, 460px)))`, so CSS
      divides the two lengths. It takes the desktop demo's tokens (`--d-*`,
      set on `.story` too): one solid desktop with its grain, a 14 radius, a
      hairline and shadow 2, a 20 px menu bar in glass 1 with four menu
      titles, Snapfly's mark and the clock. In right-to-left pages it
      mirrors.
    - **The moments.** Take it: the shortcut in a dark key strip (22 pt
      keys, 82% black), pressed 140 ms apart, then a dashed accent selection
      dragged corner to corner over an invoice window, and the flash. It
      hangs: the line comes down from under the menu bar (0.6 s) and the
      stamp drops onto its clip (`hang-in`). Private details get covered:
      cover ink grows over the name, the street and the email, 140 ms
      apart, then the lock badge. It flies into the chat: its paper plane
      is pressed, and the stamp takes off up and toward the reading end at
      −9° and lands in Lena's chat (820 ms on `ease.flight`) along a dashed
      flight path, and is struck with a postmark. The line tucks itself
      away: the empty line goes back up (0.5 s, ease-in).
    - Its stamps are the page's own, 7 px padding: perforated in airmail;
      glass without the blur in classic and white cards in bold, both 4 px
      padding at a 10 radius. The postmark and the flight path belong to
      airmail. In bold the section is a field and, in light, its screens
      take the sheet.
    - Each moment plays once, when three quarters of its screen is in view
      above the window's bottom quarter; until then it holds its first
      frame. Without scripts, with Reduce Motion and in print, each shows
      how it ends.
  - **The desktop to try Snapfly on** (`section_capture`): a Mac screen
    with no laptop round it, so its content gets all the room. It is its
    own small system: every value inside it is a `--d-*` token on
    `.desk-stage`, and nothing inside uses a free value.
    - **The screen**: a 16 radius, a hairline and shadow 3, nothing else.
      Its desktop is one solid colour, as macOS offers, under a fine grain
      (8%, 10% in dark): `--d-wall-1`, `-2` and `-3` are equal. Lavender
      `#C4BDE6` (`#2C2652` in dark) in Original Sunset, sage `#A3CBBF`
      (`#11393A`) in Emerald Petrol, warm sand `#EFD2C1` (`#2B211C`) in
      Signature Orange.
    - **Three layouts**, each drawn at a fixed size and scaled as a whole,
      so nothing inside ever collides:
      - wide, 1280 × 800, from 1280 px: a floating Dock, the guide beside
        the thing it points at;
      - medium, 1024 × 720, from 768 px: a larger window, a compact Dock
        (40 pt icons), the guide under the screen, as wide as it and low;
      - tall, 360 × 572, below 768 px: the window nearly fills the screen,
        a short menu bar, the Dock a bar under the screen with no
        magnifying, the guide a sheet just above that bar. Its buttons are
        44 pt and its words 15 pt.
      - The screen, and on medium the guide too, fits the height of the
        browser window, never narrower than 960 px (wide) or 720 px
        (medium). No horizontal scroll; safe areas kept.
    - **Type**: the system stack at 11, 13, 15, 17 and 22, weights 400, 500
      and 600, line height 1.4 (1.2 on titles), tabular figures.
    - **Spacing** 4, 8, 12, 16, 24, 32, 48, 64. **Radii** 6 (controls), 10
      (menus, cards, rows), 14 (windows), 16 (the screen) and full.
    - **Colour**: ten greys, `g0` to `g9` (#FFFFFF to #1D1D1F; in dark
      #1C1C1E to #F5F5F7), one accent #0071E3 (as text #0066CC, #4DA3FF in
      dark), success #1E8E3E (#30D158 in dark), warning and error. Emerald
      Petrol turns the accent to `#168176` (text `#0E6B62`, `#5CCDB8` in
      dark), Signature Orange to `#C7461C` (text `#B23E17`, `#FF8754` in
      dark); the greys stay. Every text pair is at least 4.5:1 in both
      modes, glass included.
    - **Glass**, two levels only: 64% (menu bar) and 90% (Dock, menus,
      notes, guide), blurred 20 px at 180% saturation, with a hairline.
      Without `backdrop-filter`, solid `g1` and `g0` instead.
    - **Shadows**: 1 for controls, 2 for menus, notes, the Dock and the
      guide, 3 for windows and the screen.
    - **Motion**: 120, 200 and 280 ms; in `cubic-bezier(0.2, 0.8, 0.2, 1)`,
      out `cubic-bezier(0.4, 0, 1, 1)`. Only transform and opacity move.
      Nothing blinks, pulses or glows: motion only answers an action.
      Windows fade and scale as they open and close, shrink toward their
      Dock icon to minimize, and come to the front. Reduce Motion keeps
      the fades alone.
    - **What is on it**: a browser on a flight search, the visual focus
      (its sort menu orders by Price, Duration or Departure, rows slide to
      their place, the cheapest is marked in success green), and Messages
      with Lena. Nothing else, nothing as a filler. The traffic lights, the
      sort button and the send button are real buttons.
    - **The Dock**: browser, Messages, a divider, the trash. One icon style:
      48 pt squircles on a 64 grid, a top-lit gradient, a 10% hairline and
      one shaded glyph; the trash shows papers when full. Glass at 90%, a
      hairline and shadow 2, no gloss. A fine pointer magnifies the icon
      under it with a cosine falloff to its neighbours (a scale from the
      bottom, so nothing moves the layout). A tooltip shows after 300 ms,
      and on keyboard focus. Pressed is 0.95, the focus ring 2 px with a
      2 px offset, and an open app has a dot under it. It is a toolbar the
      arrows move through. The trash opens a small popover with Put Back
      and Empty Trash.
    - **Snapfly on it**: the photo on the line in the menu bar opens Snapfly's real
      menu (Take Screenshot, with Timer › 3, 5, 10 Seconds, Record Screen,
      Screenshot Button, Take everything down), the screenshot button sits
      at the trailing edge, and the line hangs under the menu bar. Cards
      copy on a click, go to the trash, or go to Lena with the send button
      over the chat; ⌃⌥S, ⌃⌥R and ⌘V work while the screen is in view. The
      capture screen takes a drag, a click on a window, Return for the
      whole screen, or the arrows and Space for a window; Escape cancels.
      What is taken is the screen's own SVG with its `viewBox` set to the
      area, so it is exact, and a click on it copies a real PNG. Snapfly's
      own parts are never in it.
    - **Notes**: one line for each action, above the Dock, in glass with
      shadow 2: "Screenshot taken", "Copied", "Sent to Lena" and so on,
      each with Undo where it can be undone (or Paste in Messages, or Open).
      They go after 4 seconds, wait while the pointer or the keyboard is on
      them, show two at most, and are read out by a polite live region.
    - **The guide**: a card in 90% glass (10 radius, 280 wide, an arrow
      toward the thing) with "Step 2 of 6" and a progress bar, a title of
      six words at most, two sentences at most, Show me, Skip and a close
      button. A still 2 px accent ring with a 6 px soft halo marks the
      thing to try; a Dock icon carries the ring itself. The steps: take a
      screenshot, choose an area, copy it from the line, open Messages,
      send everything, Snapfly's menu; then "You did it" with Start over
      and Download for Mac. Doing a step moves on; Show me does it with a
      pointer. Return is Show me, the arrows go back and forward, Escape
      closes. It never covers a window, the Dock or the screenshot button,
      keeping 8 pt from each: beside the thing, else the nearest free spot
      either side of the window. It starts once by itself when half the
      screen is in view, without taking focus; "Start the guide" under the
      screen starts it again.
    - On the paper beside it, a handstamp says "Screenshot taken" in the
      page's language (`.cap-stamp`, 26 px above it, turned 4°).
  - **Eight ways to hang** (`section_styles`): three stamps on a stage over
    Snapfly's Settings window on its Line pane, whose eight style tiles,
    four to a row, set `data-style` on the section. Each style moves the
    same three stamps (0.55 s, `--ease-out`) and shows what holds them:
    the rope (swaying), the shelf, the island, the stack and its count, as
    before; the **wire**, a 1.5 px straight line in `--rope` fading at both
    ends, the stamps upright on their clips; **floating**, nothing behind
    them, a deeper lift and a ±3 px drift (6 s); the **filmstrip**, `#161616`
    with a 12 radius, a white hairline at 10% and rows of 9 × 6 px holes
    (`#D2D2D2`, 17 px apart) 5 px inside its top and bottom edges; the
    **fan**, the middle stamp highest and on top, the outer two 18 px lower
    and turned 9° outwards (mirrored right to left). The tiles draw each
    style small; for the wire, floating and the filmstrip their cards are
    16 × 11, so the gaps between photos show. On phones the outer stamps
    sit wider apart and the filmstrip spans 80%. Reduce Motion stops the
    sway and the drift.
  - **Hide Part** (`section_say`): the editor's window as the app opens it,
    under the centred copy and 880 px wide at most. On the leading side the
    canvas (`--fill`, 24 px margin) with a bank transfer on it, under a
    `0 6px 14px` shadow at 18%; on the trailing edge the inspector, 300 px,
    the groups of a settings pane over a footer: "Say what to hide" with
    the sparkles field, Hide and the three examples as its rows and the
    note under the box; "By hand" with the hint as its subtitle and Remove
    All; then Cancel and Done. On a phone (640 px and below) the inspector
    moves under the canvas. Covers are cover ink at a 3 radius, one per
    line of a detail, growing in from the reading start 45 ms apart;
    hovered, they show an eye and an accent ring, and a click removes one.
    A drag draws a dashed accent box. A few words in English, German and
    Arabic stand in for Apple Intelligence; Done adds the lock badge. A
    handstamp with the app's "Hide Part…" ends the copy (`.say-stamp`,
    28 px below it, turned −5°).
  - **Private by design** (`section_private`): the Settings window on its
    Privacy pane, with a handstamp of `stamp_covered` ("Private details
    covered") struck over its trailing top corner (38 px above, 14 px
    past the edge; 4 px inside it on phones).
  - **Start in four steps** (`section_start`), before the close: four
    perforated stamps, each with a 44 pt icon tile in the brand gradient
    (12 radius, the brand glow), its title (18 px, 750) and a line (15 px).
    - Each is the stamp component below: 26 px padding (28 at the
      bottom), a drop shadow `0 6px 10px` at 18% of the shade, and a
      printed frame, a 1 px hairline of `--post-fill` at 30%, 12 px inside
      the perforations.
    - Its number is the stamp's value: printed in `--post-fill` in the top
      trailing corner (18 px down, 22 px in), 40 px, weight 800, tracking
      −0.04em, tabular figures. The number stays out of the reading order.
    - Above 960 px they hang on a rope like the photos: each by its clip at
      the rope's sag, tilted −1.2°, 0.8°, −0.6° and 1.1°, straightening
      under a fine pointer (0.5 s), and dropping 40 px onto its clip when
      it arrives. Two across up to 960 px and one on a phone (640 px and
      below, 12 px apart), as plain stamps without the rope.
  - **The hero's chat** carries the chat button and its message bar as
    "Chat button" above has them, over the chat's own send button. Its
    photos are the line's newest two. Hold it, or right-click it for Send
    with a Message…; the photos land as one album and the message right
    under it. The hero's photos also reorder by a sideways drag, lifted
    under the pointer (1.06), and by Option and an arrow. One photo is
    already posted in it when the page opens (124 px wide, postmarked),
    except where the chat is too small to hold it clear of the button
    (1100 px wide or 860 px tall and less).
  - The privacy and support pages are documents on the paper. On the
    support page each question leads with its glyph (22 px, in the accent,
    from Lucide in the site's single stroke), and its answer lines up under
    the words, 38 px in. German only for now (`NEW_PARTS_LANGS`).
- **The postal pieces.** All of them print in the theme's postal ink and
  are hidden from assistive technology; the words they carry are said
  elsewhere on the page.
  - **The stamp** (`.photo`, `.step`): white paper (`--stamp`) behind the
    picture or the words, with a perforated edge cut by a mask: 5 px of
    paper, holes 3.2 px in radius on a 9.6 px pitch (`round`, so they fit
    every side evenly). Its shadow is a `drop-shadow`, so it follows the
    perforations. A photo stamp has 9 px padding, its picture a 2 radius,
    and lifts `0 4px 6px` at 22% of the shade, `0 9px 12px` at 26% and
    103.5% under the pointer. Desktop files that land on a rope become
    smaller stamps: a 4 px border, holes 2.2 px on a 6.6 px pitch.
  - **Clips**: steel, 10 × 24 with a 3 radius, a horizontal gradient of
    `#8E949F` (2 px at each side) and `#D4D7DD`, a dark 2 px bar 9 px down,
    and a `0 1px 1.5px` shadow. Each stamp hangs from one, 12 px above its
    top edge, at the rope's sag. The rope is a 2 px `--rope` stroke.
  - **The postmark** (`postmark()`): an SVG 260 × 120. A ring of radius 53
    (2.6 stroke) round a ring of radius 36 (1.4), "SNAPFLY · PAR AVION ·"
    twice round a path of radius 42 (9.5 px, 700), the date in the middle
    (15 px, 800) over the time (14.5 px, 700, in SF Mono), and five wavy
    cancellation lines (2.4 stroke, 13 apart) running on from the ring.
    - It prints in `--post-mark` at 95% opacity, rotated −8° (−10° in the
      chat, −12° on the keys), and draws through the INK filter.
    - **The INK filter** (`#ink`, once per page): fractal noise (0.8, two
      octaves, seed 7) speckles the strokes where the stamp met the paper
      unevenly, and a 1.4 displacement roughens their edges.
    - Over a picture (on the line and in the chat) it gets a white halo, a
      1 px and a 0.5 px white drop shadow at 90%, so it reads on any
      screenshot.
    - Its figures are plain and the same in every language, as a post
      office's: the date as dd.mm.yy and the time as HH:MM, both two
      digits (16.10.26, 14:38). `site.js` writes the visitor's date and
      time into every postmark and refreshes them every 15 s; one struck
      on a sent photo keeps the time it was sent.
    - In right-to-left pages the drawing mirrors, so the waves run toward
      the reading end, and its words are mirrored back to read.
    - It is struck across the line's second stamp (115% of the card
      width), across the keycaps, across the icon stamp on the envelope,
      and on every photo that lands in the chat (172 px; 150 px on the one
      posted before the visit).
  - **The airmail label** (`airmail()`): the page's language large, the
    other three under it, from `AIRMAIL` in `content.py`: By Air Mail,
    Luftpost, بالبريد الجوي, Par Avion. White capitals on `--post-fill`,
    a 4 radius, 11 × 18 px padding, ringed in 3 px of paper and 2 px more
    of ink, a soft shadow, and stuck at −4°. The large line is
    `clamp(18px, 1.7vw, 25px)`, weight 800, tracking 0.07em; the small
    one 11 px, 650, tracking 0.14em, at 92%. Arabic is never tracked. On
    a wide page it sits under the trailing end of the line, above the
    chat; at 900 px and below it is in the flow, at the trailing side.
  - **The handstamp** (`handstamp()`): a rubber stamp. Tracked capitals in
    `--post` (13 px, 800, tracking 0.16em; Arabic 15 px, untracked) inside
    a double rule, a 2.5 px border and a 1.5 px outline 3 px outside it,
    a 3 radius, 6 × 12 px padding, at 90% and struck a little crooked
    (−6° by default, each placement its own angle).
  - **The tag at the end of the line**: Send all, a 58 pt circle in
    `--post-fill` (50 pt on phones) with the paper plane, ringed in 3 px
    of paper and 2 px of ink. Under it, its name as a small label: tracked
    capitals (11.5 px, 750, 0.1em) in `--post` on the surface, a 1.5 px
    inset rule and a 3 radius. Photos sent together land in the chat as
    one album bubble.
  - **The envelope** (`.envelope`, the privacy section "No account…"):
    white surface paper with a 6 radius and the float shadow, inside its
    own chevron border (`clamp(10px, 1.2vw, 14px)`; stripes 15, 7, 15,
    7 px). The app icon is its stamp, in the top trailing corner turned 3°,
    with a postmark struck across it. The points are a heavy display list
    (`clamp(2.6rem, 6vw, 5rem)`, tracking −0.015em) kept clear of the
    stamp. On phones the stamp sits above its words, 84 px wide.
  - **The envelope back** (`.envelope-back`, the close): the same paper and
    border, at most 900 px wide, its flap a triangle in `--paper-2` with a
    hairline folded down to a point, `clamp(110px, 13vw, 170px)` deep.
    The app icon seals it at the flap's point; the heading, the download
    badge and the note sit below the seal.
  - **The seams** between sections: a tear line of perforations across the
    sheet (holes 2.4 px in ink at 22%, 12 px apart, inside the gutters).
    Before the two envelopes (the privacy section and the close) an
    airmail ribbon instead: 6 px tall, a 3 radius, stripes 9, 4, 9, 4 px.
  - **The flight path**: a dashed curve from the line down to the chat, a
    2 px `--post` stroke at 55%, dashes 1.5 on 9 with round caps. It is
    hidden at 960 px and below.
  - **The steel clips, stamps and postmarks are the world's own devices**;
    chevron stripes, tilted labels and crooked stamps belong to it. The
    app's rule against coloured stripes on cards is about the app's cards,
    not this edge.
- **Brand themes.** The site has three complete looks, at the owner's
  request, and the visitor picks one; light or dark stays the system's, so
  there are six in all. Each is the same envelope in its own paper, edge
  and ink.
  - **Original Sunset** (the default).
    - Light: paper `#ECEBFA` (lavender aerogramme), `--paper-2` `#E1DFF5`;
      edge coral `#FF5E62` and violet `#5B2BB8` on white; postal ink,
      `--post-fill` and `--post-mark` all `#5B2BB8`; stamp `#FFFFFF`;
      accent `#5B2BB8` (white on it 8.5:1); link `#4B22A0`; ink `#1F1646`
      (14.1:1), secondary `#4E4775`; rope `#3A2F66`; badge `--post-fill`.
    - Dark: a night sheet `#15122B` (`--paper-2` `#1D1938`); edge
      `#FF6B6E` and `#7B52E8` on `#EDEAFF`; postal ink `#B39CFF`,
      `--post-fill` `#6A3FD8` (white on it 6.3:1), `--post-mark`
      `#8462F0`; stamp `#F7F6FF`; accent `#6A3FD8`; link `#BCA8FF`; ink
      `#EEECFF`, secondary `#B4AEDB`; rope `#CFC6F5`.
    - Amber, coral and violet stay the brand gradient on icon tiles.
  - **Emerald Petrol**.
    - Light: mint paper `#E6F2EE` (`--paper-2` `#D8EBE4`); edge teal
      `#168176` and petrol `#062F31` on white; postal ink, fill and mark
      Emerald `#07514E` (white on it 9.1:1); accent Refined Teal `#168176`
      (white on it 4.7:1), as a Mac takes on its accent colour; link
      `#07514E` (8.0:1); ink `#062F31`, secondary `#2F5554`; rope
      `#062F31`; badge `--post-fill`.
    - Dark: deep petrol paper `#0A1E1F` (`#0F2829`); edge `#1E9A8C` and
      mint `#8FD6C4` on `#E8F3EF`; postal ink `#8FD6C4`, `--post-fill`
      `#168176`, `--post-mark` `#23A08F`; stamp `#F5F8F5`; accent
      `#168176`; link `#8FD6C4`; ink `#E7F5F0`, secondary `#9FC7BC`; rope
      `#B8DED2`.
    - Shadows are tinted petrol; brand tiles go `#3FAE9C` to teal to
      emerald.
  - **Signature Orange**: one confident colour used with precision.
    - Light: warm white paper `#FAFAF8` (`--paper-2` `#FFEFE6`), a warm
      grain; edge Primary Orange `#EC632C` and Premium Black `#171717` on
      white; postal ink, fill and mark Deep Orange `#C7461C` (white on it
      4.9:1); accent `#C7461C`; link `#B23E17` (5.6:1); ink `#171717`,
      secondary `#4A4542`; rope `#171717`; badge Premium Black.
    - Dark: Premium Black paper `#141312` (`#1E1B19`); edge orange
      `#EC632C` and Soft Peach `#FFE4D7` on `#2A2522`; postal ink
      `#FF8754`, `--post-fill` `#C7461C`, `--post-mark` `#E8642E`; stamp
      `#FAFAF8`; accent `#C7461C`; link `#FF8754`; ink `#F5F5F7`,
      secondary `#B5AFA9`; rope `#FFE4D7`; badge Deep Orange with a peach
      hairline (`rgba(255, 196, 170, 0.45)`).
    - Shadows are warm brown; brand tiles go `#FF8754` to Deep Orange.
  - **Stays the same in all three**: windows, system controls' shapes, the
    traffic lights, status colours, cover ink, the steel clips, the
    screenshots' content and the app icon. Dark shadows are black in all
    three.
  - **Tokens.** Everything a theme changes is a custom property on
    `:root`: the paper (`--paper`, `--paper-2`, `--ground`, `--grain`),
    the edge (`--stripe-a`, `--stripe-b`, `--stripe-gap`), the postal ink
    (`--post` for lines and labels on paper, `--post-fill` as a surface
    under white words, `--post-mark` for postmarks), `--stamp`, accent,
    link, ink, fills and hairline, menu bar and menu colours, rope, the
    shadow tint (`--shade`, `--shade-deep`, as r g b), the brand gradient
    and its glow, the badge (`--badge-bg`, `--badge-edge`), the line-style
    tiles (`--tile-*`) and what sits straight on the paper (`--on-wall`,
    `--on-wall-2`, `--kbd-wall-*`, `--pill-*`, `--file-shadow`,
    `--shelf-*`). Each theme overrides them on `:root[data-brand="…"]`, in
    light and in dark. `--edge` and the radii (`--r-card` 16,
    `--r-inner` 12, `--r-window` 18) are shared.
  - **The switcher** sits in the menu bar before the language menu: a
    small well (`fill-2`, full radius, hairline) with three 14 pt swatches
    in 30 × 22 cells, each its theme's edge in small (stripes 3, 1.5, 3,
    1.5 px at −45°, the two edge colours on white), and a raised thumb
    (white, or white 20% in dark) under the chosen one that slides across
    in 0.45 s. The order is Original Sunset, Emerald Petrol, Signature
    Orange. A swatch grows to 112% under the pointer and to 90% when
    pressed; the ones not chosen sit at 86%. Its name shows in a help tag
    after 0.45 s, or at once on keyboard focus. It is a radio group: Tab
    reaches the chosen swatch, the arrows choose the next one and wrap
    round, in the reading direction. On touch the swatches are 32 × 28
    with a 44 pt tall target. With a mouse they keep their 30 × 22 cells,
    and the target reaches a point past each edge: 24 pt tall, as WCAG
    asks.
  - **The look switch** sits just before it, at the owner's request, so a
    visitor can go back to the site as it was before the envelope, or on
    to the bold colour look: a well of the same make with three 30 × 22
    cells and the same sliding thumb.
    - Airmail first (the default): a white envelope 18 × 13 inside a
      2.5 px chevron border (coral `#FF5E62` and violet `#5B2BB8`, 2, 1,
      2, 1 px at −45°), radius 2.
    - Then the classic Mac desktop: an 18 × 13 sunset wallpaper (`#FFC45C`
      to `#FF5E62` to `#B234D6`, 140°) under a white 80% menu bar 2.5 px
      tall, radius 3.
    - Then bold colour: an 18 × 13 coral `#FF5E62` field with two bars of
      type in `#120708` (10 × 2.5 and 7 × 2.5 px, 3 px in), radius 3.
    - The pictures keep their colours in every theme. Names: "Airmail",
      "Mac desktop" and "Bold colour" (Luftpost, Mac-Schreibtisch,
      Kräftige Farbe; البريد الجوي, سطح مكتب الماك, اللون الجريء), under
      the group label "Design". Grow, press, help tag, arrows and touch
      size are the swatches'.
  - **The classic look** is the site as it stood before the airmail
    envelope: the brand gradient as the Mac desktop, glass photo cards,
    washes and scrims, in all three themes, light and dark.
    - `static/classic.css` holds it: the earlier `site.css`, every rule
      scoped to `<html data-look="classic">`, and loaded after
      `site.css`. The page's own token blocks carry the attribute outright,
      so they outweigh `site.css`'s tokens; every other rule wraps it in
      `:where()`, so it keeps its weight and wins by coming later.
    - A last block turns off what only the envelope has (the edge, the
      perforations, postmarks, labels, handstamps, the flight path, the
      envelopes and the posted photo) and undoes what the envelope added
      to shared parts, so the classic look matches its old captures pixel
      for pixel.
    - New shared rules that must hold in every look are written with a
      leading `:root`, which outweighs `classic.css`; the menu bar's
      narrow-screen rules are some.
  - **The bold colour look** is the third, chosen by the owner as a
    luxury, modern brand look: one confident colour field per theme, giant
    type, the screenshots dealt onto the line like cards, and a band of
    what a screenshot can do running across the foot of the first view.
    Mac windows on it stay native.
    - `static/bold.css` holds it, every rule scoped to
      `<html data-look="bold">` and loaded after `classic.css`. Like the
      classic look it restyles the airmail page's own parts and turns off
      what only the envelope has.
    - Its tokens, in light: `--field`, the theme's colour (`#FF5E62`,
      `#5CC9B2`, `#EC632C`) under two soft radial glows (`--glow-a`,
      `--glow-b`); `--type`, the words on it (`#120708`, `#062F31`,
      `#171717`), and `--type-2`, the same at 78–88%; `--sheet`, the quiet
      ground between (`#FFF4EE`, `#EEF8F4`, `#FFF6F0`); `--night`, the
      black sections, the band and the footer (the type's colour), with
      `--night-ink` and `--night-ink-2` on them; `--mark`, the field's
      colour where it marks something on black; `--pill` and `--pill-ink`
      for the download and the send buttons.
    - In dark the field turns near black (`#0F0C0D`, `#0B1213`, `#121110`)
      and the theme's colour becomes the type (6.5, 9.4 and 5.7 to 1); the
      night sections, the band and the footer take the theme's colour,
      with black words on them. Every text pair is at least 4.5 to 1.
    - Down the page: field (first view), sheet (send), field (how a
      screenshot travels), night (try it),
      sheet (Desktop), field (private), sheet (say), night (menu), sheet
      (line styles), field (no account), sheet (steps), field (close),
      night (footer).
    - Type: the headline at weight 800, −0.06 em, line height 0.86, up to
      7.5 rem (`min(7vw, 10vh)`), 12.5 ch wide; headings 800, −0.055 em,
      up to 5.75 rem, or 4.25 rem beside a window; "No account…" up to
      8 rem. Arabic keeps 0 tracking and a 1.12–1.15 line height.
    - Parts: the photo cards white at radius 16 (their pictures 11) with a
      crisp shadow and no perforations; the download a full pill in
      `--pill`; the send-all button a `--pill` circle ringed in the field;
      keycaps flat with a 2 px border and a 6 px foot; the four steps white
      cards at radius 22 with a 2 px ring in the type's colour; a dot grid
      (1.5 px dots every 14 px, 30%) in a corner of the private and "no
      account" fields, off on phones.
    - The band: `--night`, 58–78 px tall (54 on phones), the app's own menu
      words at 1.25–1.75 rem, weight 700, between four-pointed stars in
      `--mark`. Screen readers skip it; the menu section says the same.
    - The menu bar: the field at 92% over a 1.5 px rule in the type's
      colour; the theme swatches solid dots of their colour. At 380 px and
      less it keeps a 10 px margin of its own, having no edge to sit in.
    - Motion (deal, rise, run) is in `MOTION_SYSTEM.md`. Reduce Motion
      stops the band and every arrival.
  - Each look has its own browser bar colours: classic
    `#F5F5F7`/`#161618`, `#F5F8F5`/`#081819`, `#FAFAF8`/`#121211`; bold
    the field, `#FF5E62`/`#0F0C0D`, `#5CC9B2`/`#0B1213`,
    `#EC632C`/`#121110`.
  - **No wrong flash**: the first script in `<head>` reads the choices
    (`snapfly-brand`, `snapfly-look`) and sets `data-brand` and
    `data-look` before the page paints; both switches only appear once
    scripts run. Changing look spreads like changing theme. Changing theme spreads the new
    one over the page in a circle from the swatch that was chosen (0.7 s
    on `--ease-out`, reaching the farthest corner last); with Reduce
    Motion, or without the View Transitions API, it changes at once. The
    browser bar colour follows the paper (`#ECEBFA`/`#15122B`,
    `#E6F2EE`/`#0A1E1F`, `#FAFAF8`/`#141312`). Another open tab follows
    the change, at once.
  - Below 900 px the menu bar lets the clock and the language's name go;
    at 720 px and less it keeps Snapfly's icon and hides its name from
    view (it is still read out). On phones (430 px and less) it packs its
    items 2 px apart, its links 6 px in, and both switches' cells 26 px
    wide, so everything fits in every look and language. At 400 px and
    less Support leaves the bar (it stays in the footer); at 380 px and
    less the gaps go and the links sit 4 px in; at 340 px and less the
    cells are 24 px.
- **Everything on the paper that is not postal is native.** It follows
  this file's tokens:
  - the menu bar: 46 px, paper at 86% blurred 20 px, a hairline;
  - corner buttons on the stamps (22 pt discard, 30 pt accent send);
  - cover ink;
  - context menu: 13 radius, 7 radius rows, accent highlight;
  - segmented control;
  - switches and checkboxes in the accent;
  - windows with traffic lights at an 18 radius and the float shadow.
- **One exception to "corner buttons show on hover":** the paper plane on
  each hanging stamp always shows on the site. The page has to invite the
  first click, and phones have no hover.
- **Buttons.** The download link is a badge like the stores' own, at the
  owner's request, printed in postal ink inside a paper ring: `--badge-bg`
  (`--post-fill`; Premium Black in Signature Orange light, Deep Orange in
  its dark), a 12 radius, at least 60 tall, an inset 1 px hairline
  (`--badge-edge`), then 2 px of paper and 2 px more of the badge colour
  round it, and a `0 12px 24px` shadow at 24% of the shade. A solid white
  Mac 34 wide, then two lines, "Download for" at 12 (13 in Arabic, 500)
  over "macOS" at 24 (650). Its focus ring is 3 px of `--post`, 6 px out.
  No Apple logo: Apple keeps it for its own badges, and the real App
  Store badge goes beside it once Snapfly is in the store. Other primary
  buttons are pills in the accent with white text, at least 48 tall.
- **Type.**
  - The system stack only: SF Pro and SF Arabic on Apple devices, SF Mono
    (`ui-monospace`) for the postmark's time. No web fonts, so nothing is
    fetched from another host.
  - Headlines are heavy, weight 800, in ink. The hero runs to 5.6 rem
    (`clamp(2.6rem, min(5.6vw, 8.8vh), 5.6rem)`, line height 0.98,
    tracking −0.035em, at most 13 characters wide); section heads to
    3.5 rem (line height 1.04, tracking −0.03em); the close to 4.2 rem.
    Arabic is never tracked and gets a taller line (1.2 to 1.3).
  - German headlines step down a size for long words (the hero to
    4.6 rem, 15 characters wide).
  - Postal labels are tracked capitals: the airmail label (0.07em and
    0.14em), handstamps (0.16em), the Send all label (0.1em).
  - Body text is 17 px at 1.5; lead text `clamp(1.05rem, 1.3vw, 1.2rem)`
    in the secondary ink.
- **Motion.** Things are struck or flown, never floated.
  - The signature move is the paper plane: the stamp takes off up and
    away, as on the icon, then lands in the chat while the line closes
    the gap, and a postmark is struck across it with the time it was sent.
  - **The strike**: 500 ms on `cubic-bezier(0.2, 0.9, 0.3, 1.15)`, from
    118% and turned 6° further, landing with a small overshoot. The
    airmail label strikes from 115% and 5° further.
  - **The first view arrives once**, and never again, so photos hung later
    just hang. The rope draws across (0.9 s, from the reading start), the
    photos drop onto it one after another (110 ms apart from 350 ms) and
    swing to rest on their clips, each swing smaller (1.2 s), the tag
    hangs last (800 ms). The headline, the line under it and the download
    badge rise 22 px out of a 10 px blur (0.9 s, 0.1 to 0.34 s in), and
    the chat opens like a Mac window, up 32 px from 95% (1 s at 0.45 s).
    Then the post: the flight path draws toward the chat (0.9 s at 1 s),
    the airmail label is struck (1.25 s) and the postmark on the second
    stamp is struck (1.6 s). All on `--ease-out`
    (`cubic-bezier(0.16, 1, 0.3, 1)`) but the strikes.
  - **Below the first view, each thing arrives once as it comes into
    view**, by what it is: headings rise 26 px out of a 10 px blur, words
    rise 18 px, windows and the demo screen open from 95% and 44 px down,
    the four stamps come in as a list (98%, 28 px), each 90 ms after the
    one before, four at most. 0.8 s for opacity and blur, 1 s for
    movement. Handstamps and postmarks are struck as they come in (from
    118%, 6° further, 0.5 s on the strike curve, opacity in 0.2 s). Only
    what starts out of view waits; nothing is hidden without `site.js`,
    and print shows everything.
  - Every photo that lands in the chat settles from 96% (0.35 s) and is
    struck with a postmark 120 ms later.
  - Everything else plays once when seen: the Desktop sweep and the
    keycaps.
  - **Presses and hovers.** A press answers at once (0.06 s) and letting
    go eases back: a photo gives to 98%, a corner button to 88%, the pill
    buttons to 96%, Send all to 96%, the menu bar's items highlight.
    Hover that raises or grows something is only for a pointer that
    hovers, so a tap on a phone leaves nothing raised.
  - **Nothing teleports.** An FAQ answer slides open and closed (0.35 s)
    where the browser can size it, and opens at once elsewhere. The chat's
    hint folds away with its gap (0.26 s) when the first photo lands.
  - Photos sway 1.1° each way (5.6 s), and pause while their line is off
    screen.
  - Reduce Motion turns flights into fades and stops the sway, every
    arrival and every strike: postmarks and labels are simply there. On
    the desktop to try Snapfly on, only fades are left.
- **Phones** (640 px and below): the edge is 8 px; sections are 72 px
  apart; the line holds two stamps 100 px wide; the airmail label sits in
  the flow under the line, at the trailing side (from 900 px down), with
  smaller words (17 and 9.5 px); the envelope's stamp sits above its
  words; long centred words read from the start of the line; and the
  Desktop's files sit right under the rope, above the words, so the sweep
  is a short hop up and never crosses the text.
- **Images.** The PNGs in `website/static` come from the app icon, drawn by
  `website/make-images.py`. `og.png`, the picture shown when a link is
  shared, still shows the old gradient wallpaper with the icon; it waits
  for the owner. Everything else is inline SVG drawn in `build.py`.
- **Words.** Labels the app shows come from its `Localizable.strings`.
  Everything else is in `website/content.py`, in English, German (du) and
  Arabic (right to left), including the airmail label's four languages
  (`AIRMAIL`) and the handstamp on the privacy section (`stamp_covered`).

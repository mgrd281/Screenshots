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
  cover-ink: "#1F1F1F"         # covers over private details in a photo
  island-black: "#000000"      # the island line style
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
  themselves. Never put text on a custom translucency that has no opaque
  fallback.
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
- The **amber, coral and violet gradient** belongs to the app icon and the
  About pane only. It is not an interface color: no gradient buttons, no
  gradient panels.

### Semantic
- **Pin orange** means "kept on purpose". It is used only for the pin badge.
- **Count red** is only for the closed stack's count, as on a Dock badge.
- **Search yellow** is the highlighter on words found by Search.
- **Cover ink** is the opaque block over private details. It reads as
  redaction, not decoration.
- **Record red** (`Color.red`) is only for the stop button while the screen
  is recorded, as macOS marks recording.
- **Allowed green** and **not allowed orange** (`.green`, `.orange`) are only
  for a permission's state, with a symbol beside the word, never color alone.
- **Island black** is pure black, to blend into the notch and the menu bar
  above it.

### Neutral
- Text uses `.primary`, `.secondary` and `.tertiary`.
- Fills use `Color.primary.opacity(0.045–0.12)`, so they work in both light
  and dark.
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
- **Screens and devices.** Snapfly is macOS only; there is no mobile layout.
  It must handle these instead:
  - several displays: the line goes to the screen with the pointer;
  - full screen Spaces;
  - a line moved down with its grip;
  - all three sizes;
  - all four styles.

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
  - covered: lock badge;
  - a PDF: a "PDF" capsule with its page count, in the lock's corner and
    style (9 pt bold white on black 55%, 18 pt high);
  - pinned: orange pin;
  - copied: "Copied" capsule below;
  - search: dimmed and desaturated when it isn't a match, yellow marks when it
    is;
  - dragged: 45% opacity in its slot. Dragged along the line (within the
    cards' height and 24 pt more), its slot moves to where the pointer is,
    past each neighbour's middle, and the others step aside with the line's
    order spring; let go there, it stays rather than flying back. A closed
    stack does not reorder. VoiceOver has Move Earlier and Move Later.

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
- **Menu bar menu.** Short: Take Screenshot, then Show or Hide line, Search…,
  History…, Take everything down, Settings…, Open folder, Updates, Quit.
- **Photo context menu.**
  - Grouped by intent: copy and send; translate and describe; open and edit;
    take down.
  - SF Symbols on macOS 26 only, as Apple's own menus have.
- **Settings sidebar.** General, Line, Privacy and About.

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
  - Hide Part has a rounded field above its footer to say what to hide,
    after `sparkles` (or `text.magnifyingglass` without Apple Intelligence)
    in 13 pt semibold `.secondary`, with a Hide button and a small spinner
    while it works. With Apple Intelligence, three examples sit under it as
    small `.bordered` buttons, in a row where they fit, else stacked. A callout note in `.secondary` under it says what it did.
    While the field has the keyboard, Return runs it; empty, Return is Done.
- **No modal alerts** for things that can be said inline in the card.
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
  - The search and Clear History… sit in the toolbar. Empty, it uses
    `ContentUnavailableView`.
- **Chat button** (`ChatButton.swift`), the one control that floats over
  another app's window. It shows only while photos hang and a chat app or a
  browser is in front, and it sits just above the chat's own send button.
  - A `controlGlass` capsule with a 4 pt inset. It holds the newest photo
    (26 pt, 7 pt corners, the one before it leaning behind), the count
    (13 pt semibold rounded, monospaced digits), and the paper plane in white
    on an accent circle of 28 pt, which turns into a checkmark once sent.
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

### Signature: the line styles
- **Clothesline**: rope, clips and swing.
- **Glass shelf**: Liquid Glass, with upright photos.
- **Island**: black, from the notch.
- **Card stack**: fanned in the corner, spreading on approach.

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
  three sizes and in all four line styles.
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

## Website

The site in `website/` (GitHub Pages) sells the app and hosts the privacy
policy and support pages that App Store Connect links to. It extends this
system to a web page. The brief and direction contract are in
`website/BRIEF.md`.

- **The page is the Mac screen.** A frosted menu bar carries the navigation.
  The line hangs under it, and a chat window sits in front.
  - On the home page the wallpaper stays fixed while the page scrolls over
    it, like a Mac's desktop.
  - Below the first view, a light plum wash (28%, or 38% in dark) sits over
    it, so the wallpaper keeps its colours. A soft, blurred scrim sits only
    behind the words (plum at 46%, blurred 60 px), so white words stay at least 4.5:1 on
    every part.
  - Each demo is a native object on that desktop:
    - keycaps;
    - Desktop files that fly onto a rope;
    - Snapfly's own Settings window, on its Privacy and Line panes, with
      the line-style tiles;
    - the photo's menu opening from a card on a line;
    - a whole Mac desktop to try Snapfly on (below);
    - the Hide Part window, said in a sentence (below).
  - **The desktop to try Snapfly on** (`section_capture`): a Mac screen
    with no laptop round it, so its content gets all the room. It is its
    own small system: every value inside it is a `--d-*` token on
    `.desk-stage`, and nothing inside uses a free value.
    - **The screen**: a 16 radius, a hairline and shadow 3, nothing else.
      Its wallpaper is a calm gradient of muted lavender, rose and violet
      (a dusk version in dark) under a fine grain (8%, 10% in dark).
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
      dark), success #1E8E3E (#30D158 in dark), warning and error. Every
      text pair is at least 4.5:1 in both modes, glass included.
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
    - **Snapfly on it**: the shirt in the menu bar opens Snapfly's real
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
  - **Hide Part** (`section_say`): the editor's window with a bank transfer
    in it, the sparkles field, the three examples, the note, and Remove
    All, Cancel and Done. Covers are cover ink at a 3 radius, one per line
    of a detail, growing in from the reading start 45 ms apart; hovered,
    they show an eye and an accent ring, and a click removes one. A drag
    draws a dashed accent box. A few words in English, German and Arabic
    stand in for Apple Intelligence; Done adds the lock badge.
  - **Start in four steps** (`section_start`), before the close: four
    cards on `web-surface` (20 radius, the float shadow), each with its
    number in a 30 pt accent circle, a 44 pt icon tile in the brand
    gradient, a title and a line. Four across, two on a tablet, one on a
    phone.
  - **The hero's chat** carries the chat button and its message bar as
    "Chat button" above has them, over the chat's own send button. Its
    photos are the line's newest two. Hold it, or right-click it for Send
    with a Message…; the photos land as one album and the message right
    under it. The hero's photos also reorder by a sideways drag, lifted
    under the pointer (1.06), and by Option and an arrow.
  - The privacy and support pages are documents on `web-ground`.
- **Brand themes.** The site has three complete looks, at the owner's
  request, and the visitor picks one; light or dark stays the system's, so
  there are six in all.
  - **Original Sunset** is the default and the site as it always was: the
    warm sky below, with every value it had. Nothing in it changed.
  - **Emerald Petrol** is deep water with cool light falling in from above.
    - Palette: Deep Petrol `#062F31`, Emerald `#07514E`, Refined Teal
      `#168176`, Soft Mint `#B8DED2`, Pearl White `#F5F8F5`.
    - Wallpaper: a 160° sweep from teal (`#17806F`) through emerald to
      petrol, a pool of petrol low on the leading side, a mint bloom where
      the light enters above the line (top, trailing), a faint diagonal
      sheen like light through glass, and a fine matte grain (5%). In dark,
      the same water at night: `#0B3E3B` to `#021516`, a teal bloom, the
      sheen in mint.
    - Accent: Refined Teal, as a Mac takes on its accent colour, so switches,
      selection, bubbles and filled buttons turn teal (white on it is
      4.7:1). Links are Emerald on light (8.6:1 on Pearl) and `#8FD6C4` on
      dark.
    - Glass picks up a hairline of light along its top edge (white 60%, or
      mint 16% in dark), on the menu bar and the photo cards; the menu bar
      is pearl glass, petrol glass in dark.
    - Shadows are tinted petrol, not plum. Brand tiles use teal to emerald.
      The download badge is Deep Petrol with a mint hairline.
    - The page ground is Pearl White, or `#081819` in dark.
    - The desktop to try Snapfly on gets a sage desktop (petrol at night) and
      a teal accent; its greys stay.
  - **Signature Orange** is one confident colour used with precision, the
    many-coloured Sunset's opposite.
    - Palette: Primary Orange `#EC632C`, Deep Orange `#C7461C`, Warm
      Orange Highlight `#FF8754`, Soft Peach `#FFE4D7`, Pure White, Premium
      Black `#171717`, Warm Neutral `#FAFAF8`.
    - Light: the first view and the close are a bold orange field (a warm
      highlight where the line hangs, a deeper orange low on the trailing
      side) with Premium Black type (5.5:1). Between them, clean Warm
      Neutral space with Premium Black words (text at 76%, 8:1), a faint
      peach glow in two corners, and no washes or scrims. The privacy band
      ("No account…") is Premium Black with white words, its first words in
      the Highlight and an orange glow in one corner.
    - Dark: the page is Premium Black (`#121211`). The orange becomes light:
      an ambient glow above the line, a glow rising into the close, and a
      solid Deep Orange privacy band.
    - Filled controls, switches and bubbles use Deep Orange, so white on
      them stays 4.9:1; links are `#B23E17` on light (5.6:1) and the
      Highlight on dark. Brand tiles go Highlight to Deep Orange.
    - The download badge is Premium Black on orange, Deep Orange on black.
    - Glass is white (72% on the menu bar) with a white top edge; shadows
      are warm brown, black in dark. The rope is Premium Black, peach in
      dark. Keys, pill buttons and the glass shelf on the light page are
      drawn in black at low opacity instead of white.
    - The desktop to try Snapfly on gets a warm sand desktop (black at
      night) and a Deep Orange accent.
  - **Stays the same in all three**: windows, system controls' shapes, the
    traffic lights, status colours, the screenshots' content and the app
    icon. Signature Orange sets text in Premium Black.
  - **Tokens.** Everything a theme changes is a custom property on
    `:root`: the wallpaper, washes and scrim, menu bar, menu and glass
    colours, the glass shine, rope, accent, link, ground, the shadow tint
    (`--shade`, `--shade-deep`, as r g b), the brand gradient and its
    glow, the badge, the line-style tiles' small wallpaper, and what sits
    straight on the wallpaper (`--on-wall` and `--on-wall-2` for words,
    `--kbd-wall-*`, `--pill-*`, `--file-shadow`, `--shelf-*`), plus the
    surfaces a theme may give the first view, the close and the privacy
    band (`--hero-bg`, `--close-bg`, `--band-*`). Each theme overrides
    them on `:root[data-brand="…"]`, in light and in dark; nothing is
    coloured outside the tokens.
  - **The switcher** sits in the menu bar before the language menu: a
    small well (`fill-2`, full radius, hairline) with three 14 pt swatches,
    each its theme in small with a highlight where its light comes from,
    and a raised thumb (white, or white 20% in dark) under the chosen one
    that slides across in 0.45 s. The order is Original Sunset, Emerald
    Petrol, Signature Orange. A swatch grows to 112% under the pointer
    and to 90% when pressed. Its name shows in a help tag after 0.45 s, or
    at once on keyboard focus. It is a radio group: Tab reaches the chosen
    swatch, the arrows choose the next one and wrap round, in the reading
    direction. On touch the swatches are 32 × 28 with a 44 pt tall target.
  - **No wrong flash**: the first script in `<head>` reads the choice and
    sets `data-brand` before the page paints; the switcher only appears once
    scripts run. Changing theme spreads the new one over the page in a
    circle from the swatch that was chosen (0.7 s on `--ease-out`,
    reaching the farthest corner last); with Reduce Motion, or without the
    View Transitions API, it changes at once. The browser bar colour
    follows. Another open tab follows the change, at once.
  - On phones (430 px and less) the menu bar keeps Snapfly's icon and hides
    its name from view (it is still read out) so everything fits.
- **The brand gradient is the wallpaper.** On the site, amber, coral and
  violet are the desktop the app sits on.
  - Nothing that is pressed or read sits on it bare. White text gets the
    wash, fading up from the bottom of the first view.
  - Dark mode swaps in a dusk version of the same three hues.
- **Everything on the wallpaper is native.** It follows this file's tokens:
  - photo cards: 16/12, 4 pt inset, glass, swaying 1.1° on a clip;
  - corner buttons;
  - cover ink;
  - context menu: 13 radius, 7 radius rows, accent highlight;
  - segmented control;
  - switches and checkboxes in the accent;
  - windows with traffic lights at a 18 radius.
- **The tag on the site's line:**
  - It hangs from the rope at the end of the line.
  - It holds a single tool, Send all: a 58 pt accent circle with a white
    ring and the paper plane.
  - Its name sits under it in a "Copied"-style capsule, so the one-click
    send of every photo is seen and tried at once.
  - Photos sent together land in the chat as one album bubble.
- **One exception to "corner buttons show on hover":** the paper plane on
  each hanging card always shows on the site. The page has to invite the
  first click, and phones have no hover.
- **Buttons.** The download link is a badge like the stores' own, at the
  owner's request: black, a 12 radius, at least 60 tall, a light hairline
  (white 32%) and the download shadow, a solid white Mac 34 wide, then two
  lines, "Download for" at 12 (13 in Arabic, 500) over "macOS" at 24 (600).
  No Apple logo: Apple keeps it for its own badges, and the real App Store
  badge goes beside it once Snapfly is in the store. On the ground, the
  primary is `web-button` with white text. The app's `#007AFF` gives white
  text only 4.0:1.
- **Type.**
  - The system stack only: SF Pro and SF Arabic on Apple devices. No web
    fonts, so nothing is fetched from another host.
  - Display sizes are allowed on the site: hero to 5.6 rem, section heads to
    3.5 rem. Tracking is −0.015 em on display lines, −0.01 em on section
    heads, and 0 in Arabic, as SF Pro Display wants.
  - German headlines step down a size for long words.
- **Motion.**
  - The signature move is the paper plane: the card takes off up and away,
    as on the icon, then lands in the chat while the line closes the gap.
  - **The first view arrives once**, at the owner's request for modern,
    rich motion: the rope draws across (0.9 s), the photos drop onto it
    one after another (110 ms apart) and swing to rest on their clips,
    each swing smaller (1.2 s), the tag hangs last. The headline, the line
    under it and the download badge rise 22 px out of a 10 px blur
    (0.9 s, 0.1 to 0.34 s in), and the chat opens like a Mac window, up
    32 px from 95% (1 s). All on `--ease-out`; it plays on load and never
    again, so photos hung later just hang.
  - **Below the first view, each thing arrives once as it comes into
    view**, by what it is: headings rise 26 px out of a 10 px blur, words
    rise 18 px, windows and the demo screen open from 95% and 44 px down,
    the four steps come in as a list (98%, 28 px), each 90 ms after the one
    before, four at most. 0.8 s for opacity and blur, 1 s for movement.
    Only what starts out of view waits; nothing is hidden without
    `site.js`, and print shows everything.
  - Everything else plays once when seen: the Desktop sweep and the
    keycaps.
  - **Presses and hovers.** A press answers at once (0.06 s) and letting
    go eases back: a photo gives to 98%, a corner button to 88%, the pill
    buttons to 96%, the menu bar's items highlight. Hover that raises or
    grows something is only for a pointer that hovers, so a tap on a phone
    leaves nothing raised.
  - **Nothing teleports.** An FAQ answer slides open and closed (0.35 s)
    where the browser can size it, and opens at once elsewhere. The chat's
    hint folds away with its gap (0.26 s) when the first photo lands.
  - Swaying photos pause while their line is off screen.
  - Reduce Motion turns flights into fades and stops the sway and every
    arrival; on the desktop to try Snapfly on, only fades are left.
- **Phones** (640 px and below): sections are 72 px apart, long centred
  words read from the start of the line, and the Desktop's files sit right
  under the rope, above the words, so the sweep is a short hop up and never
  crosses the text.
- **Images.** The PNGs in `website/static` come from the app icon, drawn by
  `website/make-images.py`. Everything else is inline SVG drawn in
  `build.py`.
- **Words.** Labels the app shows come from its `Localizable.strings`.
  Everything else is in `website/content.py`, in English, German (du) and
  Arabic (right to left).

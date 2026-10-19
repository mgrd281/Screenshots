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
  cover-label: "#FFFFFF"       # a labelled cover's word, at 92%, on the cover ink
  cover-dot-dark: "#2E2E2E"    # the dots look on a light ground (gray 0.18), at 92%
  cover-dot-light: "#F0F0F0"   # the dots look on a dark ground (gray 0.94), at 92%
  # The cover looks' sample in Settings, a little chat, fixed in the picture.
  sample-ground: "#FFFFFF"     # #1C1C1E in dark
  sample-bubble-in: "#E9E9EB"  # the grey bubble, with a name; #3A3A3C in dark
  sample-bubble-out: "#007AFF" # the blue bubble, with a number, in both
  tile-paper: "#EBEBEB"        # the ink tiles in the dark, their symbol in #1A1A1A
  island-black: "#000000"      # the island line style
  # Draw on Photo's inks, drawn into the copy's pixels, so fixed in light and dark.
  draw-red: "#FF3B30"          # the first ink; white words and numbers on it
  draw-yellow: "#FFCC00"       # the highlighter's first ink; dark words on it
  draw-green: "#34C759"        # dark words on it
  draw-blue: "#007AFF"         # white words on it
  draw-black: "#1C1C1E"        # also the dark words on the light inks
  draw-white: "#FFFFFF"        # a step's rim on the other inks
  # Background's colours (Backdrop.Fill), from the top left to the bottom right.
  backdrop-sunset: "#FFC45C → #FF5E62 → #B234D6"   # the icon's gradient
  backdrop-emerald: "#34D399 → #0E7490"
  backdrop-orange: "#FFB340 → #FF5E3A"
  backdrop-ocean: "#5AC8FA → #007AFF"
  backdrop-lilac: "#D8B4FE → #6366F1"
  backdrop-graphite: "#48484A → #1C1C1E"
  backdrop-mist: "#F5F5F7 → #DCDCE1"
  backdrop-white: "#FFFFFF"
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
  # The iPhone app only (iOS/Snapfly/HomeParts.swift, AccentColor in its assets).
  phone-accent: "#07875C"      # the iPhone's accent, links and tools; #1FA774 in dark
  phone-protect: "#07875C"     # the green button in light and dark: white on it 4.5:1
  phone-protect-pressed: "#056B49"  # pressed, and the badge's lower end
  phone-protect-light: "#12A572"    # the badge's upper end
  phone-surface: "#EAF7F0"     # the soft green behind the stacked photos; #102A20 in dark
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
  guide-card:
    rounded: "{rounded.floating}"
    padding: "{spacing.lg}"
    width: "340pt"                 # in 28pt of clear room; an 18 × 8pt arrow with a rounded tip
  guide-shade:
    backgroundColor: "#000000"     # at 38%, 50% with Increase Contrast; a hole 6pt round what it shows, with a 1.5pt accent edge
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
    size: "30pt × 28pt"            # a tool in Draw on Photo's row of eight; chosen: the accent at 16% behind the accent glyph
  phone-dock-icon:
    size: "44pt"                   # a tool or a way out on the iPhone editor's floating capsules; glyph 18pt semibold; chosen: white on a 38pt phone-protect circle
  phone-glass:
    shadow: "black 12%, radius 10, y 4"   # floating controls before iOS 26: regular material, a 0.5pt hairline of .primary at 8%; Liquid Glass from iOS 26
  phone-status-capsule:
    height: "36pt"                 # at least; footnote, 14pt in, 6pt under the navigation bar
  draw-swatch:
    size: "18pt"                   # an ink, with a 1pt hairline of .primary at 18%; chosen: a 2pt accent ring 3pt out
  draw-handle:
    size: "9pt"                    # white, a 1.5pt accent edge, at a chosen mark's ends or corners
  cover-look-tile:
    rounded: "{rounded.tile}"
    sample: "132pt × 82.5pt"       # three to a row; a 1pt hairline of .primary at 12%; chosen: a 2.5pt accent ring
  cover-label:
    size: "64% of the letters covered, at most 2.2% of the unit"   # semibold system font; under 6 px, or no room, plain ink
  cover-dots:
    size: "46% of the letters covered, 70% of that between them"   # centred on the line
  cover-pixels:
    tile: "a third of a line's height; on a face or a code, 2% of the unit, at least 12 px"
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
- **Cover looks** (`CoverStyle`, chosen under Privacy, ink at first) are
  how a covered place looks in what leaves the line: ink; labelled, the ink
  with the kind's short word on it (`PrivateDetail.label`, "Hidden" for a
  rule or a part hidden by hand); blur, word-shaped smudges over the colors
  around with a fine grain; pixels, square tiles darker toward a line's
  middle; dots, a row of round dots over the colors around; erased, the
  colors around carried across. **Every look hides for good**: blur,
  pixels, dots and erased are drawn only from a thin band just outside the
  place (its middle value, so a stray letter does not tint it), leaving out
  every covered place, plus noise seeded by the place's position, never
  from the pixels under it. A real blur or pixelation of text can be read
  back; these cannot. Places that overlap on one line are drawn as one, and
  lines of one height get labels, dots and tiles of one size. A face or a
  code takes pixels in the dots look.
- **Every copy is checked** (`Finder.covered`): once covered, it is read
  again as anyone could read it, and a detail still readable, or a piece of
  three letters or more of what was hidden left beside its cover, is covered
  too, in two more rounds at most. What is drawn on a cover is never read as
  text. The strongest protection covers each line with a detail whole, with
  0.45 of its height of room across and 0.35 up and down instead of 0.25
  and 0.2. Apple Intelligence, where it is on, only adds covers: never on a
  guess, only words that are in their line, never waited for on the main
  thread, and not for Test on a Sample, which reads the same each time.
  Copy Text leaves out what it found once it has answered, and with the
  strongest protection, whole lines, as they are covered.
- **Photo badge** is black 55% with a white glyph or text, over a picture: the
  lock, the paper plane of a photo sent before, the PDF capsule, and the size
  while an area is chosen. With Reduce Transparency on, it is the cover ink
  instead (grey 12%, solid).
- **Record red** (`Color.red`) is only for the stop button while the screen
  or a guide is recorded, as macOS marks recording.
- **Allowed green** and **not allowed orange** (`.green`, `.orange`) are only
  for a permission's state, and whether the AI assistant's key works, and the orange for a rule's pattern that cannot
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
| Welcome title | 15 pt | Semibold | The introduction's welcome card, its one step up, and a guide's title |
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
    radius), as System Settings does, but every tile is ink
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
  - **Workspace** (`WorkspacePane`, `folder.fill`, between General and
    Line; absent in the App Store edition) is a grouped `Form`: the switch
    with its two footers (what off means, and the iCloud warning), a warning
    row (`exclamationmark.triangle.fill` in orange, Open Settings… and Try
    Again) only while something is wrong, Location (the folder's place, Show
    in Finder, Change Location…, the folder's name, the screenshots' count
    and size), Categories (where new ones go, a row for each: its name as a
    plain field, its count in 11 pt `.secondary`, then borderless 20 pt
    buttons for hide, up, down and remove, all labelled, and a field with
    Add), and a last section with Delete…, a destructive button that asks.
  - General has a Screen recordings section with one Sound menu (No Sound,
    Mac's Sound, Microphone, Mac's Sound and Microphone); the microphone
    choices are greyed out before macOS 15, and the footer says why.
  - General names the screenshots folder under "Screenshots folder", from
    the home folder down ("Pictures › Snapfly"), with Show in Finder beside
    it; watched folders are named the same way.
- **Screens and devices.** Snapfly is macOS only; there is no mobile layout.
  It must handle these instead:
  - several displays: the line goes to the screen with the pointer;
  - full screen Spaces;
  - a line moved down or across with its grip;
  - all three sizes;
  - all eight styles.

- **Background…** (`BackdropEditor`) is laid out like Draw on Photo: the
  picture on the left as it will go out (drawn at 1400 px at most, again at
  each change), the 340 pt inspector on the right. Its Background section is
  a grid of four 26 pt gradient circles a row, 12 pt apart, with a
  hairline of `.primary` at 15% and a 2 pt accent ring round the chosen one;
  then Padding and Corners sliders, a Shadow switch and a Size menu. Remove
  Background (only when it has one), Cancel and Done sit in the footer.
  In the picture, the room is 2–20% of the photo's unit (the square root of
  its area; 8% to begin), the corners up to 4.5% of it, and the shadow black
  at 32%, blurred 3.5% and dropped 1.2%.
- **The workspace folder's icon** (`FolderIcon`) is the system folder with
  the app's icon on its front, a share 0.5 of the folder wide (0.62 up to
  32 pt, so it reads small), centred at 40% of the height, with a soft
  shadow only above 32 pt. It is drawn at 16, 32, 128, 256 and 512 pt, at 1×
  and 2×, and set with `NSWorkspace.setIcon`; it adds no colour of its own.

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
  except the pin and a picked photo's check, which always show.
  - Top leading: discard (cross, or eye-slash for files outside Snapfly's
    folder) or unpin.
  - Top trailing: the pick circle, 20 pt glass with an 8 pt bold
    `checkmark` in `.primary`, as the cross is drawn. A click picks the
    photo to go with others, without the "Copied" capsule; picked, it is
    the accent circle with a 9 pt bold white check, and a click puts it
    back. Its tip says Pick or Unpick.
  - Bottom trailing: send, a 22 pt accent circle with `paperplane.fill`.
    Under the card, not on it, a row of six destinations, each on its own
    switch (Settings › Line, in a section of their own, Icons under photos,
    one row per destination (below), then Websites open in, before Send
    button over chats): ChatGPT, Claude, WhatsApp,
    Gmail, GMX and WEB.DE, in that order until dragged into another
    (`ChatTarget.ordered`, below), 20 pt each, 4 pt apart, centered
    under the card 6 pt below it, so the card keeps only its own buttons.
    The photo's menu and VoiceOver's actions follow the same order.
    - **Their order** (`ChatOrderRow`): the section opens with the six as
      they stand under a photo, 28 pt (`ChatIcon`, the strip's drawing at
      any size, its short mark at 37.5% of it), in rows of the same length
      (`IconGrid`): as many rows, 14 pt apart, as the width needs with the
      icons at least 12 pt apart, the icons shared out evenly between them
      (eighteen that fit sixteen to a row go nine and nine, never sixteen
      and two), each in the middle of an equal column across the row; every logo in its
      own colours, the ones under photos with a 13 pt accent check (a 7 pt
      heavy white `checkmark`, ringed in the window's background) at their
      bottom trailing corner, 4 pt out, fading and scaling in over 0.15 s;
      one turned off keeps its place and VoiceOver hears "Off"; each with its name as help. A click
      turns it on or off, as its switch does (a button to VoiceOver).
      Dragged, one takes the place of the icon it passes, the rest closing
      up on an 0.15 s ease-out, and every photo's row follows at once;
      VoiceOver has Move Earlier and Move Later. A callout `.secondary` line
      under the row says to click and drag them, and how many fit.
    - **One row per destination** (`ChatRow`), in the same order: its icon
      at 24 pt; its name over a caption (`.caption`, `.secondary`) saying
      where a click goes, "Opens on its website, in Safari.", "Opens in its
      app." or "Its app is not on this Mac, so it opens in Safari.", with
      "The photo is copied, to paste into a message." after it for those
      that copy; then, on the trailing edge, a pop-up menu, Browser or App
      (help "Open ChatGPT in"), and its switch, labels hidden, VoiceOver
      hearing "ChatGPT on photos".
    - **Websites open in** (`ChatBrowserRow`), after them: a pop-up menu,
      "Default browser (Safari)", a divider, then each browser on the Mac
      that can say which page it shows, by name with its 16 pt icon, in
      alphabetical order; one no longer on the Mac reads as the default.
      Its subtitle says what Browser and App mean beside each icon.
    The row shows with the pointer over the card or the row, fading in and
    settling 6 pt, and the photo's view (`GrabView`) and its hit rect reach
    30 pt below the card (`PhotoButtons.stripHeight`) while it does; the
    space between the icons takes no click.
    - **More to choose.** Twelve more sit among the six in Settings, off at
      first: Perplexity, Grok, DeepSeek and Qwen (AI chats, covered as in any
      AI chat), Messenger, Instagram, Outlook, Yahoo Mail, Facebook, Airbnb,
      Visual Studio Code and Antigravity. Any number can be on. A row holds
      six (`PhotoButtons.maxChats`, `ChatTarget.row`): with more on, the
      first five stand in it and the sixth place is **⋯** (`MoreChatsIcon`),
      a 20 pt `controlGlass` circle with `ellipsis` at 45% of it, bold,
      `.primary`, under the badge shadow, as a mark is drawn. A click or a
      right-click on it pops up the rest under it, each "Send to …" with
      its 16 pt icon, in their order; its tip reads "More: Perplexity, Grok
      and Qwen". The order row wraps onto more lines in the pane. Instagram, Outlook, Yahoo Mail, Facebook, Airbnb, Visual Studio
      Code and Antigravity copy the covered photo for pasting, as GMX does;
      their marks are "Ig", "Ol", "Y!", "Fb", "Ab", "VS", "AG", and "Px",
      "Gk", "DS", "Qw", "Ms" for the rest.
    - **What each shows.** All but ChatGPT and Claude show their logo,
      which the owner supplied, as a 192 px PNG from `assets/chat-logos`
      (`logo`, copied into the app by `scripts/build-app.sh`, the SVGs kept
      beside it), drawn as it is. ChatGPT and Claude carry no logo of theirs
      in Snapfly: each shows the app's own icon as macOS draws it
      (`NSWorkspace.icon(forFile:)`), drawn at 122% so its shape matches the
      logos, wherever the app is on the Mac, by its bundle ID or else by name
      in the Applications folders, which also finds an app made from the
      website. Without either, a 20 pt `controlGlass` circle with a short
      mark ("GPT", "Cl", "WA", "Gm", "GMX", "WEB") in 7.5 pt bold rounded
      `.primary`. All sit under the small badge shadow.
    - **What a click does.** It opens the website in the browser chosen
      under Websites open in (the Mac's default at first), or the app where
      its row says App and the app is on the Mac (Browser at first, or App
      for all where the one choice of before said so). Gmail
      starts a new message and moves from its address field to its body with
      two Tab presses before pasting. GMX and WEB.DE open the mailbox, which
      takes a photo only once a message is started: the covered photo is
      copied, a note says "Copied. Start a new message and paste." for 6 s,
      and the photo stays on the line. The photo's menu always has Send to
      each of them. Not on recordings, which the chats don't take.
    - A right-click on ChatGPT or Claude opens the questions from Settings › Line
      › Questions for ChatGPT and Claude: Ask ChatGPT as a disabled header
      over a separator, then one item per question. A click sends the photo
      as the icon does and pastes the question after it; nothing is sent
      until Return is pressed in the chat. The photo's menu has the same
      under Ask ChatGPT ▸ and Ask Claude ▸, after Send to ChatGPT and Send
      to Claude, with `questionmark.bubble` from macOS 26. The icon's tip
      then reads "Send to ChatGPT. Right-click to ask a question." With no
      question written, a right-click opens the photo's own menu.
  - Each draws in SwiftUI and is hit-tested in `GrabView`, mirrored for
    right to left as SwiftUI draws leading and trailing.

### Photo card
- Glass frame, a 4 pt inset and a 12 pt image corner.
- States:
  - picked: accent ring and the pick circle's check. A photo stays picked
    when the line goes up, until it is sent, a click copies one photo
    alone, or Unpick All in its menu;
  - covered: lock badge, shown only when something was covered. Resting on
    it shows a tip naming what was, kinds in Settings' order joined by " · ",
    then "Your own rules" and "Hidden by hand": "Covered: Names · Emails".
    The same line is the photo's accessibility value, and the first item of
    its menu, disabled, with `lock.fill` from macOS 26, over a separator.
    Resting on the lock also shows where (`CoveredPlaces`, from
    `CoverReport.places`, in the copy as it shows, cut and under its time
    stamp band): the rest of the picture steps back under black 40%, and
    each covered place keeps its look inside a 1.5 pt accent outline with a
    2 pt corner, 1 pt outside it, clipped to the image corner; places that
    overlap open one hole under one outline. It fades in
    and out over 0.15 s ease-out, takes no clicks, and VoiceOver skips it,
    as the tip already says what was covered. A PDF shows no places;
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
- A 26 pt wide capsule of SF Symbol tools: grip, combine, search, send,
  download (`arrow.down.to.line`, right above the trash) and take down.
  While photos are picked, PDF takes search's place, so it never holds more
  than six.
- Each tool stands 24 pt tall with a clip and 22 pt without; when six share
  the tag they stand 20 pt, so the tag keeps its height (`LineTag.rowHeight`).
- It is clipped to the rope on the clothesline and sits inside the holder on
  the shelf and the island.
- Tools show only when they can act.
- Under the pointer, a tool's glyph sits on a 22 pt circle of
  `.primary` at 10%, or white at 18% on the island, fading in over 0.12 s;
  20 pt when the tools stand 20 pt.
- **Grip** (`arrow.up.and.down`, `TagView`). Dragged at once, it moves the
  line up or down, as it always did.
  - Held still (within 4 pt) for `duration.hold` (0.45 s,
    `TagView.holdDuration`), the line comes loose. Meanwhile the circle shows
    and swells to `scale.hold` (1.18, linear; it stays at 1 with Reduce
    Motion).
  - Loose, the circle fills with the accent and the glyph turns white, to
    `arrow.up.and.down.and.arrow.left.and.right` (`.symbolEffect(.replace)`).
    A Force Touch trackpad taps (`.levelChange`) and the pointer is the
    closed hand.
  - Then the line follows the pointer 1:1, any way. Within 12 pt of its
    usual place across the screen, or of the top, it snaps there with a tap
    (`.alignment`); the sideways snap rides `spring.snap` (0.25 / 0.85).
  - Photos keep their middles 96 pt in from the screen's edges
    (`Layout.photoInset`), so none fades, and the empty line's hint 160 pt
    (`Layout.hintInset`). The tag stays 40 pt in.
  - On a rope or a wire the tag stays clipped near the end and the photos
    slide along, stopping 8 pt short of it. On the other styles the tag
    comes along.
  - The place is kept as a share of the screen's width (`Layout.across`),
    so it holds on another screen. A line longer than the screen, scrolled
    with Keep on line, stays in the middle.
  - Its help tag says both ways. VoiceOver has Move Left and Move Right (a
    photo's place, on `spring.spread`) and Back to the Middle.

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
  - **Count and dot** (Count on the menu bar icon, Settings › Line, on at
    first). While photos hang, how many follows the icon, in 12 pt medium
    monospaced digits raised 0.5 pt, "99+" past 99; the item grows to fit
    and goes back to a square when the line is empty. While something new
    hangs that the line has not shown (it hung with Bring the line down
    when something new hangs off, or during a call), a 4.6 pt dot sits at
    the icon's bottom trailing corner, cut free of the photo by a 1.2 pt
    gap; it goes once the line comes down. Both are in the template, so
    macOS colours them, and in the tip and the spoken label: "Snapfly, 4
    photos on the line, something new".
- **Menu bar menu.** In groups, by purpose, as Apple's menu bar extras are.
  - First what hangs, as a disabled line ("3 photos on the line", "Nothing
    on the line"), and the main act: Paste into <the app in front>, with
    the send shortcut, enabled while something hangs.
  - Then Settings… (⌘,) and Open screenshots folder (Open Workspace while
    it is on), at the top, where they are found at once.
  - Then the ways onto the line: Take Screenshot, Take Screenshot with
    Timer, Capture Whole Page, Record Screen (Stop Recording while it runs),
    Record a Guide and Recent Guides.
  - Then files from anywhere: Add Files… (⌘O) and Cover Files….
  - Then the line: Show or Hide line, Search…, History…, Take everything
    down; the last three enabled only when they can act.
  - Then three switches with a checkmark: Hide private details, which keeps
    the kinds chosen when turned off and brings them back when turned on
    (the recommended ones when none were kept), Screenshot Button and Hide
    Desktop Icons.
  - Then the Introduction, Help & Support… (the website's support page, in
    German or Arabic where the Mac speaks them) and Check for Updates…, just
    above Quit, which comes last. The download edition checks and updates
    itself after a question; the App Store edition opens TestFlight for a
    test build, else the App Store's updates.
  - Permissions Needed… comes first of all, only once a permission was
    refused.
  - SF Symbols on macOS 26 only, as the photo context menu: `paperplane`,
    `camera.viewfinder`, `timer`, `scroll`, `record.circle` (`stop.circle`
    while recording), `folder.badge.plus`, `arrow.down.to.line` or
    `arrow.up.to.line`, `magnifyingglass`, `clock.arrow.circlepath`,
    `eye.slash`, `hand.raised`, `camera.circle`, `menubar.dock.rectangle`
    (Hide Desktop Icons, a switch with a check like the two above it),
    `gearshape`, `folder`,
    `questionmark.circle`, `arrow.down.circle`. None on Quit, as in Apple's
    menus.
- **Finder's Services menu.** Send Safely with Snapfly and Hide Private
  Details with Snapfly, for photos and PDFs, translated like the app
  (`ServicesMenu.strings`). Open With lists Snapfly as an alternative, never
  as what opens them. Hide Private Details opens Hide Part for one file, to
  save a copy beside it, and Cover Files for several or a folder.
  - For one file, the inspector's footer opens with **Send covered**: an
    11 pt semibold `.secondary` label over the chats on for photos (the
    usual six when none are), each a 30 pt `ChatIcon` that grows to 1.1 under
    the pointer (still with Reduce Motion), the rest under ⋯
    (`MoreChatsIcon`), then borderless `doc.on.doc` (Copy) and
    `square.and.arrow.up` (Share…, the Mac's own menu). A hairline divides it
    from Cancel and Save Copy…. Check All, Recommended and Uncheck All sit in
    one row of small buttons, shrinking their words to 75% before wrapping.
- **Cover Files** (`CoverFiles.swift`), a standard titled window (880 × 600,
  at least 760 × 480, its frame remembered), from Cover Files… (`doc.on.doc`)
  in the menu bar under Add Files….
  - Empty, a drop zone: a 2 pt dashed rounded rectangle (radius 14, dashes
    7 and 5, `.secondary` at 35%, the accent while files are over it), 20 pt
    in, with `doc.on.doc` at 44 pt light, a `.title2` semibold title, a
    `.secondary` line and Choose Files….
  - With files, a header (the count in `.headline`, PDFs and pictures under
    it in 11 pt `.secondary`; Add…, Remove and Clear, or after a run a menu
    to show All, Covered, Nothing to cover or Not covered), then a `Table`
    of a state symbol, Name (the path inside what was brought, truncated in
    the middle), Kind and Result, then a footer: the progress bar with
    "312 of 1,000 · about 4 min left" and Stop while running, and after it
    the tally in symbols.
  - State symbols: `circle` in `.tertiary` waiting, a mini progress view
    working, `checkmark.shield.fill` green covered,
    `exclamationmark.circle.fill` orange nothing to cover,
    `xmark.octagon.fill` red not covered, `minus.circle` stopped.
  - On the right a 300 pt grouped `Form`: What to cover, with four small
    bordered buttons two by two (Names Only, As in Settings, All, None), the
    kinds in Settings › Privacy's six groups as switches, a note on own
    rules and where the files are read; at the bottom the prominent Cover
    1,000 Files, or Show in Finder and Start Over after a run.
- **Photo context menu.**
  - Short, as a Mac app's own menus are: about fifteen rows, what is done
    most at the top, the rest in submenus named for what they are for. A
    group with nothing in it for this photo is left out, and no separator
    stands at an end or next to another. From the top:
    - What was covered and where one like it went lately, dimmed, after
      `lock.fill` and `paperplane`.
    - Copy, Copy Text (a photo) and Paste into the app in front, by name;
      then Copy Link (`link`) where the build has share links, and Delete
      Link (`minus.circle`) once one was made from the photo. Copy Link says
      "Making the link…" in a working note, then "Link copied" with the days
      it works, the note opening the link when clicked.
    - **The share link page** (`share/worker.js`) is the photo, film or PDF
      on a white card (#232326 in the dark, the site's window colour), radius
      16 with 4 pt of it round the picture at 12, on #f5f5f7 (#161617), at
      most 1100 px wide and 82% of the window high; under it, in 13 px
      secondary, a capsule Save, the days left, "Shared with Snapfly" and
      Report abuse. System fonts, light and dark from the system, nothing
      from another host, and right to left in Arabic.
    - **Send to** (`paperplane.circle`): the chats under photos as they stand
      there, each with its icon at 16 pt on every macOS; then **More Chats**
      (`ellipsis.bubble`) with the rest; then Send with Shop Header.
    - **Ask AI** (`questionmark.bubble`), with questions or prompts set up:
      each AI chat with its icon, opening its questions, then Prompts as a
      disabled header and each prompt by name after its `1.circle`,
      `2.circle` …; the right-click on ChatGPT or Claude under a photo has
      the same.
    - **Text and AI** (`sparkles`, a photo): Translate Text (macOS 15), Describe
      (`text.below.photo`), Order Details; then Write a Reply and Explain with
      the assistant.
    - **Edit** (`slider.horizontal.3`): Crop…, Keep Whole Photo when cropped,
      Hide Part…, Draw on Photo…, then Markup; for a recording, Trim… and Make
      GIF.
    - **Save and Export** (`square.and.arrow.up`): Save Copy… when what goes out
      differs from the file, Make PDF, Combine into one image with photos
      picked, **Convert to SVG…** (`point.topleft.down.curvedto.point.bottomright.up`,
      a photo, its window below); then Save for Bookkeeping and Email to
      Bookkeeping…; then Save to Desktop.
    - Open, Quick Look, Keep on Top (a photo), Show in Finder, Pin or Unpin.
    - **All Photos** (`square.on.square`), with more than one on the line or
      some picked: Copy all, Pick All, Unpick All, then Take down everything
      to the left and to the right. Then Take down (or Discard) and Move to
      Trash.
    - Submenus' symbols, like every item's, show from macOS 26 on, as Apple's
      own menus have them; a chat's icon shows on every macOS, as Open With's
      apps do.
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
    All (the primary); it sends nothing. With the AI assistant set up, the
    rows read on the Mac show at once under the note "Asking Claude for the
    rest…", and the parts it adds, Product among them, join in their place;
    the note then says which were read on the Mac and which in the covered
    copy, and a failure is added to the note, the rows kept.
  - **Write a Reply** (`arrowshape.turn.up.left`) and **Explain with
    Claude** (`bubble.left.and.text.bubble.right`, the assistant's name as
    chosen) follow Order Details. Both open the text card, titled Reply and
    Explanation, under a working note with its spinner ("Claude is writing a
    reply…", "Asking Claude…"); the answer sits on the reading panel's fill,
    the note says it was written from the covered screenshot. Under it, the
    **question field**: a rounded field the card's width, prompted with an
    example ("Add something, like “offer a replacement”", or "Ask about
    this screenshot"), and a borderless `arrow.up.circle.fill` at 18 pt with
    the help Write Again or Ask, dimmed while it works; Return asks too.
    Only this card takes the keyboard, and only while its field is clicked.
    Reply's footer has Copy and Send (the primary), which closes the card,
    then pastes the reply into the chat in front; Explanation has Copy
    alone. Without a key, or with one refused, the card says so with an
    Open Settings… link in place of Open System Settings….
  - **Settings › AI Assistant** (`AIAssistantPane`, `sparkles`, a pane of
    its own after Line), a grouped `Form` in four sections:
    - **Assistant**: two **assistant tiles** side by side in equal parts,
      Claude and ChatGPT (`AIProviderTile`), chosen as a line style or cover
      look tile is. Each is a 12 pt continuous rounded rectangle with 12 pt
      padding: the app's icon at 34 pt as the Dock shows it where the app is
      on this Mac, else its short mark in a glass circle (`ChatIcon`), never
      a logo of theirs in Snapfly; the name in 13 pt semibold, the maker
      (Anthropic, OpenAI) in 11 pt `.secondary`, and under them, in 11 pt, a
      green `checkmark.circle.fill` with "Key saved" or a `key` with "No key
      yet". On the trailing edge `checkmark.circle.fill` in the accent when
      chosen, else `circle` in `.secondary` at 50%. Chosen: the accent at 8%
      inside a 2 pt accent edge; else the primary at 3% (6% under the
      pointer) inside a 1 pt edge of the primary at 12%. VoiceOver reads
      name, maker and key, and says which is selected.
    - **Connection**: once a key is kept, a status row: a small spinner with
      "Checking the key…", a green `checkmark.circle.fill` with "Ready. The
      key works.", an orange `exclamationmark.triangle.fill` with the
      provider refusing it, or `exclamationmark.circle` in `.secondary` with
      what went wrong (offline, busy); Check Again on the trailing edge.
      Without a key, or with one refused, a row "No key yet?" saying where
      to make one, with Get a Key… as a `SettingsButton`. Then the key: kept,
      "Saved in your keychain, ending in …WXYZ", never the key, with Change
      and Remove Key (destructive) on the trailing edge; else a rounded
      secure field, prompted "Paste your key here", then a borderless
      `doc.on.clipboard` that pastes the copied key and saves it in one click
      (labelled), Cancel while changing one, and Save as
      `.borderedProminent`, off while the field is empty, Return saving too.
      A key is checked as it is saved, and when the pane opens unchecked, by
      asking the provider for its models (`AIConnection`), which costs
      nothing; the result is kept while Snapfly runs.
    - **Model**: a menu, the provider's own models once the key works
      (Claude's by the names Anthropic gives them, ChatGPT's that chat, by
      ID, newest first), else the usual three (Opus, Sonnet, Haiku 5.5); the
      usual model is always in it and is kept as none named. Other… shows a
      field in the monospaced system font for an ID typed by hand.
    - **What it does**: Write a Reply, Explain with Claude and Order
      Details, each with the symbol its menu item has, in `.secondary`, and
      a line of 11 pt `.secondary` saying what it does; read as one by
      VoiceOver. Then the switch Find more with Claude (also under Privacy).
      The footer says where they are (a photo's menu, under Text and AI),
      what is sent where, only when chosen, and that the provider bills it,
      not a subscription.
    - An AI card's Open Settings… opens this pane.
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
- **Settings sidebar.** General, Line, Privacy, Sync, Permissions, Support
  and About, each on its tile (see Layout).
- **Sync pane** (`SyncPane.swift`), between Privacy and Permissions, with
  `arrow.triangle.2.circlepath` in the sidebar. A grouped form: the two
  toggles (Sync with your iPhone, Originals too, the second dimmed while the
  first is off) with the footer that it goes through the owner's own iCloud;
  This Mac with the state as its second line, `exclamationmark.triangle.fill`
  before it when it needs the owner, and Sync Now as a `SettingsButton`;
  then Your devices, a row each: the device's SF Symbol (`laptopcomputer`,
  `desktopcomputer`, `iphone`, `ipad`) at title size in `.secondary` in a
  28 pt column, the name, and when it was last there in caption
  `.secondary`. In a build that cannot sync, one line with `icloud.slash`
  in `.secondary` and nothing else.
  - Your devices leaves out devices of another Apple account; they have
    their own section, Another Apple account: a row each, as above, with
    Disconnect… on the trailing edge (a confirmation dialog with a
    destructive Disconnect), then Connect with a code with Show Code… as a
    `SettingsButton`, dimmed while syncing is off (its subtitle then says
    to turn syncing on first). A failure to disconnect shows as a row with
    `exclamationmark.triangle.fill` in `.secondary`.
  - **Pairing sheet** (`PairingSheet`), 440 pt wide, 24 pt padding, its
    content centred in at least 190 pt over a row of buttons on the
    trailing edge. Showing the code: the headline, one line of how in
    `.secondary`, the six digits as "042 917" in 44 pt semibold rounded
    with monospaced digits (selectable, read digit by digit by VoiceOver),
    a 180 pt linear progress bar running down the 30 seconds, and "A new
    code in 12 seconds" in caption `.secondary`; Cancel. When a device
    typed it: its SF Symbol at 36 pt in `.secondary`, "Connect “iPhone”?"
    as the headline, what it will see in `.secondary`; Don't Connect
    (Escape) and Connect (Return, `.borderedProminent`). Then a spinner
    with Connecting “iPhone”…, and an outcome: `checkmark.circle.fill` or
    `exclamationmark.triangle.fill` at 36 pt in `.secondary`, a headline
    and a line, with Done, or Cancel and Try Again. Nothing moves but the
    bar, a second at a time, so Reduce Motion asks for nothing more.

### Dialogs, sheets and panels
- **Floating card** (`TextCard`) for results that belong to a photo:
  - a header with symbol, title and close, the symbol in the accent on a
    circle of the accent at 12%;
  - one content block on a faint fill;
  - an optional note;
  - for the AI assistant's cards, the question field (see Photo context
    menu);
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
      copy" follows (below). Last, "By hand": the hint as a row's
      subtitle, Remove All on its trailing edge.
    - **Click to cover.** A click on the picture, not on a box, hides the
      word read under the pointer, or the nearest on its row within its own
      height (`HideModel.word(at:among:)`), as a hand box with the usual
      room round it; a click on a box shows it again, and a drag still
      draws a box. Under the word just hidden (over it, near the bottom),
      one small `.borderedProminent` button, "Always cover “Kelly”" after
      `plus.circle.fill`, at most 220 pt wide, the word truncated in the
      middle, kept 90 pt from the picture's sides, adds the word as a rule
      of the owner's own (`OwnRules.add`, once in any case, without the
      punctuation round it); its help says where the rule lives, and a
      footer then says it is covered from now on and where to
      change it (in the footer of Say what to hide). Every photo is read
      again, and Settings shows the rule. The button fades and goes with the
      next click, drag, page or the word's box removed.
    - The **footer**, under a divider, holds Cancel and Done on the
      trailing edge.
  - Hide Private Details in a copy (from Finder) is the same window with
    "Hide in this copy" in the inspector: Check All, Recommended and Uncheck
    All, small, sharing the row in equal parts (stacked where they don't
    fit), a footer saying the copy has no place or camera details, then the
    twenty-one kinds as switches in the six groups Settings has, named as
    Settings names them, starting with what Settings hides. The primary
    button reads Save Copy… and opens a save sheet in the folder of the
    original, under the name "… (covered)". A small spinner shows in the
    footer while the copy is written, and the window closes only once it is.
- **Draw on Photo** (`DrawEditor.swift`) is Hide Part's window, laid out
  the same (`HidePartLayout`), for arrows, boxes, circles, highlights,
  numbered steps and words drawn on a photo, and the part of it to keep.
  - The **canvas** shows the picture with what Hide private details covers
    and the parts hidden by hand, in the cover look chosen under Privacy
    (ink until they are read), then the marks drawn by the same code as
    the copy (`Drawing.draw`), so what you see is what goes. Hide Part shows
    covers as ink while you draw. A highlight
    multiplies into the picture, so words under it stay as dark as they
    were.
    - A chosen mark has a dashed accent outline (1 pt, 4 and 3) 4 pt out,
      and a 9 pt white handle with an accent edge at an arrow's ends or a
      box's or a circle's corners. The canvas keeps 12 pt round the picture so handles at
      its edges show whole.
    - Outside a crop is dimmed, black 60%, with a white hairline round
      it. While cropping it is 45%, with thirds in white at 35% and 18 pt
      white corners, 3 pt and rounded, to drag.
    - The pointer is the arrow for Select, the I-beam for Text, and the
      crosshair for the rest.
  - The **inspector**: first "Tool", a row of eight 30 × 28 pt tools,
    `cursorarrow`, `arrow.up.right`, `rectangle`, `circle`, `highlighter`,
    `1.circle`, `textformat` and `crop`, each with its help tag and its key
    (V, A, R, O, H, N, T, C), the chosen one in the accent on the accent at
    16%, rounded 6; the section's footer says how to use the tool. The last
    tool that draws is chosen again the next time; Select and Crop are not
    kept. Then Color, six 18 pt
    swatches, and Size, a segmented Thin, Medium, Thick; they change the
    chosen mark and the next one, and the highlighter keeps an ink of its
    own. A chosen mark gets a section with its name and Delete (⌫), and for
    words a rounded field to type them in, which takes the keyboard when
    words are put down. Crop shows the pixels kept and Keep Whole Photo.
    Last, the number of drawings, with Remove All on the trailing edge and a
    subtitle saying they are drawn on what is sent, then "Keep as a file"
    with Save Copy…, which saves the drawing and then the photo as it goes
    out as a file of its own, in a save panel opening in the original's
    folder.
  - The **footer** holds Undo and Redo (⌘Z, ⇧⌘Z) as icons on the leading
    edge, and Cancel and Done on the trailing. While the words' field has
    the keyboard, the letters, Delete and Return are typing: Return and
    Escape end it, and the next Return is Done.
  - Marks are flat: no shadow, no glow. A step is a circle of the ink with
    a white rim (a black one on white) and its number in SF Pro Rounded
    bold; words sit on a label of the ink, a white one with a hairline. An
    arrow narrows towards its tail under a solid head. A circle is an oval
    in the box dragged, drawn as a pen draws one: clockwise from the top
    left, once round and about a third of a radian past where it began,
    from 0.9 of the pen's width inside the oval to 0.9 outside it, so the
    ends pass each other, and thinning to 35% where the pen lands and
    lifts. Drawing explains and never hides: blur and pixelate are not
    offered, and nothing drawn counts on the lock.
- **Convert to SVG** (`VectorEditor.swift`, `VectorCanvas.swift`) is Hide
  Part's window, laid out the same (`HidePartLayout`, opening for the
  picture's size with the 36 pt bar under the canvas counted), titled "name
  as SVG", for drawing a photo again as shapes. It works on the copy that
  leaves the line, so nothing covered shows in it.
  - The **canvas** keeps `underPageBackgroundColor` and the picture under
    the floating card's shadow (black 18%, radius 14, y 6). The picture and
    its vector lie one over the other: the photo to the left of the
    **divider**, the shapes to the right. The divider is a 2 pt white line
    with a soft shadow (black 35%, blur 3) and a 30 pt white handle with
    `arrow.left.and.right` in black, at the picture's middle, kept in view.
    Over it, two **labels**, Original and SVG, in the dark badge (11 pt
    semibold white on `PhotoBadge`'s fill: black 55%, solid with Reduce
    Transparency), 10 pt in from the picture's top corners, left out where
    their side is narrower than 90 and 70 pt. A drag anywhere moves the
    divider when the picture fits; zoomed in, only the handle does, and a
    drag elsewhere pans. Left and Right move it 5%, ⇧ 1%. A picture with
    clear parts shows 8 pt chequers behind it (grey 90% and 78%).
  - **Zoom** is a pinch, ⌘ or ⌥ with scroll, + and − or the buttons, as
    large as 64 screen pixels to a pixel; 0 or Fit to Window shows it all, and
    a double-click zooms ×4 at the pointer, or back. The shapes are drawn at
    the zoom they are seen at, so they stay sharp; the photo's pixels are
    not blurred (no interpolation above 100%). A picture is shown up to ×4
    its size when it fits. The pointer is `resizeLeftRight` over the divider
    and the open or closed hand when zoomed.
  - The **bar** under the canvas is 36 pt: on the leading side a small
    segmented Compare, SVG, Original, 210 pt wide; on the trailing side
    `minus.magnifyingglass`, the zoom as a percent of the picture's pixels
    in callout `.secondary` with monospaced digits, `plus.magnifyingglass`
    and `arrow.up.left.and.down.right.magnifyingglass`, each with its help
    tag and its spoken label.
  - The **inspector** is a grouped `Form` over the footer. "Kind of
    picture" is a menu: Screenshot, Logo or icon, Illustration, Photo and
    Black and white; its footer says in a line what the choice is for and
    reads "Your own settings." when a setting was moved off a choice (the
    menu then lists Custom, and shows a choice again when the settings meet
    it). "Detail" has Colors (a slider from 2 to 64 with its number),
    Smoothness (Exact to Smooth), Leave out specks (0 to 20 px) and two
    switches, Smooth gradients and Transparent background, each with its
    help; its footer says a gradient becomes bands of flat color. "Result"
    shows Colors, Shapes and Size as rows with monospaced digits, a small
    spinner in the header while it traces, and notes in `.secondary` where
    they apply: that the picture was large and traced smaller, that it was
    made from the covered copy, that it could not be traced.
  - Moving a setting traces again after 0.2 s, off the main thread, and
    stops a trace that a newer one has replaced; the last result stays on
    the canvas until the new one is ready.
  - The **footer** has Close (Escape), Copy SVG and Save SVG… (the primary,
    Return) on the trailing edge, the last two off until there is a result.
    Copy SVG puts the markup on the pasteboard as text and as
    `public.svg-image` and says so in a note; Save SVG… opens a save sheet
    on the window in the photo's folder, named like the photo, and a note
    says where it went.
  - **VoiceOver**: the canvas is one slider named "Compare the photo with its
    SVG", its value the divider's place in percent, adjusted in steps of 10.
  - The SVG itself: one `<path>` for each color, `fill-rule="evenodd"` so a
    hole is an outline inside an outline, the bottom color a `<rect>` where
    the picture is wholly opaque, numbers to two places in relative
    commands, coordinates in the picture's own pixels with `width` and
    `height` giving the original size where it had to be shrunk to trace.
    A straight edge is a line, a corner is a corner, and a curve is a
    cubic fitted within a fifth to two fifths of a pixel.
- **Record a Guide** (`HowToRecorder.swift`) turns clicks into a
  step-by-step guide.
  - Every left or right click in another app is a step; a second click at
    once on the same spot (within 8 pt) makes it a double-click. Clicks on
    Snapfly's own windows are not steps, and its windows stay out of the
    screenshots. Nothing typed is recorded.
  - The capsule above the Dock (`CaptureBadge`, `.steps`) has the record-red
    stop button and "Click through the steps", then "Steps: 3", in 13 pt
    semibold rounded with monospaced digits that roll (`.numericText`). A
    click on it finishes. The menu bar has Finish Guide and Cancel Guide
    meanwhile.
  - Where each click lands, a 40 pt ring in the accent, 3 pt wide, spreads
    from 0.45 to 1 and fades over 0.45 s, ease-out (`HowToFlash`). With
    Reduce Motion it only fades, over 0.3 s.
  - The sentence comes from Accessibility (`HowToElement`, the direct edition
    only): the control, link, menu item, field, tab or Dock item under the
    click, or holding what was clicked, and its title, description, label or
    hint, never a field's value. A name stays out ("Click here.") when it
    holds a private detail found by its shape, one of the owner's own rules,
    a person's name as the Natural Language tagger reads it, or, for what a
    page shows rather than a control, three digits or more. Names are cut at
    a word past 48 characters.
- **The guide's window** (`HowToEditor.swift`) opens 720 pt wide, at least
  560 × 480, over the line, titled "Guide".
  - At the top, the title in a plain field, 15 pt semibold, "Name this
    guide", and the step count under it in 11 pt `.secondary`.
  - The steps one under another, at most 760 pt wide and centred. Each is a
    block on `.primary` at 4.5%, with 12 pt corners and 12 pt inside:
    - a 24 pt number circle in `.primary`, its digits in the window's
      background colour (11 pt bold rounded);
    - the sentence in a plain field, 13 pt, one to four lines, on
      `.primary` at 4.5% with 6 pt corners;
    - the picture as it will leave, at most 340 pt high, with 8 pt corners
      and a 0.5 pt edge of `.primary` at 12%;
    - under it, the app's name in 11 pt `.secondary`, and borderless 24 pt
      tools, each with its help tag and spoken label: Show Whole Screen or
      Show Around the Click, Move Up, Move Down and Delete Step.
  - While a step is covered, its picture is a placeholder 180 pt high with
    a small spinner, and the footer says "Covering private details…". A
    step whose screenshot can't be read says so, and waits for Delete Step.
  - The footer, large: Delete Guide… (a borderless trash that asks first),
    then Save, a menu of Save as PDF…, Save as Image… and Copy as Image, and
    Hang on the Line (`.borderedProminent`, `arrow.up.to.line`). Return
    does not hang it, because the fields take Return.
- **What a guide leaves as** (`HowToRender.swift`) is drawn in fixed
  colours, like the drawing inks, so it reads the same wherever it is
  opened.
  - A PDF of A4 pages (595 × 842 pt) with 48 pt margins across and 52 down,
    or one tall picture 600 pt wide at twice the resolution, with 32 pt
    margins.
  - The title in 20 pt semibold in ink (grey 0.11), then "5 steps · 18
    October 2026" in 11 pt grey 0.42, and 24 pt before the first step.
  - A step: a 22 pt ink circle with its number in white (11 pt bold,
    monospaced digits) on the reading side; the sentence in 13 pt ink, 32 pt
    in from the circle's side; 10 pt under it, the picture across the full
    width, rounded 8 with a 0.75 pt edge of grey 0.84; 28 pt to the next
    step.
  - A step never breaks across pages. Alone on a page and still too tall,
    it is drawn smaller. With several pages, "2 / 3" stands at the foot in
    11 pt grey.
  - The picture is the step's covered screenshot, cut to 60% of the screen's
    width at 16:10 around what was clicked (wider when that is), never past
    the edges, or all of it with Show Whole Screen. What was clicked is
    boxed in the red ink (`Drawing.Ink.red`, the medium line, corners of 1.5
    lines), or a ring at the click, 2.4% of the screen's size across its
    radius, filled with the red at 18%.
  - In the PDF the pictures are JPEG at 0.88 quality and at most 1600 px;
    the tall picture stays sharp.
- **The introduction** (`Guide.swift`) points at the real thing on the
  screen, never at a picture of it. Two non-activating panels over the
  line and the menu bar and under menus (`GuidePanel`, `.statusBar` + 1
  and + 2), on the screen of what is pointed at, both kept out of a call's
  shared screen:
  - **The shade** (`GuideShade`, shared with the iPhone): the screen at
    black 38% (50% with Increase Contrast), filled even-odd round a hole,
    and every click goes through it, so nothing is held back. The hole is
    what it points at with 6 pt of room, its corners those of the thing
    plus the room, up to a capsule (`GuidePlacement.hole`): the menu bar
    icon, a photo (16), its lock or pick circle (14), the photo with its
    icons, the tag. A 1.5 pt accent edge rings the hole. Between steps the
    hole glides on `Motion.spring(response: 0.45, damping: 0.86)`; the
    shade fades in and out over 0.2 s. No shade while a screenshot is
    taken, so the picture stays as it is, nor for a tip.
  - **The card** (`GuideCardView`), 340 pt wide in 28 pt of clear room, a
    floating card in `.regularMaterial` with its edge and shadow (black
    22%, radius 18, y 8) and corners of 20, with an 18 × 8 pt arrow with a
    rounded tip drawn into the same outline (`GuideCardShape`) on the edge
    facing what it points at, at least 24 pt from a corner, placed on the
    screen and not mirrored right to left. It goes below what it points
    at when there is room, else above, else beside it, 14 pt away and
    12 pt inside the screen's visible frame (`GuidePlacement.place`);
    pointing at nothing, it sits across the middle just under where the
    line hangs. It glides to a new place over 0.3 s on `ease.out` (at
    once with Reduce Motion) and follows what it points at as the line
    moves.
    - A step: the symbol in the accent on a 28 pt circle of the accent at
      12%, the title in 13 pt semibold, and the cross (a 20 pt circle of
      `.primary` at 7%, a 9 pt bold `xmark` in `.secondary`, End
      Introduction as its help, Escape); the words in 13 pt `.secondary`
      with 2 pt leading; then how far along, a dot a step, 6 pt and 5 pt
      apart, the one showing drawn 14 pt long in the accent, those done
      at 35% and those to come at 15% of `.primary` (VoiceOver: "Step 2
      of 6"), Back (← key) and Next on the trailing edge, large. Next is
      the primary (`.borderedProminent`, Return) only on a step that waits
      for nothing; a step that asks for the real thing keeps it plain,
      since the real thing is the main act. The screenshot step adds Take
      Screenshot as its primary, over the footer. Long words drop the dots
      first (`ViewThatFits`).
    - Done on the real thing, the symbol turns into a check
      (`.symbolEffect(.replace)`), VoiceOver hears "Done.", and the next
      step comes 0.7 s later.
    - The welcome: the app icon at 44 pt beside "Welcome! Discover
      Snapfly." in 15 pt semibold over "About a minute" in 11 pt
      `.secondary`, a line on what it does, and Skip for Now (Escape) and
      Start Introduction (`arrow.forward`, Return), side by side or one
      over the other where they do not fit, over the shade without a hole.
    - The last card points at the menu bar icon: "You're all set", where
      to find it again, and Done.
    - A tip is the same card without the shade, the dots or Back: its
      symbol, title and line, No More Tips as a link and OK.
  - **Steps** (`GuideStep.introduction`): the menu bar icon (its menu
    opened), a screenshot (one hangs), the photo (copied, picked or sent),
    its lock (the pointer rests on it 0.8 s), the photo with its icons
    (the pointer rests on it), its menu (opened), the tag (Next). A step
    whose part is not there is left out and not counted; a step whose
    photo goes goes back to taking one. While Crop, a screenshot, a dialog
    or a window of Snapfly's has the screen, or during a call, both panels
    fade out and take no clicks, and come back after.
  - **Where it stands** (`GuideProgress`), kept with the settings: the
    steps seen, where it was ended, finished, and the version it was for.
    It is offered once at launch, a moment after it and before the question
    about screenshots; a newer version is offered once more. The menu bar
    item reads Introduction, or Continue Introduction while it was ended
    before its end (`hand.wave`, above Help & Support). Each step and card
    is announced to VoiceOver, and opened on purpose the card takes the
    keyboard without bringing Snapfly to the front: Return, Escape and the
    arrows work at once.
  - **Tips** (`GuideTip`) show once each, at most one each time the line is
    brought down on purpose, never during the introduction or a call, and
    not for what it already showed: the lock on a covered photo, and the
    pick circle once two photos hang.
  - **Help & Introduction**, the first section of Settings › Support:
    Introduction with Start, Continue or Start Again and where it stands
    ("Ended at step 3 of 7. It goes on from there."), Show Me How with a
    menu of one thing at a time (`GuideLesson`: a screenshot, what gets
    covered, sending into a chat, a photo's menu, the tag), and Tips while
    you work as a switch. Starting one closes Settings first.
- **No modal alerts** for things that can be said inline in the card.
- **Privacy pane.** Grouped form. First a row of three small `.bordered`
  buttons, Check All, Recommended and Uncheck All, sharing the row in equal
  parts, under the header "Hide private details" and over the footer that
  says what is checked is covered.
  Then the twenty-one kinds in six sections named for their group: People;
  Companies and organizations; Money; Health; Documents; Passwords and
  access. People opens with Names (its subtitle "Everyone's"), Patient
  names ("In medical letters, reports and forms") and Other people (the
  doctors, customers, staff, payees, senders and recipients), each a
  switch with its subtitle. While Names is on, the other two show on and
  dimmed, as Names takes them in. The section's footer says that without
  Names only the people chosen are covered, told by the words round each
  name, and that an unclear name is covered and marked to check. A change
  draws the photos hanging again. Then "Cover look": the
  six looks as tiles three to a row (`CoverLookPicker`), each a little chat,
  a grey bubble with a name and a blue one with a number, covered by the
  same code as a copy, light or dark as the system is, with its name under
  it, chosen as a line style tile is; then the toggle Keep the last four
  digits (off at first) with a subtitle naming card, account and phone
  numbers and the bank statement; over a footer that every look hides for
  good, the soft ones drawn from the colors around, never from what is
  covered. A new look or the toggle draws the photos hanging again and puts
  the test's result away. Then "Protection": the toggle Strongest
  protection (off at first), whose subtitle says every line with something
  private is covered whole with more room, so not even its length shows;
  and Find more with Apple Intelligence (on at first), whose subtitle says it
  reads the words on the device and covers what the patterns miss, or, off
  and dimmed where the device has no Apple Intelligence, that it needs it;
  then Find more with Claude, or ChatGPT (off at first), whose subtitle
  says it sends each screenshot's words to the assistant set up under
  General and that covering takes a few seconds longer, or, off and dimmed
  without a key, that it needs one;
  over a footer saying every copy is read again before it leaves, and
  whatever private still shows is covered too. Then a section of its
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
  kinds puts the result away. Last the Preview. The iPhone's Settings use the same six groups.
- **About pane.** The icon at 128 under its shadow, the name in 34 pt
  rounded bold, the tagline in title3 `.secondary`, the version in callout
  `.tertiary`. Then one line, "Made by" in `.secondary` before the maker's
  name in semibold, and "© year name" in callout `.tertiary` under it;
  Check for Updates… as a regular `.bordered` button, in both editions.
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
  - **Workspace** shows only while the workspace is on, as a fourth
    segment. Its bar holds a category menu ("All (12)", then each visible
    category with its count), Open Workspace and a Grid | List segmented
    control. Grid is the cards above (112 pt, thumbnails made as they come
    into view and at most 400 kept), with the category beside the time and a
    2.5 pt accent ring and a check on a selected one; a click selects,
    ⌘-click adds, a double-click opens, and the menu is Hang on the line,
    Open, Quick Look, Show in Finder, Copy, Copy File Path, Move to Folder,
    Rename… and Move to Trash (red). List is a `Table` of Name, Category,
    Date and Size with the same menu. Empty, it says "No screenshots yet"
    with a Take Screenshot button. Each card is one VoiceOver element with
    the same actions.
  - The toolbar holds a segmented Photos | Orders | Sent picker in the middle, then
    the search, Export… (`square.and.arrow.up`, Sent only) and Clear
    History…, which clears both. Empty, each page uses
    `ContentUnavailableView` (Sent with `paperplane`).
  - **Sent** is a standard `Table`, newest first: Date (day, month, year,
    hour and minute, monospaced digits), Photo, Sent to, Covered (the kinds'
    titles in `.secondary`) and Message. Its context menu has Remove from
    History. Export… opens a save panel for "Sent with Snapfly.csv".
- **The week's line** (`CoverTally`), at the top of Settings › Privacy, on
  its own: `checkmark.shield` and one sentence in `.secondary`, "In the last
  7 days, Snapfly covered 143 details in 38 photos you sent." It counts the
  places covered in each photo sent (paper plane, ⌃⌥V, the chat button, the
  AI chats, a drag into an app), and keeps only counts, day by day, for two
  weeks. Nothing shows until something was covered; it never shows
  anywhere else.
- **Not during a call** (`Calls.swift`). Zoom, Teams, FaceTime and a call
  in the browser all open the microphone, so the Mac's default input device
  being in use says a call is on, whatever the app; Snapfly hears nothing.
  While it lasts, with Not during a call on (Settings › Line › Bring the
  line down, on at first): the line comes down only for the shortcut or the
  menu, not for a new screenshot or the pointer in the menu bar, and tucks
  away as the call begins unless it was opened on purpose; the chat button
  stays away; and every panel and titled window of Snapfly's has
  `sharingType = .none`, so a shared screen or a recording by another app
  shows none of them. Menus and the menu bar item are the system's and
  stay as they are. Off, calls change nothing.
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
  - **Prompt numbers.** Over an AI chat (ChatGPT, Claude, Perplexity and
    the other AI chat sites and apps) the prompts from Settings stand in a
    `controlGlass` capsule of their own, 6 pt above the send capsule and
    flush with its trailing edge, in both looks, so the send capsule keeps
    its size and its place over the chat's own controls: a 24 pt circle
    each on `.primary` at 7%, the number in 12 pt semibold rounded with
    monospaced digits, 4 pt apart, with a 4 pt inset. Under the pointer a
    number opens into a capsule with the prompt's name (12 pt medium, one
    line, 160 pt at most, 9 pt padding) on `.primary` at 14%, through
    `Motion.spring(0.3, 0.85)`, growing toward the leading side. The panel
    follows the label's size as SwiftUI lays it out, its bottom trailing
    corner staying put; only the two capsules take the pointer, the room
    beside the numbers lets clicks through to the chat. A click on a number
    pastes the photos and then that prompt as one message, waiting for
    Return, and the glyph turns into the checkmark as for a send. Over
    other chats there are none. The right-click menu adds Send with
    “name”, after `1.circle`, `2.circle` …; VoiceOver has the same as
    actions.
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
  - **Settings › Line › Questions for ChatGPT and Claude**: the same rows,
    the field prompted with the first standard question, under them Add
    Question and, once the questions were changed, Standard Questions,
    which puts the five back; a footer saying where they are offered. Saved
    like the messages. The standard five are localized, so a chat answers
    in the user's language.
  - **Settings › Line › Prompts for AI chats**: a switch, Numbers beside
    the send button (on), then one row per prompt: its number in
    `.secondary` and its title, the first line of its text under them (Not
    written yet while empty), Edit… and a borderless `minus.circle` at the
    trailing edge. Add Prompt (up to nine) and, once changed, Standard
    Prompts under them; a footer saying where they are offered. Edit…
    opens a 560 pt sheet: Prompt 2 as its headline, a rounded Title field,
    a text editor at least 300 pt high on the text background with 6 pt
    corners and a hairline of `.primary` at 15%, a callout line in
    `.secondary`, and Cancel (Escape) and Done (`.borderedProminent`) on the
    trailing edge; Return makes a new line. Two prompts come with it,
    Natural writing and Reply to a customer, localized, the first in ten
    paragraphs.
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
  in the chat lists, as Settings › Privacy chooses. It is off until turned
  on, so a click on a chat sends at once.
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
- **Capture overlay** (`Capture.swift`), one of the two surfaces that cover
  the whole screen, with Crop below. It shows the screens still, captured a
  moment before.
  - It takes the keyboard without activating the app, as the search bar does.
    Return takes the whole screen, and Escape or a right-click cancels.
  - **At rest**, the still screen is dimmed by black at 12%, and the window
    under the pointer is tinted with the accent at 22%.
  - **Smart selection** (`SmartSelection.swift`, `SmartArea.swift`), on
    unless turned off under General › Screenshots, outlines the part under
    the pointer instead: a photo, a card, a button, a paragraph.
    - The part has a 2 pt stroke of the accent just outside it over a fill
      of the accent at 12%, and the size capsule under its trailing corner.
    - It is the smallest part found there, at least 16 pt each way. The
      scroll wheel (away from you, or fingers up, for bigger, whichever way
      the Mac scrolls; a notch, or 24 pt on a trackpad) and ↑ and ↓ step out
      to bigger parts, then the window (the tint above), then the whole
      screen (no tint). A click takes what is outlined.
    - Parts come from the still picture itself, read at one cell a point:
      runs of at least 6 pt of plain rows or columns of the empty space's
      colour part one thing from the next, and each part is read again for
      the parts in it. In the direct edition, with Accessibility allowed,
      the app under the pointer adds what it says is there (a picture on a
      page, a button, a list), so a photo on a background of its own colour
      is outlined too. Of two parts within 4 pt of each other, the smaller
      stays.
    - A drag's corners keep to the edges of the parts and the window within
      6 pt; ⌘ lets them go anywhere. Letting go cuts the plain rows and
      columns round what was dragged over down to an 8 pt margin on each
      side, or less where there was less; with ⌘ held, it stays as dragged.
    - The hint says to click what is outlined and to scroll for a bigger or
      smaller part.
  - **While dragging**, everything outside the area is dimmed by black at
    35%, and the area has a 1 pt edge of white at 90%.
  - **The size** of the area, in points, sits in a capsule under its trailing
    corner: 11 pt medium monospaced digits, white on black at 55%, 20 pt high.
  - **A hint** sits in a `controlGlass` capsule above the Dock on the screen
    with the pointer, and hides once a drag begins. It says what the choice
    is for: a screenshot, a timed screenshot or a recording.
  - The cursor is the crosshair.
- **Crop** (`QuickCrop.swift`), from a photo's menu (Crop…, `crop`, after
  Markup) or an ⌥-click on it: the photo large over the screen with the
  pointer, to drag over the part to keep, quicker than Draw on Photo's crop
  and kept the same way, as the drawing's crop.
  - A non-activating panel over everything, as the capture overlay is, that
    takes the keyboard. It fades in and out over 0.15 s.
  - The screen is dimmed by black at 45%. The photo sits centred in the
    visible frame, 80 pt kept free at the bottom for the hint, as large as
    fits in 80% of it and never larger than itself at the screen's scale
    (`QuickCropLayout`), under the floating card's shadow (black 18%,
    radius 14, y 6). It shows what is drawn on it, not the crop.
  - A crop kept before shows as Draw on Photo shows one at rest: outside it
    black at 60%, with a 1 pt edge of white at 90%.
  - **While dragging**, outside the part on the photo is black at 45%, the
    part has the capture overlay's 1 pt edge of white at 90%, and the
    capture overlay's size capsule (`SizeCapsule`) gives the pixels kept. A
    drag begun beside the photo keeps to its edges; under 4 pt across or
    up it is not meant, and the next try waits.
  - Letting go keeps the part at once. Return keeps the whole photo, and
    Escape, a right-click or a click beside the photo cancels.
  - **Smart selection**, as on the capture overlay: the part of the photo
    under the pointer is outlined with the accent's 2 pt stroke, outside it
    on the photo black at 30%, with the size capsule giving its pixels; a
    click keeps it. The scroll wheel and ↑ and ↓ choose a bigger or smaller
    part; the whole photo stays Return's. A drag keeps to the edges in the
    photo within 6 pt and is trimmed to an 8 pt margin; ⌘ turns both off.
  - The capture overlay's hint (`CaptureHint`) sits above the Dock and
    hides once a drag begins.
  - The cursor is the crosshair over the photo and while dragging, and the
    arrow beside it.
  - A crop kept says so in a done note (6 s): it goes out cropped, and the
    file in its folder stays as it is. Keep Whole Photo
    (`arrow.up.left.and.arrow.down.right`) follows Crop… in the menu of a
    cropped photo.
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
    - Something that went as it should, like a file saved, leads with
      `checkmark.circle.fill` in the same size and style instead.
    - **Every edit says where it went** (`Notice.saved`, `Notice.savedCopy`):
      Markup and Trim, which write over the file, and Save to Desktop, which
      moves it, say "Saved to Pictures › Snapfly", the folder named from the
      home folder down as Settings names it; a copy saved as a file of its
      own says its name and its folder. These stay 6 s, and a click shows
      the file in Finder. Done in Draw on Photo and in Hide Part says the
      edit is kept with the photo and goes out with it, while the file in
      its folder stays as it is.
    - **Sent, and a way back** (`Line.leftNote`): once sent photos leave
      the line, a done note names where they went, "Sent to WhatsApp. Click
      to put it back on the line.", with the count first for several and
      without a place after a drag, for 5 s. A click hangs them again as
      the newest, takes them out of the History, and brings the line down
      as for files brought on purpose. The copies already in the chat stay
      there; only the line takes the photos back.
    - **Undo, in the note** (`Line.goneNote`): the corner cross, Discard,
      Take down (one, those to one side, or everything from the tag or the
      menu bar) and Move to Trash end with a done note for 5 s, "Taken
      down. Click to put it back on the line.", or "Moved to the Trash. …"
      when that is where they went, with the count first for several. A
      click hangs each again as the newest: out of the History to Snapfly's
      folder, or out of the Trash to where it was, under a name of its own
      if that one is taken by then. Crop, Keep Whole Photo and Hide Part's
      Done on a photo say what happened and "Click to undo." for 6 s; the
      click puts back the crop or the hand boxes there were, and the line
      shows the photo as before. A PDF's note in Hide Part stays as it was.
      A photo that can no longer come back, gone from the History or kept
      by the Trash, ends with "Could not put it back on the line."
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
app follows macOS: system fonts, colours, materials and controls, Dynamic
Type and Dark Mode as they come. At the owner's request it has a green of
its own (October 2026): its accent is `phone-accent` (the asset catalogue's
AccentColor, `#07875C`, `#1FA774` in dark), and its one primary action is the
green pill below. Its tokens are `SnapflyTokens` in `HomeParts.swift`.

- Screenshots sit in small square cards, corners 12, in the grids, and at
  3:4, corners 14, where a card stands alone.
- **The tab bar** (`AppTabs.swift`) is the system's `TabView`, never a bar
  of our own, so it is Liquid Glass from iOS 26 on, where it also shrinks
  to the tab shown while a page scrolls down (`tabBarMinimizeBehavior`),
  and the system's bar before. Four tabs, each with its own navigation:
  Photos (`photo.on.rectangle.angled`), Scan (`doc.viewfinder`), Protected
  (`checkmark.shield`) and More (`ellipsis.circle`), tinted with the
  accent; a selection haptic marks each change. The tab bar steps aside
  while a picture is open (Protect Picture is immersive). One share sheet
  serves every tab; a quick cover's note floats 24 pt over the bottom of
  the tab it was started in.
- **Photos** (`PhotosTab`). No navigation bar: a header in the page, 16 pt
  in, "Snapfly" in large title bold, at least 44 pt high, then on the
  trailing edge, while syncing is on, a chip with how it stands (footnote
  in `.secondary`, orange with `exclamationmark.triangle.fill` when it
  needs the owner, else `checkmark.icloud`, on a capsule of `.primary` at
  6%, padded 10 by 6, opening More). Settings is the More tab, so the
  header has no gear. Under the status bar is the page's own colour; from
  iOS 18 on, once the page scrolls, the bar material fades in there (0.15 s)
  so the status bar stays readable.
  Sections are 24 pt apart.
  - **The stacked photos** (`PhotoHero`), drawn with shapes, never a
    picture: on a soft ellipse of `phone-surface` (300 by 190, blurred 18),
    three cards. Behind, a page (124 by 165, corners 16, the card colour
    with a hairline and a shadow of black 8%, radius 10, y 4) turned -11°
    and 80 pt to the leading side, its lines capsules of `.primary` at 10%,
    one covered in `.primary` at 85%; and a chat turned 10° and 80 pt to the
    trailing side, its bubbles grey or `phone-protect` at 22%, a name in one
    covered. In front, a landscape (136 by 182, corners 14) on a 5 pt card
    border with corners 19 and a shadow of black 14%, radius 18, y 10: sky,
    sun, two hills and water, dimmed at night. Over its lower edge the
    badge: `photo.on.rectangle.angled` 25 pt semibold in white on a 64 pt
    circle from `phone-protect-light` to `phone-protect-pressed`, ringed 4
    pt in the background colour, with a green shadow (30%, radius 10, y 5).
    The whole is 320 by 250 and hidden from VoiceOver. It settles once a
    launch: the cards come in from the middle and turn to their places on a
    spring (0.6, 0.82, 0.05 to 0.1 s apart), the badge grows in after
    0.25 s (spring 0.5, 0.7); with Reduce Motion it is simply there.
  - **Full or small.** With no screenshots yet, the picture is whole, over
    "Your pictures. Your privacy." in title 2 bold and "Find private details
    and protect them, simply." in `.secondary`, centred, then the button,
    then No screenshots yet. Once there are screenshots, the picture is
    0.46 as large, beside the same words (headline and subheadline) and the
    button, leading, so the screenshots come first; at accessibility text
    sizes, the small picture sits above them.
  - Beside the small picture the pill is compact: subheadline semibold,
    padded 14 by 8, at least 36 pt tall, growing no larger than at extra
    large text.
  - **Protect a Photo**, the green pill (`ProtectButtonStyle`):
    `shield.lefthalf.filled` and the words in body medium, white on
    `phone-protect`, padded 20 by 11, at least 44 pt tall; pressed, it is
    `phone-protect-pressed` and 97% as large (not smaller with Reduce
    Motion), with a light impact. It opens the system's photo picker.
    Allow Access on the first launch, and Settings when access was refused,
    are the same pill.
  - Then From your Mac. What was protected lately is the Protected tab.
  - **Screenshots**, title 3 semibold, with See All and a chevron in the
    accent on the trailing edge whenever there are screenshots, over the
    newest twelve in a grid (`ScreenshotGrid`): square cards at least 76 pt
    and at most 160 pt wide, 8 pt apart, four to a row on most iPhones. A
    card (`ScreenshotCard`) shows the top of the screenshot, square in the
    grid with corners of 12, at 3:4 with corners of 14 in the row of
    protected ones, a hairline of `.primary` at 8% and a shadow of black 6%,
    radius 6, y 2; when it was taken, whole ("20:03" today, the date alone
    before, "19.10.", with the year, "19.10.25", from an earlier year, as
    the language writes them; VoiceOver says "Yesterday, 20:03") in
    caption 2 medium with monospaced digits, no larger than at the default
    text size and shrinking to 70% rather than cut, on an ultra-thin capsule
    4 pt in at the bottom of a grid card (6 pt in the row); no button of its
    own, holding the card offers its menu; and, once protected here
    lately, `checkmark.shield.fill` in white on a 22 pt `phone-protect`
    circle at the top. Thumbnails are small, made by Photos'
    caching manager and kept in memory while the app runs. From iOS 18 on, a
    screenshot opens by growing out of the card tapped (the system's zoom
    transition, a fade with Reduce Motion), from the grid, the row or See
    All alike. See All shows every screenshot in the same grid, under the
    system's search field, always showing ("Search words in screenshots"),
    which finds the screenshots read ahead of time that say every word
    typed, case and accents aside; nothing found shows the system's search
    empty state, and while nothing is read ahead of time a footnote in
    `.secondary` with `text.magnifyingglass` says where to turn that on. A
    menu on the trailing edge (`line.3.horizontal.decrease.circle`, filled
    while it narrows) shows All Screenshots, With Private Details, Protected
    or Not protected, Newest First or Oldest First (`LibraryQuery`). Holding a card offers Cover and Copy
    (`doc.on.doc`), Cover and Share (`square.and.arrow.up`) and Cover and
    Save (`square.and.arrow.down`): covered and checked without opening,
    with a note in a floating pill over the bottom, 24 pt up, gone after
    2.5 s; sharing opens the share sheet with the covered PNG.
  - The first time a grid has cards, they rise into place: from 8 pt down
    and transparent, on a spring (0.42, 0.82), 35 ms apart in reading order
    for the first twelve (`stagger.grid`); cards that come later, or come
    back, are simply there. With Reduce Motion they fade in over 0.15 s.
  - **First launch**, before access: the whole picture over "Allow Snapfly
    to see your screenshots" in title 2 bold and what Snapfly does, in
    `.secondary`, centred, 32 pt in, then Allow Access.
- **Scan** (`ScanTab.swift`), a large title, 16 pt in:
  - A card of `phone-surface` with corners of 24 and a hairline of
    `.primary` at 6%, padded 20 by 24, its contents centred 18 pt apart: a
    viewfinder 132 pt square, drawn with shapes (a page 74 by 96 of the card
    colour with corners of 10, a shadow of black 10%, radius 8, y 4, its
    lines capsules 5 pt high of `.primary` at 10%, one covered at 85%,
    inside four corner arms in `phone-protect`, 4 pt, round caps, a fifth of
    the width long), hidden from VoiceOver. Each time the tab shows, a
    reading line crosses the page once, top to bottom, in 0.9 s
    (`sweep.scan`): a capsule 96 by 2.5 pt of `phone-protect`, clear at
    both ends, with a glow of the same green at 70%, radius 5, fading in
    and out at the ends; never in a loop, and not at all with Reduce Motion.
    Then "Scan a document" in title 2
    bold over what it does in subheadline `.secondary`; and Scan Document
    (`camera.viewfinder`), the green pill, with a light impact. Where the
    iPhone cannot scan, the pill is dimmed over a footnote saying so.
  - Scanning is the system's document camera (`VNDocumentCameraViewController`),
    full screen. One page opens at once in Protect Picture; several wait
    under "Scanned pages" (title 3 semibold, Clear on the trailing edge) as
    the grid's square cards in the order scanned, a document's order. Each
    card carries its number in caption 2 medium on an ultra-thin capsule
    4 pt in at the bottom leading corner, and, once it was opened and its
    copy is checked, the protected shield (white on a 22 pt
    `phone-protect` circle, top trailing), which scales in. Holding a card
    offers Remove (`trash`, destructive). A page opened opens again as it
    was left (`ScannedPages` keeps its `ProtectSession`).
  - Under the cards, centred, Share Covered PDF (`doc.richtext`), the
    green pill. While it works it says which page it covers ("Page 2 of
    5", digits rolling) beside a white spinner, and Clear and Remove wait.
    Then the share sheet opens with the PDF (`ScanPDF`, named "Snapfly"
    and the date) and a success haptic; a page that cannot be covered, or
    one opened whose copy is not checked yet, stops it with a note saying
    which, and no PDF is made. Two footnotes in `.secondary`, 4 pt apart:
    how each page is covered and that the PDF holds only pictures, then
    that pages stay only while the app is open.
  - Then three steps, each an SF Symbol in `phone-protect`, body semibold,
    24 pt wide, before subheadline `.secondary` words, 14 pt apart.
- **Protected** (`ProtectedTab`), a large title: the last twelve screenshots
  protected, in the Photos tab's grid with the shield on each, over a
  footnote of how they are kept; with none, the system's empty state with
  `checkmark.shield`.
- **More** is Settings as a tab: a large title "More", no Done.
- **The share extension** (`iOS/Share`), in any app's share sheet: the
  system's sheet with an inline "Snapfly", Cancel and Done (semibold), on
  `systemGroupedBackground`, 16 pt in. The covered picture fitted whole,
  corners 12, a hairline of `.primary` at 8% and a shadow of black 8%,
  radius 10, y 4; a large spinner while it is covered. Under it the status
  capsule of the editor (regular material, footnote medium, at least 36 pt
  high): a small spinner and Covering private details…, then
  `checkmark.shield.fill` in `phone-protect` with how many places are
  covered, or `exclamationmark.triangle.fill` in orange with what went
  wrong. Then Copy, Share and Save as three equal bordered buttons, 64 pt
  high, corners 14, tinted `phone-protect`, the glyph 20 pt semibold over
  footnote medium words, dimmed until the copy is ready; then "Covered as
  chosen in Snapfly." in footnote `.secondary`. Notes float in a capsule of
  regular material 96 pt over the bottom, with a success haptic.
- **Protect Picture** is an immersive editor: the picture is the screen,
  and everything else floats over it (`ProtectView`, `EditorParts.swift`).
  - **The canvas** (`MarkCanvas`, a `UIScrollView`) fills the screen under
    the bars, on `secondarySystemBackground`, black in Full Screen. The
    picture is fitted whole into the room the floating controls leave (8 pt
    from them and from the safe areas), never cropped or stretched, with
    12 pt corners; zoomed (up to 6× with two fingers, or 2.5× at a point
    with a double tap and back), it scrolls out from under the controls on
    every side, so nothing on it is ever out of reach. When the room
    changes, as Full Screen comes or goes, the picture grows or shrinks to
    it in 0.32 s (at once with Reduce Motion); while zoomed in it keeps its
    zoom and is fitted again once it is all in sight. A small picture shows
    first while the whole one loads.
  - **The navigation bar** is the system's, inline: Back, "Protect
    Picture", and a menu (`ellipsis.circle`): Details, Full Screen, then
    Clear Hidden by Hand and Reset to Suggestions, each one change to undo.
  - **Floating glass** (`editorGlass`): Liquid Glass from iOS 26, else
    regular material with a hairline of `.primary` at 8% and a shadow of
    black 12%, radius 10, y 4. Every floating control uses it.
  - **The status capsule** (`PrivacyStatus`), centred 6 pt under the bar,
    footnote, at least 36 pt high, 14 pt in: while the picture is protected,
    a small spinner and the step (Opening…, Finding private details…,
    Checking the copy…, Apple Intelligence is reading… with Don't Wait in
    semibold); after a failure, `exclamationmark.triangle.fill` in orange,
    what went wrong and Try Again; then `checkmark.shield.fill` in
    `phone-protect` and how many places are covered, and while any are to
    check, a dot, `circle.dashed` in the accent (`exclamationmark.triangle.fill`
    in orange while one is uncovered) and how many are To check, then a
    small `chevron.down`. Counts change as numbers roll. Each step gives way
    to the next in place on a spring (0.42, 0.82), the capsule fitting its
    words (a 0.15 s ease-out with Reduce Motion); when the copy is ready,
    the shield bounces up once and a success haptic says so. A place only
    offered is never counted as covered. A tap opens Details; VoiceOver
    reads the whole state. Under it, for 2.5 s after a drawing tool is
    chosen, how to use it in a capsule of the same glass.
  - **The tools** (`EditingDock`), a capsule of glass over the bottom:
    Select (`hand.point.up.left`), Marker (`pencil.tip`), Box
    (`rectangle`), Lasso (`lasso`) and Eraser (`eraser`), a 1 pt divider
    24 pt high, Undo and Redo (`.tertiary` while there is nothing to undo
    or redo). Each is a 44 pt target with its glyph 18 pt semibold
    (`DockIcon`); the tool in hand is white on a 38 pt `phone-protect`
    circle. Held, the marker offers its widths (Thin, Medium, Thick: 2%,
    3.5% or 6% of the picture's width) and the eraser its sizes (Small,
    Medium, Large: 1.5%, 3% or 6%), the others their name; the tool in hand
    chosen again opens its options in a sheet 300 pt high (or medium), with
    Clear Hidden by Hand and Reset to Suggestions over "Each can be
    undone." A selection haptic marks each change of tool; a light impact
    marks a shape drawn, a word hidden or a cover erased; a medium one a
    place held down.
  - **The ways out** (`ExportDock`), 8 pt under the tools, a capsule of the
    same icons: Copy (`doc.on.doc`), Share (`square.and.arrow.up`), Save
    (`arrow.down.to.line`) and, only while a Mac is there to send to, Send
    to Mac (`laptopcomputer.and.arrow.down`); held, each says what it does,
    and Save offers Save to Photos and Save to Files (the system's file
    exporter). A tap saves to Photos. A way tapped before the copy is ready
    waits with a small spinner in its place and goes once it is; tapped
    again it no longer waits. Beside the capsule, two round 44 pt buttons
    of glass (`ToolButton`): the eye on the leading side, held down to show
    the screenshot as it was (white on `phone-protect` while held), and
    Full Screen (`arrow.up.left.and.arrow.down.right`) on the trailing.
  - **Notes** float 10 pt over the tools in a capsule of glass, footnote
    semibold: `checkmark.circle.fill` in `phone-protect` and what was done
    (Copied, Saved to Photos, Saved to Files, On its way to your Mac), gone
    after 2 s with a success haptic; or `exclamationmark.triangle.fill` in
    orange, what went wrong and Try Again, gone after 5 s with an error
    haptic. The picture and every change stay as they were.
  - **Full Screen** leaves only the picture on black, without the bars,
    the status bar or the home indicator, with Select in hand: still to
    zoom and move. One round button of glass
    (`arrow.down.right.and.arrow.up.left`) stays in the bottom trailing
    corner, and a tap anywhere on or beside the picture brings everything
    back. With Select in hand, a tap on nothing (no place, no word) and
    nothing selected, or beside the picture, goes to Full Screen.
  - Controls come and go on a spring (0.35, 0.86), the tools rising from
    the bottom; with Reduce Motion, a 0.15 s ease-out fade.
  - **Its places** show over the picture: the cover ink (grey 12%, corners
    of a quarter of the height, 8 at most) over a covered place until the
    copy is made, then the copy itself; a dashed outline, 2 pt in dashes of
    5 and 3 at any zoom, in the accent round a place to check, and in
    `.secondaryLabel` round a place left uncovered. A shape drawn by hand
    is solid ink as drawn (the marker's stroke with round ends, a box, an
    outline filled inside), at 75% while it is drawn, the lasso's edge
    dashed in the accent; the eraser's path shows as `systemBackground` at
    55%, as wide as it reaches. When a picture's covers first arrive, they
    grow over their places one after another, top to bottom and along the
    line (`stagger.cover`, 45 ms, the first 25), each spreading from the
    reading side in 0.32 s on a cubic ease-out, mirrored right to left; with
    Reduce Motion they are simply there.
  - **Select.** A tap on a place selects it, again lets go; a tap on a word
    no place covers hides it by hand and selects it; elsewhere lets go.
    The place selected shows a dashed accent outline (turned with a box)
    and a handle at each corner, a white 12 pt circle with a 2 pt accent
    edge; a box also has a turn handle 28 pt beyond the middle of its top
    edge on a 1.5 pt stem. Handles keep their size on screen at any zoom,
    and a finger takes one within 22 pt. Dragging the place moves it, a
    corner resizes it from the one across (a turned box grows about its
    middle), the turn handle turns it; one finger elsewhere moves the
    picture. Over the tools floats a capsule of glass, subheadline, at
    least 40 pt high: Cover or Uncover, the width (`lineweight`) for a
    stroke, Delete (`trash`) for what is by hand, and Done in semibold.
    Holding a place down selects it and asks, in a confirmation dialog
    titled with its kind: Cover or Uncover, Delete for what is by hand,
    Cancel.
  - **Drawing.** With the marker, a box, the lasso or the eraser, one
    finger draws and two move and zoom the picture; a tap with the marker
    leaves a dot, with the eraser rubs out what is under it. A drawing too
    small to see is dropped; the start of a two-finger zoom is no stroke.
  - Places are kept from 0 to 1 from the bottom left of the original
    picture, so zooming, the room changing or the screen turning never
    moves them; widths and turns are measured on the picture, so a stroke
    stays round and a turned box square.
  - Copy, Share and Save go only once the copy is made, checked and every
    cover known to have landed (`Finder.coversHold`), and while places are
    still to check, each asks first in a confirmation dialog ("%d places
    still to check"): Check Now opens Details, Continue Anyway goes on,
    Cancel. Share opens the system's share sheet with a PNG file of the copy
    alone, named by when the picture was taken, deleted once the sheet
    closes; Save to Files offers the same PNG under the same name.
- **Details** (`ReviewSheet`) is a sheet at medium or large height, the
  picture still usable behind it at medium. First, while there are places
  Snapfly was not sure about, "To check" with "%d of %d checked" and a
  progress bar in `phone-protect`, over one place at a time, from the top
  of the picture down, starting at the first still to check: its kind in
  the headline with Covered (`phone-protect`) or Not covered (orange) on
  the trailing edge, the place itself cut from the screenshot (84 pt high
  at most, corners of 8, a hairline), the words it hides in footnote
  `.secondary`, then Leave Visible (bordered) and Keep Covered, or Cover
  (prominent, `phone-protect`), large and of equal width, each deciding
  and going on to the next place still to check; then Previous
  (`chevron.left`), Show on Picture, which closes the sheet and shows the
  place selected and zoomed in, and Next (`chevron.right`). Keeping a
  cover decides it without changing the picture (`ProtectionPlan.decide`),
  one change to undo. Once all are decided, "Everything is checked." with
  `checkmark.seal.fill`. Then Covered and Not covered, each place a toggle
  in `phone-protect` with its kind, or Hidden by hand or Your own rules,
  over the words it hides, top to bottom.
- The icon is the Mac icon's picture, full bleed and opaque, since iOS rounds
  it (`scripts/make-icon.py --ios`).
- The introduction (`PhoneGuide.swift`) shows on its real screens: the
  newest screenshot to tap, then Copy, Share and Save under it. The shade
  is the Mac's (`GuideShade`), black 40%, round a hole 6 pt round the
  thing with corners of 18 and a 2 pt accent edge, and every tap goes
  through it. The card is in `.regularMaterial` with corners of 22, 20 pt
  inside, as wide as the screen less 16 pt each side (420 at most): beside
  the thing when it fits above or below it, else at the bottom, clear of
  the home indicator. The title is the headline, the words subheadline
  `.secondary`, the symbol on a 36 pt circle of the accent at 12%, the
  cross 30 pt in a 44 pt target, the dots 7 pt (16 pt long for the step
  showing) and the buttons large. The hole and the card move on a spring
  (0.45, 0.86), a 0.15 s ease-out with Reduce Motion. Offered once when
  the first screenshots show, again from Settings › Help & Introduction.
- Settings opens with Check All, Recommended and Uncheck All as small
  bordered buttons sharing a row, under "Hide private details", then the
  six groups. People opens with Names, Patient names and Other people,
  each with its subtitle in footnote `.secondary`, the two dimmed and on
  while Names is on, over the Mac's footer. Then "Cover
  look", the Mac's tiles three to a row with Keep the last four digits and
  Strongest protection under them; then "Reading and checking": Find more
  with Apple Intelligence and, once a screenshot was covered, how long the
  last one took, then Picture shown and Ready to share, each "Median %@ ·
  95% under %@" over the last fifty, then a row Faster picture processing,
  On or Off, opening its page (below); then Sync; then "Advanced", two rows that open pages:
  Also hide (`text.badge.plus`) and Double tap the back of your iPhone
  (`hand.tap`); then Help & Introduction. Also hide is a row per rule of
  the owner's own, its
  kind as a menu over a field with the kind's prompt, swiped away to remove,
  and Add Rule. A pattern that cannot be read says so under its field with
  `exclamationmark.triangle.fill` in orange. Rules are kept as they change,
  and the Mac's and the iPhone's are the same kind of rule.

- **Faster picture processing** (`PreparingView.swift`), in Settings ›
  Reading and checking:
  - Off, its page says what it does and that nothing leaves the iPhone,
    with Turn On…, which opens the consent sheet: an inline title "Enable
    faster picture processing", Not Now and Turn On in the bar; under them
    `bolt.badge.clock` at 36 pt semibold in the accent over the sentence of
    what it does, then four lines, each an SF Symbol in `.secondary` before
    subheadline words (`iphone`, `lock`, `battery.100.bolt`, `icloud.slash`);
    then "What may be prepared", an inline picker: Screenshots only, All
    allowed photos, Only selected photos, over a footer that allowing
    Photos is not a yes to this.
  - On, the page shows Status (Preparing…, Up to date, Paused, or what it
    waits for), a progress bar of the real share done while there are
    photos, Prepared ("%d of %d"), Still to prepare, Only in iCloud with its
    subtitle when any, Could not be read when any, Last update (relative)
    and Room on this iPhone, over a footer of when it works and waits. Then
    Pause or Resume, Prepare Now, and Delete Local Index and Turn Off in
    red, the first asking in a confirmation dialog, over a footer that
    turning it off deletes everything prepared. Then "What is prepared":
    the photos as a picker, the period ("Last 60 days", or "The photos you
    chose"), Choose Photos… with Only selected photos, and Change Allowed
    Photos… under limited access, with a footer saying so.

- Syncing with the Mac (`PhoneSync.swift`), once Sync is on:
  - From your Mac sits above the grid: the headline, then a row that
    scrolls sideways of the pictures' previews, 104 pt wide at 3:4, with the
    grid's 10 pt corners and 6 pt gaps; `laptopcomputer` in `.secondary`
    while a preview has not come. A tap opens the picture in a sheet, fetched
    whole with a progress view, then Copy, Share and Save under it as for a
    covered screenshot.
  - Send to Mac, a bordered button with `laptopcomputer.and.arrow.down`,
    under Copy, Share and Save; once pressed it waits dimmed and the note
    says it is on its way.
  - Settings has a Sync section before Help & Introduction: the toggle with
    its footnote, This iPhone with the state (orange with
    `exclamationmark.triangle.fill` when it needs the owner), Sync Now while
    on, and a row per device with its symbol, name and when it was last
    there.
  - Under it, Another Apple account: a row per Mac joined with a code
    (`laptopcomputer`, its name, its state in footnote `.secondary`, and a
    borderless destructive Disconnect… asking first), then Connect to a Mac
    with a Code with `number`, and a footer saying where the Mac shows it.
  - **Connect to a Mac** (`PairingJoinView`), a sheet with an inline title:
    one centred field for the six digits, large title rounded with
    monospaced digits, the number pad, focused at once; it goes by itself
    once six digits are in, or with Connect. Its footer says where the code
    is, or why it did not work, in orange after
    `exclamationmark.triangle.fill`. While it works, a row with a spinner
    and what is happening ("Say yes on “Studio” to connect."); when done,
    `checkmark.circle.fill` with what happened, and Done.

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

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
    is.

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
- **Menu bar menu.** Short: Show or Hide line, Search…, Take everything down,
  Settings…, Open folder, Updates, Quit.
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
- **No modal alerts** for things that can be said inline in the card.

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
  The line hangs under it, and a chat window sits in front. Below the first
  view, sections sit on the system ground (`web-ground`), and the close
  returns to the wallpaper.
- **The brand gradient is the wallpaper.** On the site, amber, coral and
  violet are the desktop the app sits on: the ground of the first view, the
  desk and line-style demos, and the close.
  - Nothing that is pressed or read sits on it bare. White text gets a wash
    (plum at 46% fading up from the bottom), so it stays at least 4.5:1.
  - Dark mode swaps in a dusk version of the same three hues.
- **Everything on the wallpaper is native.** It follows this file's tokens:
  - photo cards: 16/12, 4 pt inset, glass, swaying 1.1° on a clip;
  - corner buttons;
  - cover ink;
  - context menu: 13 radius, 7 radius rows, accent highlight;
  - segmented control;
  - switches and checkboxes in the accent;
  - windows with traffic lights at a 18 radius.
- **One exception to "corner buttons show on hover":** the paper plane on
  each hanging card always shows on the site. The page has to invite the
  first click, and phones have no hover.
- **Buttons.** The download button on the wallpaper is a white pill with ink
  text. On the ground, the primary is `web-button` with white text. The
  app's `#007AFF` gives white text only 4.0:1.
- **Type.**
  - The system stack only: SF Pro and SF Arabic on Apple devices. No web
    fonts, so nothing is fetched from another host.
  - Display sizes are allowed on the site: hero to 5.6 rem, section heads to
    3.5 rem, tracking −0.035 em, and 0 in Arabic.
  - German headlines step down a size for long words.
- **Motion.**
  - The signature move is the paper plane: the card takes off up and away,
    as on the icon, then lands in the chat while the line closes the gap.
  - Everything else plays once when seen: the Desktop sweep and the
    keycaps.
  - Reduce Motion turns flights into fades and stops the sway.
- **Words.** Labels the app shows come from its `Localizable.strings`.
  Everything else is in `website/content.py`, in English, German (du) and
  Arabic (right to left).

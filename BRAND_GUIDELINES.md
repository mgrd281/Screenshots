# Snapfly brand guidelines

How to apply the brand in `BRAND_IDENTITY.md` to new work: a view in the
app, a section of the website, a store asset or a video. Values come from
`DESIGN.md`, which wins wherever the two seem to differ. A new colour,
radius, size, component or motion value goes into `DESIGN.md` first, in the
same pull request.

## Where each part of the brand is

| Area | Where |
|---|---|
| 1. Positioning and personality | `BRAND_IDENTITY.md` §1, `PRODUCT.md` |
| 2. Logo and app icon | `BRAND_IDENTITY.md` §2; usage below |
| 3. Colour architecture | `BRAND_IDENTITY.md` §3; values in `DESIGN.md` "Colors" and "Brand themes" |
| 4. Typography | `BRAND_IDENTITY.md` §4; values in `DESIGN.md` "Typography" |
| 5. Iconography | `BRAND_IDENTITY.md` §5 |
| 6. Spacing and layout | below; values in `DESIGN.md` "Layout" |
| 7. Radius and elevation | below; values in `DESIGN.md` "Shapes" and "Elevation & Depth" |
| 8. Images and screenshots | below |
| 9. Motifs and illustration | `BRAND_IDENTITY.md` §9 |
| 10. Voice and tone | `BRAND_IDENTITY.md` §10 |
| 11. Light and dark | below |
| 12. Motion | `MOTION_SYSTEM.md` |
| 13. Social and promotional assets | below |
| 14. Responsive and accessibility | below; `DESIGN.md` "Accessibility" |

## The app icon

- **Do** use `assets/icon.png`, or the sizes made from it, unchanged.
- **Do** give it clear space of at least a quarter of its width on every
  side, and show it at 16 px or more.
- **Do** set the name beside it in the system font, Semibold, in the text
  colour of the surface.
- **Don't** recolour it for a theme, outline it, add a shadow beyond the
  system's own, rotate it, crop the squircle, or put it in another shape.
- **Don't** redraw the paper-plane card as a separate logo, or pair it with
  another mark.
- **Don't** use Apple's logo or Apple's own badges in Snapfly's artwork.
  The real App Store badge, from Apple's marketing tools, goes beside the
  download badge once Snapfly is in the store.

## 6. Spacing and layout

- **A 4 pt rhythm:** 2, 4, 6, 8, 12, 16, 24 in the app; the website adds 32,
  48, 64 and larger section gaps. No spacing off the rhythm.
- **One primary action per surface,** on the trailing edge.
- **Content first.** A card is as big as its content; controls appear where
  the hand already is.
- **On the website,** the page is a Mac screen: the menu bar on top, the
  line under it, windows in front. Sections are demos on that desktop, not
  generic marketing blocks. No KPI tiles, no sidebar-plus-cards layouts.
- **Order by reading direction,** never by fixed left and right.

## 7. Radius and elevation

- **Radii from the scale only.** The app's are 2, 3, 6, 10, 12, 16, 20, 24,
  30 and full (`rounded` in `DESIGN.md`). The website adds only what its
  drawn macOS parts need (menus 13, windows 18; the desktop demo 6, 10, 14,
  16), all listed under "Website" in `DESIGN.md`. Corners nested inside
  each other stay concentric.
- **Two levels of depth:** things on the line, and things floating over
  other apps. A shadow means it floats; inner blocks are flat with a faint
  fill.
- **One shadow per object.** No stacked shadows, glows or outer borders.
- **Glass is for the layer that floats above content,** not for the content.

## 8. Images and screenshots

- **The screenshot is the content.** Show it sharp, never blurred,
  distorted or recoloured. The frame around it is thin glass and one radius
  (16 pt card, 12 pt image, 4 pt inset).
- **Use drawn screenshots,** like the website's (`website/build.py`):
  invented but believable content (an invoice, a map, a chart), never a real
  person's data and never another company's branded screen passed off as
  real.
- **Private details are covered** with cover ink in every picture that would
  show them: names, IBANs, addresses, email addresses.
- **Real captures of the app,** for the store, come from a clean user
  account: default wallpaper or a brand-theme wallpaper, no other apps'
  notifications, the menu bar tidy, the clock at a neutral time.
- **Photos on the line hang slightly tilted** and may sway; in a chat they
  sit straight.

## 11. Light and dark

- **Light and dark are equals.** Every surface, theme and asset is designed
  and checked in both.
- **In the app,** colours are system colours, materials, or `.primary` with
  an opacity, so both work without branching.
- **On the website,** each theme overrides its tokens in light and in dark,
  so there are six looks; text pairs stay at least 4.5:1 in all six.
- **The appearance is the system's.** The site never offers its own light or
  dark switch; the theme switcher only chooses the theme.
- **Assets for both:** store screenshots and social images come in the
  appearance that suits their placement; never mix light and dark in one
  composition.

## Brand themes on the website

- **Original Sunset is the default** and stays exactly as it is.
- **Everything a theme changes is a token** on `:root[data-brand="…"]`, in
  light and in dark. Nothing is coloured outside the tokens.
- **A new section or component must work in all six looks** before it ships:
  three themes, light and dark.
- **The switcher, its order, its names and its storage stay as they are:**
  Original Sunset, Emerald Petrol, Signature Orange; `localStorage` key
  `snapfly-brand`; the choice is applied before the first paint.
- **A fourth theme, or a theme in the app, needs the owner's request.**

## 13. Social and promotional assets

- **Formats.**
  - Vertical 9:16, 1080 × 1920, 30 fps: TikTok, Instagram Reels, YouTube
    Shorts. The existing promo (`promo/`) is this format.
  - Horizontal 16:9, 1920 × 1080: YouTube, the website, and the Mac App
    Store's app preview.
  - Square 1:1, 1080 × 1080: feeds and posts.
  - Mac App Store screenshots in 16:10 (for example 2880 × 1800). Check App
    Store Connect's current list of sizes before exporting.
- **Safe areas.** In 9:16, text and buttons stay above y = 1500 and clear of
  the right 140 px from y = 850 down (`promo/README.md`). In 16:9 and 1:1,
  keep words inside the central 90%.
- **Languages.** Every asset with words comes in English, German and Arabic;
  Arabic is laid out right to left, not just translated.
- **Words** are the app's and the site's own (`Localizable.strings`,
  `website/content.py`). The tagline closes; the icon and "Download for Mac"
  or the store badge end the piece.
- **No sound in the master.** Music is added where the video is posted.
- **Never publish or replace media without the owner.** Renders and exports
  stay out of the repository (`promo/out/` is ignored).
- **Static compositions** (boards, posters, store art) use the icon, the
  line, the photo cards and a theme's wallpaper, nothing borrowed from
  another brand. The `canvas-design` skill may help with layout, never with
  a new style.

## 14. Responsive and accessibility

- **The app** is pointer-driven: targets at least 20 × 20 pt, keyboard
  support (Return confirms, Escape cancels), spoken labels on every
  icon-only control, Reduce Motion, Reduce Transparency and Increase
  Contrast honoured, and right to left respected.
- **The website** works from 320 px to wide desktops, with no sideways
  scroll, safe areas kept, 44 px touch targets on coarse pointers, keyboard
  access to every control, a visible focus ring, `prefers-reduced-motion`
  honoured, text at least 4.5:1 in every look, and Arabic right to left.
- **Videos** carry their words on screen, large enough to read on a phone,
  with nothing that flashes more than three times a second.
- **Every language holds up:** German's long words and Arabic's direction
  are checked before anything ships.

## Before something ships

- [ ] Values come from `DESIGN.md`; any new value was added there first.
- [ ] It works in light and dark, in all three themes (website), and in all
      four line styles and three sizes (app).
- [ ] It reads well in English, German and Arabic.
- [ ] Motion follows `MOTION_SYSTEM.md`, and Reduce Motion leaves fades
      only.
- [ ] No invented claims, numbers, testimonials or other companies' marks.
- [ ] The icon and name are used as above.

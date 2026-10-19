# Snapfly motion system

How Snapfly moves, in the app, on the website and in videos. The first half
names the motion that already ships as reusable tokens. The second half
holds concepts for future work. **Nothing in the concepts is built**, and
none of it is built without the owner asking.

- `DESIGN.md` wins. The tokens below are names for values that already
  ship (in `Sources/Tendedero`, `website/static/site.css` and `site.js`).
  A new motion value goes into `DESIGN.md` first, then here.
- The brand behind it is in `BRAND_IDENTITY.md`; how to apply it is in
  `BRAND_GUIDELINES.md`.

## Principles

1. **Motion explains.** It says where something came from or where it
   went: a capture flies in, a sent photo takes off, a stack spreads. It
   never runs just to decorate.
2. **Native and calm.** It should feel like macOS: short, settled, no
   overshoot you notice, nothing that blinks, pulses or glows.
3. **Spatial continuity.** A thing moves along a path the eye can follow,
   from its old place to its new one. It never vanishes in one place and
   appears in another without a link.
4. **Fast to the hand.** Feedback starts at once, within a frame. Quick
   things (hover, press) take 120–300 ms; travel takes 450–820 ms.
5. **Interruptible.** A new action takes over from a running animation at
   its current state. Nothing makes the user wait for it to finish.
6. **Once is enough.** Entrances play once. Only the hanging photos' small
   sway loops.
7. **Reduce Motion always has an answer:** a quick fade, or nothing.
8. **Reading direction.** Anything that travels sideways mirrors in
   right-to-left languages.

## Tokens

Each token lists where its value ships today. "App" is SwiftUI or AppKit;
"site" is the website.

### Duration

| Token | Value | Where it ships |
|---|---|---|
| `duration.press` | 60 ms | Site: how fast a pressed control gives |
| `duration.micro` | 120 ms | Site desktop demo `--d-t1` (hover fills, small fades); app 0.12 s fades |
| `duration.quick` | 150 ms | App `Motion.spring` with Reduce Motion (ease-out); site transitions with Reduce Motion |
| `duration.short` | 200 ms | App state changes (`.easeOut(duration: 0.2)`); site hover and press; desktop demo `--d-t2` |
| `duration.medium` | 280–300 ms | Desktop demo `--d-t3` (windows); app empty-line fade (0.3 s) |
| `duration.hold` | 450 ms | App: a held photo shrinks while its menu builds up |
| `duration.travel` | 450–600 ms | Site switcher thumb (0.45 s), line reflow (0.6 s); app capture fall (0.55 s) |
| `duration.strike` | 500 ms | Site: a postmark or the airmail label struck onto the paper |
| `duration.reveal` | 700 ms | Site: a new theme spreading from its swatch |
| `duration.flight` | 820 ms | Site paper-plane flight |
| `duration.entrance` | 0.8–1.2 s | Site first view and arrivals, once per page |
| `duration.ambient` | 5.6 s | Site sway of a hanging photo (alternate, loops) |
| `duration.run` | 30 s, linear, loops | Site bold look: the band of words running across the first view |

### Easing

| Token | Value | Use |
|---|---|---|
| `ease.out` | `cubic-bezier(0.16, 1, 0.3, 1)` | Site default (`--ease-out`): entrances, hover, travel |
| `ease.enter` | `cubic-bezier(0.2, 0.8, 0.2, 1)` | Desktop demo `--d-in`: things appearing |
| `ease.exit` | `cubic-bezier(0.4, 0, 1, 1)` | Desktop demo `--d-out`: things leaving |
| `ease.flight` | `cubic-bezier(.45, .05, .25, 1)` | The paper plane: a slow lift, a quick glide, a soft landing |
| `ease.drop` | `cubic-bezier(0.3, 0, 0.6, 1)` | A photo falling onto its clip, before the swings |
| `ease.hide` | ease-in, 0.22 s | App: the line goes back up |

### Springs (app)

SwiftUI springs, as `response` / `dampingFraction`, always through
`Motion.spring(response:damping:reduced:)` so Reduce Motion gets a 0.15 s
ease-out.

| Token | Spring | Where it ships |
|---|---|---|
| `spring.row` | 0.25 / 0.85 | A history row on hover |
| `spring.control` | 0.3 / 0.8 | The capture button (1.08) and the chat button (1.04) on hover |
| `spring.card` | 0.3 / 0.6 | A photo card on hover (1.035) and the pin badge |
| `spring.reveal` | 0.42 / 0.82 | The line comes down; on the iPhone, grid cards rising and the status capsule changing step |
| `spring.arrive` | 0.42 / 0.72 | A photo arrives and swings on its clip (16°) |
| `spring.spread` | 0.42 / 0.8 | The card stack fans out |
| `spring.style` | 0.5 / 0.85 | The line changes style |
| `spring.reflow` | 0.55 / 0.78 | Photos close a gap or change order |
| `spring.guide` | 0.45 / 0.86 | The introduction's hole glides from one thing to the next (the card follows over 0.3 s on `ease.out`) |
| `spring.check` | 0.3 / 0.7 | A step of the introduction seen through: its symbol turns into a check |
| `spring.snap` | 0.25 / 0.85 | The line, held by its grip, snaps into its usual place across the screen |

The web has no springs in CSS. There, use `ease.out` at a duration close to
the spring's response, and keyframes (like `hang-in`) where a visible
settle is the point.

### Stagger

| Token | Value | Where it ships |
|---|---|---|
| `stagger.cover` | 45 ms | Hide Part, and the iPhone's Protect Picture: covers grow in line by line, each over 0.32 s on a cubic ease-out from the reading side |
| `stagger.demo` | 180 ms | iPhone first launch: the sample card's four details covered one after another, slow enough to follow |
| `stagger.grid` | 35 ms, twelve at most | iPhone: screenshot cards rise 8 pt into the grid the first time it has any, on `spring.reveal` |
| `stagger.list` | 90 ms, four at most | Site arrivals: the four steps |
| `stagger.hang` | 110 ms | Site first view: photos drop onto the rope |
| `stagger.deal` | 90 ms, after 250 ms | Site bold look: cards dealt onto the rope |
| `stagger.words` | 120 ms | Site first view: headline, line, badge (0.1, 0.22, 0.34 s) |
| `stagger.keys` | 140 ms | Site keycaps pressed in turn |
| `stagger.moment` | 140 ms | Site story: keys pressed, then covers grown, one after another within a moment |

### Opacity

- Things enter from 0 and leave to 0; nothing rests half transparent to
  look "subtle".
- Fades use `duration.quick` to `duration.short` alone, or ride along with
  a movement at the movement's duration.
- The one breathing dim (the text card while it works, 0.8 s, in and out)
  stops with Reduce Motion; its spinner still says it works.

### Translation

| Token | Value | Use |
|---|---|---|
| `rise.small` | 6–8 px | A message or note rising into place |
| `rise.text` | 18 px | Body text arriving |
| `rise.words` | 22–26 px | Headlines rising into focus |
| `rise.card` | 28 px | A card in a list arriving |
| `rise.window` | 32–44 px | A window opening |
| `drop.photo` | 56 px | A photo dropping onto its clip |
| `drop.card` | 40 px | A step card dropping onto its clip as it arrives |
| `lift.flight` | at least 70 px, 40 px toward the reading end | The paper plane's arc |
| `deal.card` | from 34 vw toward the trailing side and 10 vh up, turned 16°, at 92% | Bold look: a card dealt onto the line, 1 s on `ease.out` |
| `rise.mask` | 70% of its own height | Bold look: the headline (1.1 s) and headings (1 s) rising out of a mask that stays where they land |

### Scale

| Token | Value | Use |
|---|---|---|
| `scale.hover.card` | 1.035 | A photo card under the pointer |
| `scale.hover.control` | 1.04–1.08 | A floating button under the pointer |
| `scale.hover.swatch` | 1.12 | A theme swatch under the pointer |
| `scale.lift` | 1.06 | A photo dragged along the line |
| `scale.press` | 0.95 | A pressed Dock icon; on the site's line a photo gives to 0.98, a corner button to 0.88, a pill button to 0.96, a theme swatch to 0.90 |
| `scale.open` | 0.95 → 1 | A window opening |
| `scale.settle` | 0.96–0.98 → 1 | A card or photo landing |
| `scale.hold` | 1 → 1.18, linear over `duration.hold` | The grip's circle while it is held, until the line comes loose |
| `scale.strike` | 1.18 → 1 (label 1.15 → 1) | A postmark or label struck onto the paper, with a slight overshoot (`cubic-bezier(0.2, 0.9, 0.3, 1.15)`) |

### Rotation

- Sway: ±1.1° around the photo's own tilt, `duration.ambient`.
- Arrival swing in the app: 16°, settled by `spring.arrive`.
- Drop on the site: −7° to 3° to −1.2° to 0.4° to rest.
- Flight tilt: −9° at the top of the arc (9° in right-to-left).
- Strike: a postmark turns from −14° to its rest angle as it lands (the
  airmail label from −9°).

### Blur

- Only for words rising into focus on the site (10 px), once per page.
- Never on large surfaces, never in a loop, never on the app's panels.

### Interaction feedback

| Moment | Feedback |
|---|---|
| Hover | Grows by a `scale.hover` token on its spring; the pointer's target gets no other effect |
| Press | Shrinks to `scale.press` in `duration.press`; letting go eases back |
| Hold (a photo) | Shrinks over `duration.hold`, then its menu opens |
| Hold (the grip) | Its circle swells over `duration.hold`, then fills with the accent, a tap, and the line follows the pointer any way |
| Step taken (a guide) | A 40 pt accent ring spreads from 0.45 to 1 and fades where the click landed, 0.45 s ease-out; with Reduce Motion it only fades, 0.3 s |
| Copy | A small nudge, and "Copied" shows (`duration.short`) |
| Send | The paper plane (below); the line closes the gap with `spring.reflow` |
| Take down | Falls off the line (0.55 s in the app); leaves with a short fade on `ease.exit` on the site's desktop |
| Done or undoable | A note rises above the Dock with Undo (site desktop demo) |
| Failure | No shake or beep: a `Notice` says what happened and what to do |
| Copy ready (iPhone) | The status capsule's shield bounces up once (`symbolEffect(.bounce)`) with a success haptic |
| Scan tab shown (iPhone) | `sweep.scan`: a green reading line crosses the drawn page once, 0.9 s, fading in and out at the ends; none with Reduce Motion |

### Reduce Motion

- **App:** `Motion.spring` becomes a 0.15 s ease-out; flights, swings, the
  sway and the stack fan become fades; AppKit reads `Motion.reduced`.
- **Site:** `prefers-reduced-motion` cuts animations to an instant,
  transitions to 0.15 s, stops the sway and every arrival, skips the
  paper-plane flight and the theme cross-fade, and shows each of the
  story's moments as it ends. The desktop demo keeps fades alone. The
  `site-tests` suite checks this.
- **Video:** has no reduced form; it is opt-in media the viewer starts.
- **iPhone:** read `accessibilityReduceMotion` (UIKit:
  `UIAccessibility.isReduceMotionEnabled`): covers and the scan line are
  simply there or absent, grid cards and the status capsule fade over
  0.15 s; the shield's bounce is the system's, which Reduce Motion tones
  down itself.
- **Rule:** a change that adds motion defines its reduced form in the same
  change.

## The signature: take off and hang

Two moves make Snapfly's motion recognisable. They belong to the photo and
to nothing else; don't put them on ordinary buttons.

- **Take off.** A card lifts up and toward the reading end, tilting −9°,
  then glides to where it goes and lands with a small settle: 820 ms on
  `ease.flight` on the site; the app's capture and send flights follow the
  same idea. It is the icon in motion, and it means "sent".
- **Hang.** A card drops onto its clip and swings to rest, each swing
  smaller (`hang-in` on the site, `spring.arrive` in the app), then sways
  a little. It means "here, ready".

On the website a third move belongs to the envelope: **strike.** A postmark
comes down onto what was sent, from 118% to rest in `duration.strike`, a
short thud and no bounce after it, and stays with the time it was sent. The
first view ends with one (after the airmail label), and every photo that
lands in the hero's chat gets one. Nothing on the site floats; things hang,
fly or are struck.

The bold look keeps take off and the sway, and changes the arrival: the
cards are **dealt** onto the line from the trailing side, turned 16°, each
straightening as it lands, 90 ms apart; its giant words **rise** out of a
mask; its band of words **runs** on, the one thing that loops besides the
sway. With Reduce Motion the cards and words are simply there and the band
stands still.

The same two moves carry over to onboarding, the website and videos, with
the same curves, so every place feels like one product.

## Concepts for future work

Not built unless marked "ships today". Each needs the owner's go-ahead,
and each must keep every rule above. The theme reveal (C) and the scroll
story (D) shipped at the owner's request in October 2026.

### A. Hero animation

The website's first view already arrives once: the rope draws across
(0.9 s), photos hang one after another, the words rise into focus, the chat
opens like a window. Refinements, if wanted:

- **Show where photos come from.** After the others, one card flies in from
  the menu bar's screenshot button and hangs last, so the first view tells
  the whole story: take, hang, send.
- **Controlled depth without parallax.** The chat window opens a beat later
  on a longer curve, so the line reads as near the top edge and the chat as
  in front. No scroll-linked parallax.
- **Shorter on return.** Play the full intro once per visit and show the
  settled state on later pages (a `sessionStorage` flag).
- **Budget:** settled within 2.2 s; transform, opacity and the rope's
  `clip-path` only; Reduce Motion shows it settled.

### B. Screenshot interaction

How a photo behaves, in the app and in the site's demos, with what ships
marked.

| Action | Motion | Ships today |
|---|---|---|
| Hover | `scale.hover.card` on `spring.card`; its corner buttons appear | App, site |
| Drag along the line | Lifts to `scale.lift`, follows the pointer 1:1, sway paused; neighbours make room with `spring.reflow` (site: 0.6 s `ease.out`) | Site; app reorders by drag |
| Drop | Settles on its clip with `spring.arrive` | App, site |
| Rearrange by keyboard | Option and an arrow: the same reflow as a drag | Site |
| Copy | A small nudge, and "Copied" shows | App, site |
| Send | Take off (the signature), then lands in the chat with `scale.settle`; the line closes the gap | App, site |
| Dismiss | Falls off the line (app, 0.55 s) or fades out on `ease.exit` (site); never flies off sideways | App, site |
| Pin | The pin badge springs in with `spring.card` | App |

Future: a dropped photo that lands between two others could nudge them
with one small swing, so the line feels like a rope.

### C. Theme switching

Ships today: the head script sets the theme before the first paint, so no
wrong colour ever flashes. A change spreads the new theme over the page
in a circle from the swatch that was chosen, through the View
Transitions API: a `clip-path` circle on `::view-transition-new(root)`
over the old page, `duration.reveal` on `ease.out`, reaching the farthest
corner last. The thumb slides to the chosen swatch (0.45 s), the browser
bar colour follows, other open tabs follow at once, and Reduce Motion or
a browser without View Transitions switches at once. Never transition
colours property by property across the page; one snapshot is cheaper and
has no half-mixed frames.

### D. Scroll storytelling

Restrained: things arrive once as they come into view (ships today). The
"how a screenshot travels" section (ships today, German only for now) follows one screenshot
through five beats, each on a small Mac screen, each played once and never
scrubbed, when three quarters of its screen is in view above the window's
bottom quarter, so the next one waits for the eye:

1. Take it: ⌃⌥S pressed in turn (`stagger.moment`), a selection dragged
   corner to corner (0.85 s, `ease.out`), the flash.
2. It hangs on the line: the line comes down from under the menu bar
   (0.6 s), the stamp drops onto its clip (`hang-in`), then sways.
3. A name is covered: cover ink grows line by line (`stagger.moment`),
   then the lock badge springs in.
4. It takes off into the chat: the signature take-off (`duration.flight`,
   `ease.flight`, −9°), a dashed path drawn behind it, a postmark struck as
   it lands.
5. The line tucks away: the empty line goes back up (0.5 s, ease-in), as
   the app's does.

Until its turn a beat holds its first frame; without scripts, with Reduce
Motion and in print each shows how it ends.

Rules: no scroll-jacking, no pinned section taller than one screen,
nothing that hides content until a scroll. Scroll-driven CSS
(`animation-timeline: view()`) only as an enhancement inside
`@supports`, with `IntersectionObserver` as the trigger everywhere else.

### E. Brand signature motion

Take off and hang (above) are the signature. To use them elsewhere:

- **Onboarding (app):** the first screenshot after install hangs with
  `spring.arrive`; the first send takes off. The introduction adds only
  `spring.guide` for its hole and `ease.out` for its card: it points, it
  does not perform.
- **Website:** every send in a demo takes off; every new photo hangs, and
  the four steps hang on their own line.
- **Videos:** scenes join with a take-off. A card leaving one scene is the
  card arriving in the next, instead of generic wipes.
- **Never:** on loaders, on buttons that don't send, or as decoration.

### F. Cinematic brand intro (5–10 seconds)

A production concept for a short brand piece. It is not rendered or
published.

| Time | Beat |
|---|---|
| 0.0–1.0 s | The theme's wallpaper fades up from black; a hairline rope draws across. |
| 1.0–2.6 s | Three drawn screenshots hang one after another and swing to rest. |
| 2.6–3.4 s | Cover ink grows over a name on one of them, line by line. |
| 3.4–4.6 s | The newest card takes off up and toward the reading end. |
| 4.6–6.0 s | It glides into the centre and becomes the app icon (the real `assets/icon.png`, cross-faded in at the card's size and angle, then settled to straight). |
| 6.0–8.0 s | "Snapfly" rises in under it, Semibold; the tagline follows 120 ms later. Hold. |

- **Formats:** 16:9 (1920 × 1080), 9:16 (1080 × 1920) and 1:1
  (1080 × 1080), at 30 fps, with the safe areas in `BRAND_GUIDELINES.md`.
  In 16:9 the icon sits beside the name; in 9:16 and 1:1, above it.
- **Variants:** one per theme (Original Sunset first) and per language
  (English, German, Arabic; Arabic mirrors the take-off).
- **Sound:** none in the master.
- **Rules:** the icon is never redrawn or recoloured; words are the app's
  own; no claims.

## Engineering standards

For every future implementation:

- **60 fps.** Animate `transform` and `opacity` (and `clip-path` for the
  rope). Never animate `width`, `height`, `top`, `left` or `margin` on large
  elements; read layout once, then write.
- **Little JavaScript.** CSS transitions and keyframes first, then the Web
  Animations API (`element.animate`) for paths computed at run time, like
  the flight. Observers, not scroll listeners; listeners passive.
- **Cleanup.** Await `animation.finished`, then remove ghosts and clear
  inline styles; cancel a running animation when a new action takes over;
  disconnect an observer once its work is done; never leave a
  `requestAnimationFrame` loop running in a hidden tab.
- **`will-change`** only around an animation that needs it, removed after.
- **Blur** only as described above; no backdrop blur on moving elements.
- **Battery and network.** No video backgrounds, no autoplaying media, no
  WebGL, no continuous animation other than the sway. Load heavy demos
  only when they come into view.
- **Mobile Safari.** Test where the View Transitions API is missing (the
  switch must be instant), with `-webkit-backdrop-filter`, with the
  dynamic toolbar (`svh` and `dvh`, not `100vh`), and with no hover.
- **Accessibility.** Reduce Motion as above; nothing flashes more than three
  times a second; focus stays visible and never moves because of an
  animation; keyboard users get the same feedback as the pointer.
- **Compatibility.** Everything degrades to the settled state: no
  JavaScript, a browser without an API, or print shows content in place.
- **The app.** SwiftUI goes through `Motion.spring`; AppKit checks
  `Motion.reduced`; photos move only through `Layout`, for the view and
  for every flight.

## Libraries and tools

| Option | Decision | Why |
|---|---|---|
| CSS, Web Animations API, View Transitions | **Used** | Everything the site does today runs on them, with no bytes added and nothing loaded from another host. |
| Motion (motion.dev) | Future option, not a dependency | For a gesture CSS can't do well (a throw with inertia, a spring that follows the pointer). Then the vanilla `animate()` only, saved into `website/static` (the policy allows nothing from another host), and never alongside GSAP. The agent has the Motion skill and docs server for this. |
| GSAP | Installed in `website/vendor/gsap`, used by no page | For a long, scrubbed, many-track timeline. Same rules as Motion; only one of the two, ever. |
| Rive | Installed in `website/vendor/rive`, used by no page | Adds a WebAssembly runtime for state-machine illustrations. Only for an interactive illustration SVG and CSS cannot do. |
| dotLottie | Installed in `website/vendor/dotlottie`, used by no page | There are no Lottie assets; inline SVG and CSS cover icons and success marks. Only if a designer delivers Lottie files worth the player. |
| Remotion | For videos only, in its own workspace | Never in the website. See below. |

## Creative production

Where each kind of work is made, so videos and animated assets never
weigh on the website.

| Work | Where | How |
|---|---|---|
| Website motion | `website/` | CSS and `site.js`; tokens above. No framework, no build dependencies. |
| Website checks | `site-tests/` | Playwright tests; not shipped, not in a workflow. |
| Promo video (today) | `promo/` | An HTML timeline (`seek(t)`) rendered frame by frame with Playwright and ffmpeg. 9:16 now; 16:9 and 1:1 by adding sizes to its layout. Output in `promo/out/`, ignored by git. |
| Remotion videos (when needed) | A new top-level `video/` folder, not created yet | Its own `package.json` and lockfile; compositions for 1920 × 1080, 1080 × 1920 and 1080 × 1080; reuses the website's drawings and the app's strings; renders locally to `video/out/`, ignored by git. Outside `website/`, so the website and its workflows never see it. Check Remotion's license (free for individuals and small teams) before use. |
| Static compositions | Scratch folder | The `canvas-design` skill, on the brand above. Committed only if the owner wants them, under `assets/`. |

Rules for all of it:

- Nothing is rendered for release, published or replaced without the
  owner.
- One source for words (`Localizable.strings`, `website/content.py`) and
  one for drawings (`website/build.py`).
- Renders and exports stay out of git.

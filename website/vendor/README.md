# Website libraries, ready but unused

Installed at the owner's request on October 17, 2026, so they are at hand
when a design needs one. **No page loads any of them.** `build.py` copies only
the files directly in `website/static/`, so this folder is never published
and visitors download none of it.

| Folder | What | Version | License |
|---|---|---|---|
| `gsap/` | GSAP and its plugins (`*.min.js`) | 3.15.0 | GreenSock Standard "no charge" (`gsap/LICENSE.md`) |
| `rive/` | Rive web runtime, canvas renderer: `rive.js`, `rive.wasm`, `rive_fallback.wasm` | `@rive-app/canvas` 2.44.0 | MIT (`rive/LICENSE.md`) |
| `dotlottie/` | dotLottie web player: `index.js` (a module), `dotlottie-player.wasm` | `@lottiefiles/dotlottie-web` 0.80.0 | MIT |
| `floating-ui/` | Floating UI for the DOM, two browser modules | `@floating-ui/dom` and `core` 1.8.0 | MIT |
| `daisyui/` | daisyUI's full stylesheet and themes | 5.7.47 | MIT |
| `lucide/` | Lucide icons as one sprite (1,858 symbols) and their search words | `lucide-static` 1.50.0 | ISC |
| `phosphor/` | Phosphor icons, one sprite per weight (thin, light, regular, bold, fill, duotone; 1,512 each) and their search words | `@phosphor-icons/core` 2.1.1 | MIT |

Each was downloaded from npm with `npm pack` (no install scripts run; none
of them has one), at the newest version at least two weeks old. Only the
files a browser needs were kept. Two changes were made:

- `floating-ui/floating-ui.dom.browser.min.mjs` imports
  `./floating-ui.core.browser.min.mjs` instead of the package name
  `@floating-ui/core`, so it runs in a browser without a bundler.
- The Phosphor sprites were made from the package's single-icon SVGs: each
  icon is a `<symbol>` with its own name, the weight suffix dropped.

Checked in Chromium on October 17, 2026, from these files alone, with no
request to another host: GSAP and ScrollTrigger ran, Floating UI exported
`computePosition`, daisyUI styled a `.btn`, Rive's and dotLottie's
WebAssembly started, and both icon sprites drew.

## Using one

- **Rules first.** `DESIGN.md`, `MOTION_SYSTEM.md` and `BRAND_IDENTITY.md`
  still decide what the site looks like and how it moves. A library is
  adopted for a job they allow, in every look, theme and language, and
  `site-tests` must pass.
- **Ship only what a page uses:** copy that file into `website/static/` (it
  is then published under `assets/`) and reference it from the page. Never
  link a CDN; the site loads nothing from another host.
- **GSAP, Motion:** only one of the two, ever (`MOTION_SYSTEM.md`).
  Honour Reduce Motion.
- **Rive and dotLottie** load WebAssembly from a CDN by default. Point them
  at the copy here first (`rive.RuntimeLoader.setWasmUrl(…)`,
  `DotLottie.setWasmUrl(…)`), and add `'wasm-unsafe-eval'` to `script-src`
  in `vercel.json`'s Content Security Policy. Their animations are made in
  the Rive editor or as Lottie files.
- **daisyUI** styles common class names (`.btn`, `.menu`, `.card` …) and
  would restyle the site if linked whole. Take single rules from it, renamed
  to the site's tokens.
- **Icons:** pick a symbol by name (search `tags.json`) and copy its paths
  into `ICONS` in `build.py`, drawn to SF Symbols' proportions as
  `BRAND_IDENTITY.md` asks. Don't link the sprites.
- **shadcn/ui** is React; it is not here. The agent browses its components
  through the shadcn MCP server (`.mcp.json`) as references to rebuild in
  the site's own HTML and CSS.

## Updating

Repeat the same `npm pack`, keep the same files and the two changes above,
check them in a browser again, and record the versions here and in
`.claude/skills/VENDORED.md`.

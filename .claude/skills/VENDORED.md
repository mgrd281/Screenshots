# Vendored agent skills and MCP servers

These are tools for the coding agent, not parts of Snapfly. None of them is a
dependency of the app or the website: nothing here is built, shipped or loaded
by a visitor. The website libraries in `website/vendor/` are the same until a
page adopts one.

- **Skills.** Third-party Claude Code skills live in this folder. Each was
  copied from its official source and read before it was added. Claude Code
  picks them up from `.claude/skills/<name>/SKILL.md` at the start of every
  session in this repository.
- **MCP servers.** Project MCP servers are listed in `.mcp.json` at the
  repository root. Claude Code asks once before it connects to one.
- **Website tests.** `site-tests/` holds browser tests for the website,
  written with Playwright. They have their own `package.json`, are not part
  of the site and run in no workflow.

| Skill or server | Source | Version | License |
|---|---|---|---|
| `impeccable/` | https://github.com/pbakaus/impeccable | 4.5.2, commit c686908 | Apache 2.0 (`impeccable/LICENSE`, `impeccable/NOTICE.md`) |
| `ui-ux-pro-max/` | https://github.com/nextlevelbuilder/ui-ux-pro-max-skill | commit 56ea9cf | MIT (`ui-ux-pro-max/LICENSE`) |
| `frontend-design/` | https://github.com/anthropics/skills, `skills/frontend-design` | commit dbd4588 | Apache 2.0 (`frontend-design/LICENSE.txt`) |
| `web-design-guidelines/` | https://github.com/vercel-labs/agent-skills, `skills/web-design-guidelines` | 1.0.0, commit 063bee9 | MIT (stated in the repository's README; it has no license file) |
| `context7-mcp/` | https://github.com/upstash/context7, `skills/context7-mcp` | commit 1658cc4 | MIT (`context7-mcp/LICENSE`) |
| Context7 MCP server (`.mcp.json`) | https://github.com/upstash/context7, hosted at `https://mcp.context7.com/mcp` | hosted | MIT |
| Playwright MCP server (`.mcp.json`, `.claude/mcp/playwright-mcp.sh`) | https://github.com/microsoft/playwright-mcp, npm `@playwright/mcp` | 0.0.83, pinned | Apache 2.0 |
| `site-tests/` (Playwright Test) | https://github.com/microsoft/playwright, npm `@playwright/test` | 1.56.1, pinned with a lockfile | Apache 2.0 |
| `ui-animation/` | https://github.com/mblode/agent-skills, `skills/ui-animation` | commit 872bc83 | MIT (`ui-animation/LICENSE.md`) |
| `motion/` | https://github.com/motiondivision/ai-kit, `plugins/motion/skills/motion` (what `npx motion-ai` installs) | commit b7e2c68 | MIT (the `motion-ai` package's license; the folder has no license file) |
| Motion docs MCP server (`.mcp.json`) | hosted at `https://mcp.motion.dev` | hosted | free; no account |
| `remotion-best-practices/` | https://github.com/remotion-dev/skills, `skills/remotion-best-practices` | commit 039e8a2 (refreshed October 20, 2026) | none stated (no license file or field) |
| `video-shotcraft/` | https://github.com/Vincentwei1021/video-shotcraft | commit 43bd349 | Apache 2.0 (`video-shotcraft/LICENSE`) |
| `hyperframes/`, `hyperframes-core/`, `hyperframes-animation/`, `hyperframes-cli/`, `hyperframes-creative/`, `hyperframes-keyframes/`, `hyperframes-registry/`, `hyperframes-audio/`, `motion-graphics/`, `product-launch-video/`, `general-video/`, `media-use/` | https://github.com/heygen-com/hyperframes, `skills/` | commit b7fa007; CLI 0.8.181 | Apache 2.0 (`hyperframes/LICENSE`) |
| `figma-use/`, `figma-use-motion/`, `figma-implement-motion/` | https://github.com/figma/mcp-server-guide, `skills/` | commit 7047cb4 | none stated in the repository |
| LottieFiles Creator MCP server (`.mcp.json`, `.claude/mcp/lottie-creator-mcp.sh`) | npm `@lottiefiles/creator-mcp` | 0.2.2, pinned | MIT |
| Creatomate MCP server (`.mcp.json`) | hosted at `https://api.creatomate.com/mcp` | hosted | paid service; the owner's account |
| `brand-context/`, `brand-identity/`, `brand-guidelines/`, `brand-audit/`, `brand-voice/` | https://github.com/arnabbagxd/Brand-building-skills | commit 4a0a8b5 | MIT (`LICENSE` in each) |
| `canvas-design/` | https://github.com/anthropics/skills, `skills/canvas-design` | commit dbd4588 | Apache 2.0 (`canvas-design/LICENSE.txt`) |
| shadcn MCP server (`.mcp.json`, `.claude/mcp/shadcn-mcp.sh`) | https://github.com/shadcn-ui/ui, npm `shadcn` | 4.21.1, pinned | MIT |
| `website/vendor/` (GSAP, Rive, dotLottie, Floating UI, daisyUI, Lucide, Phosphor) | npm, see `website/vendor/README.md` | pinned there | see `website/vendor/README.md` |

## Impeccable

- **Installed** from the repository's `.claude/` distribution (its Option 4,
  manual copy):
  - `SKILL.md` and `reference/`;
  - two of its subagents, `.claude/agents/impeccable-documenter.md` and
    `.claude/agents/impeccable-finish-reviewer.md`.
- **Left out on purpose:**
  - `scripts/`. Its launcher downloads a prebuilt engine binary from the
    internet on first run and executes it. That engine reads web projects
    (HTML, CSS, a live browser), so it has nothing to read in a SwiftUI app.
  - The hooks in its `.claude/settings.json`. They would run that binary on
    every edit and at every session start.
  - The `asset-producer` and `manual-edit-applier` agents. They exist for web
    image pipelines and live-browser editing.
- **What changes without the launcher:** the skill's own fallback applies. Its
  SKILL.md says "Launcher unavailable: … read the existing PRODUCT.md and
  DESIGN.md". Both are at the repository root.
- **What no longer works:** `pin`, `hooks`, `live` and `generate`. They need
  the engine or a browser.

## UI/UX Pro Max

- **Installed** as `uipro init --ai claude` would for a project:
  - `SKILL.md` rendered from `cli/assets/templates`, with the script path
    `.claude/skills/ui-ux-pro-max/scripts/search.py`;
  - `data/` and `scripts/` from `cli/assets`.
- **Checked again on October 15, 2026:** the source is still at commit
  56ea9cf, and `data/` and `scripts/` match it file for file. Nothing was
  reinstalled.
- **Left out:**
  - `scripts/tests/`, the authors' test suite.
  - The bundled sub-skills (`banner-design`, `brand`, `design`,
    `design-system`, `slides`, `ui-styling`). They cover web, marketing and
    slide work Snapfly doesn't have.
- **Safety.** The scripts use only the Python standard library. They make no
  network calls and start no processes; the only `subprocess` use is in the
  excluded tests.
- **Requirements.** Needs `python3`. The SwiftUI stack is
  `--stack swiftui`.

## Frontend Design

- **Installed:** `SKILL.md` and `LICENSE.txt`, copied unchanged. It is plain
  guidance: no scripts, no network, no dependencies.
- **Not used:** the repository's plugin marketplace (`/plugin marketplace
  add anthropics/skills`). It would install for the user rather than for this
  project, and bring the document and example skills along.
- **Where it gives way:** its advice to choose distinctive typefaces does not
  apply; the app and the website use system fonts only. `DESIGN.md`,
  `PRODUCT.md` and the owner's brief come first, as `CLAUDE.md` says.

## Web Interface Guidelines (Vercel)

- **Installed:** `web-design-guidelines/SKILL.md`, copied unchanged. When
  asked to review interface code, it fetches Vercel's current guidelines from
  `https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md`
  and reports findings as `file:line`. Useful for `website/`.
- **Not used:** the repository's installer, `npx skills add
  vercel-labs/agent-skills`. It is a script from the network, and copying the
  one file needs none.
- **Left out of the same repository**, and why:
  - `react-best-practices`, `composition-patterns`, `react-native-skills`,
    `react-view-transitions`: Snapfly has no React, Next.js or React Native.
    The website uses the browser's own View Transitions without React.
  - `deploy-to-vercel`, `vercel-cli-with-tokens`: they deploy from the agent.
    Snapfly's website is deployed by GitHub and Vercel's Git integration after
    a merge, and nothing goes live without the owner.
  - `vercel-optimize`: it tunes cost and speed of server-rendered apps from
    Vercel metrics and needs a Vercel token. The website is static.
  - `writing-guidelines`: the site's words follow the rules in `CLAUDE.md`
    and `website/BRIEF.md` instead.

## Context7

- **Installed:**
  - The hosted MCP server in `.mcp.json`, scope project, type `http`. It adds
    two tools, `resolve-library-id` and `query-docs`. Nothing runs locally:
    no Node, npm or npx.
  - `context7-mcp/SKILL.md`, the project's official skill that tells the
    agent when to use those tools (library and framework questions).
- **Not used:**
  - `npx ctx7 setup`. It runs a package from npm and signs in through
    OAuth in a browser.
  - The Claude Code plugin. It installs for the user, not the project, and
    signs in through a browser.
- **The key stays out of the repository.** `.mcp.json` sends
  `Authorization: Bearer ${CONTEXT7_API_KEY:-}`. Claude Code fills it in from
  the environment when the session starts. Without the variable the header
  is empty and Context7 answers on its shared free quota, which can run out.
  - A free key comes from https://context7.com/dashboard.
  - In a Claude Code cloud environment, add it in the environment's settings
    as `CONTEXT7_API_KEY`. On a Mac, export it in the shell profile. Never
    commit it.
- **Approval.** Claude Code shows the server as "Pending approval" until
  someone approves it in an interactive session; `claude mcp list` shows the
  state.
- **Checked on October 17, 2026:** the server answered "Monthly quota
  exceeded". The shared free quota is used up, so it returns documentation
  only once the key above is set.

## Playwright and Playwright MCP

- **Playwright MCP server,** scope project, type `stdio`. It gives the agent
  a real browser to open the website, click, type, read the page and take
  screenshots (25 tools).
  - `.mcp.json` starts `.claude/mcp/playwright-mcp.sh`, which runs
    `npx -y @playwright/mcp@0.0.83 --headless --isolated` at that pinned
    version. Pages it saves go to `.playwright-mcp/`, ignored by git.
  - In a Claude Code cloud container the script points it at the Chromium
    in `/opt/pw-browsers` and turns Chromium's own sandbox off: the
    container runs as root, where that sandbox cannot start, and is itself
    the sandbox. Anywhere else nothing is changed and the sandbox stays on.
  - **Checked on October 15, 2026,** by driving it the way Claude Code
    does (initialize, list tools, call them): it opened the German page,
    read its title, language and the three theme swatches, chose Emerald
    Petrol and saw it stored. Again on October 17, 2026: it opened the
    published Arabic page and read its title.
- **Playwright Test,** in `site-tests/`, for the website: every page in
  three languages at desktop and phone sizes, the theme switcher, Reduce
  Motion. 34 tests, all passing on October 15, 2026. See
  `site-tests/README.md`.
  - `@playwright/test` is pinned to 1.56.1, the version whose Chromium the
    cloud container ships, so it runs there with no download. Its
    `node_modules/` and results are ignored by git.
  - It is a development tool: not in `website/`, not built, not shipped,
    and not in a workflow, so it can't hold up a merge or a deploy.
- **Not used:** `npx playwright install` in the container (the browser is
  already there), and the Playwright browser extension mode.

## UI Animation

- **Installed:** `SKILL.md`, `references/` and `scripts/`, copied
  unchanged. Guidance on springs, gestures, interruptible motion and
  reduced motion, and a way to measure motion from a recording.
- **Left out:** `evals/`, the authors' tests for the skill.
- **Scripts:** three Python files (`extract_frames.py`, `track_motion.py`,
  `fit_curves.py`). They read local files; `extract_frames.py` calls a
  local `ffmpeg`. No network.
- **Where it gives way:** `MOTION_SYSTEM.md` and `DESIGN.md` set Snapfly's
  durations, curves and springs. Its advice on adding interface sounds does not
  apply: Snapfly plays only macOS's own sounds, behind its sound setting.

## Motion

- **Installed:**
  - `motion/` with its five parts (best practices, docs search, CSS spring
    generation, performance audit, transition preview): the skill
    `npx motion-ai` would install, copied from its source instead of
    running the installer.
  - The hosted **Motion docs MCP server** (`https://mcp.motion.dev`), type
    `http`, no key. Its tool `search-motion-docs` takes a `searchTerm` and a
    `platform` (`js`, `react` or `vue`). Checked on October 15 and again
    on October 17, 2026: a search for springs in `js` returned the docs.
- **Not used:**
  - `npx motion-ai`. It runs a package from npm and writes into the user's
    editor settings.
  - The **Motion+** server. It is paid. Without it the skill's
    "MotionScore" performance audits are refused; the skill says so and
    the rest works.
- **Not installed:** the `motion` library itself. The website animates with
  CSS and the Web Animations API, and adding React or a library for that is
  out of scope. See "Libraries and tools" in `MOTION_SYSTEM.md`.

## Remotion

- **Installed:** `remotion-best-practices/`, the skills repository's router
  skill, copied unchanged. It already holds the others as folders: `remotion-create`,
  `remotion-markup`, `remotion-studio`, `remotion-render`, and also captions,
  docs, interactivity, maps, multimedia, SaaS and upgrade. Installing
  `remotion-create`, `-markup`, `-studio` and `-render` again on their own
  would duplicate them.
- **Scripts:** two `.mjs` helpers under the maps techniques prepare map
  data for videos; they run only if someone makes a map video.
- **Not installed:** Remotion itself. It needs React and a renderer, and the
  website must not. If a video needs it, it gets its own `video/` folder
  with its own `package.json` (see "Creative production" in
  `MOTION_SYSTEM.md`). Nothing is rendered or published without the owner.
- **License:** the skills repository states none. Remotion, the library,
  has its own license (free for individuals and small teams); check
  https://remotion.dev/license before using it.

## Motion and video tools (October 20, 2026)

The owner asked for the motion graphics tools on a list of twelve, as
necessary for the work. Each was looked up at its source first; what could
be installed for the agent in this repository was read, copied or pinned,
and tried here.

- **Remotion skills**, refreshed to the source's newest commit (it adds
  Arabic text, colour correction and timeline structure).
- **Video Shotcraft** (`video-shotcraft/`): a skill for product videos in
  Remotion, with 124 shot recipe cards, their demo code and a template.
  - **Copied:** `SKILL.md`, `references/`, `template/` (its Remotion
    project), `demos/` without `_legacy/`, `assets/lib`, `brand` and
    `scripts`, and `gallery/api/library.json`, the index its cards are
    checked against.
  - **Left out:** the audio library (37 MB: 149 sound effects and five
    pieces of music from Mixkit; its own record says six of them could not
    be traced, so they are not safe to publish), the gallery website,
    `workbench/`, `shot-polish/`, `videos/`, the authors' tests, and two
    tools for other services, `publish/` (posts to social networks) and
    `jianying-export/` (a Chinese editor's drafts). Its audio record stays
    as `assets/ATTRIBUTION-audio.md`. Snapfly's videos use the sound the
    owner approved, as before.
  - **Checked:** its template installed with install scripts off and
    rendered a frame here with Remotion 4.0.484, using the headless shell
    under `/opt/pw-browsers` (`--browser-executable`).
- **HyperFrames** (HeyGen): HTML and GSAP compositions rendered to video by
  its command-line tool, the way `promo/` already works.
  - **Copied:** twelve of its skills: the entry point, the core, animation,
    the command line, creative direction, keyframes, the registry, audio
    mixing, motion graphics, product launch videos, general video and
    media.
  - **Left out:** captions, talking-head recuts, music videos, pull request
    videos, faceless explainers, slideshows, the Remotion port and the
    studio, which cover work Snapfly doesn't do. The entry skill still
    names them; asked for one, it is not here.
  - **Not installed:** its command-line tool itself. It runs with `npx
    hyperframes@0.8.181`, pinned, when a video is made, as the skills say.
    Checked here: it made a portrait project and rendered ten seconds of
    1080 × 1920 video.
  - **Usage counters off.** The tool and its media skill send anonymous
    counts to PostHog unless told not to; `.claude/settings.json` sets
    `HYPERFRAMES_NO_TELEMETRY`, `DO_NOT_TRACK` and `HYPERFRAMES_SKIP_SKILLS`
    (which stops it checking its skills against GitHub at every start).
  - **Accounts.** Music, voices and pictures from HeyGen, Google or
    others need the owner's accounts and keys; sound effects come from
    Openverse without one. None is set up, and keys are never written here.
- **Figma motion:** `figma-use`, `figma-use-motion` and
  `figma-implement-motion`, the official Figma skills for animating designs
  and turning their motion into code. They need the Figma connector, which
  this account has.
- **LottieFiles Creator MCP server**, pinned at 0.2.2, install scripts off.
  It drives the Creator editor open in a browser on the same computer,
  through a connection on `127.0.0.1:3847`. Checked: it starts and offers
  108 tools. It does nothing until Creator is open, so it is for the
  owner's Mac, not for a cloud session.
- **Creatomate MCP server**, hosted. It asks for a sign-in in the browser
  (it answered 401 here without one) and spends the account's render
  credits. Paid; until the owner has an account it does nothing.

Not installed, and why:

- **Remotion and Revideo as libraries.** They belong in a video's own
  folder with its own `package.json`, when a video is made (`MOTION_SYSTEM.md`,
  "Creative production"), never in the website. Revideo is the same idea as
  Remotion at an early version, so it would be a second tool for one job.
- **DaVinci Resolve MCP** and **MCP for Blender.** Each controls an app on
  the owner's Mac (DaVinci Resolve Studio, Blender) through a local server
  started there. Nothing can be installed for them in this repository or a
  cloud session; on the Mac they are set up with the apps.
- **Runway.** Its MCP server is a connector of the Claude apps: the owner
  signs in to Runway in the app's connector settings, and each second of
  video spends Runway credits.
- **Claude Motion.** A feature of the Claude apps on Team and Enterprise
  plans, not something a repository installs.

## Brand-building skills

- **Installed:** `brand-context`, `brand-identity`, `brand-guidelines`,
  `brand-audit` and `brand-voice`: `SKILL.md` and `LICENSE` each, copied
  unchanged. Plain guidance, no scripts.
- **Left out:**
  - `evals/` in each, the authors' tests.
  - The repository's other skills (naming, strategy, messaging, positioning,
    rebranding and so on). Snapfly's name and brand exist; they are
    documented, not reinvented.
- **Context:** the skills read `.agents/brand-context.md` first. That file
  is a short summary pointing to `BRAND_IDENTITY.md`,
  `BRAND_GUIDELINES.md`, `DESIGN.md` and `PRODUCT.md`, which win where they
  differ.
- **Not the same as** Anthropic's `brand-guidelines` skill, which carries
  Anthropic's own brand. That one is not installed.

## Canvas Design

- **Installed:** `SKILL.md` and `LICENSE.txt`, copied unchanged. It makes
  static PNG and PDF compositions: posters, boards, store art.
- **Left out:** `canvas-fonts/`, a folder of more than fifty font files.
  Snapfly's artwork uses the system font, or the promo's Inter and Noto
  Sans Arabic; the skill's advice to pick fonts from that folder does not
  apply.
- **Where it gives way:** it works on Snapfly's brand
  (`BRAND_IDENTITY.md`, `BRAND_GUIDELINES.md`), not on a new style of its
  own. Nothing it makes is committed unless the owner wants it.

## Website libraries and the shadcn MCP server

- **Asked for by the owner on October 17, 2026,** after an earlier review
  had left them out, to have them at hand for the website's design.
- **Installed, unused:** GSAP, Rive, dotLottie, Floating UI, daisyUI, and
  the Lucide and Phosphor icons, in `website/vendor/`. No page loads them,
  and `build.py` never publishes that folder, so visitors download nothing
  new. Versions, licenses, the two small changes made, the browser check and
  how to adopt one are in `website/vendor/README.md`.
- **shadcn/ui** is React and Tailwind source, so it is not copied in. Its
  MCP server is, scope project, type `stdio`: `.claude/mcp/shadcn-mcp.sh`
  runs `npx -y shadcn@4.21.1 mcp` at that pinned version, with install
  scripts off. Its seven tools list, search and show the components and
  examples of shadcn/ui's registry, as references to rebuild in the site's
  own HTML and CSS.
  - **Checked on October 17, 2026,** the way Claude Code drives it
    (initialize, list tools, call one): a search for "dialog" in `@shadcn`
    found nine items.
  - Its `get_add_command_for_items` would add React components to a
    project; don't run what it suggests here.
- **Not installed:** any of them through a CDN, `npx shadcn init`, or
  Tailwind.

## Evaluated, not installed

- **AgentsORG DESIGN (`.design`).** Its skill drives a `.design` YAML file
  as the project's design contract: with none present it offers to create
  one, it ranks that file above everything else, and it asks other skills'
  `DESIGN.md` to be imported into it rather than kept. Snapfly's contract is
  `DESIGN.md`, which `CLAUDE.md` says wins. Two contracts would drift, so
  neither the skill nor a `.design` file was added. What it would offer
  (tokens, motion tokens, decisions, voice) is in `DESIGN.md`,
  `MOTION_SYSTEM.md` and `BRAND_IDENTITY.md`.
- **Vercel's React, deploy and optimisation skills.** As before, under "Web
  Interface Guidelines".

## Updating

- Clone the source again and repeat the same copy, with the same exclusions.
- Record the new commit in the table above.
- Never install a project's hooks, CLI, installer or launcher in this
  repository without reading it first.

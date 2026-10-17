# Snapfly: working notes for Claude

Snapfly is a macOS menu bar app that hangs screenshots on a line, made by
Mgrdegh Ghazarian. It started as a copy of Tendedero (MIT). The Swift target
and folder are still called `Tendedero`. The owner wants no mention of it
in the app's interface; the MIT License is satisfied by the notice in
`LICENSE`, which `scripts/build-app.sh` copies into the app bundle, and by
the website's footer. Both stay.

## Talking with the owner

- Write to the owner in **Arabic only**, in short, simple words. They are
  not a programmer.
  - That covers everything they see in the chat: replies, progress notes,
    and the short description shown with each command or tool call.
  - A tool's or file's name may stay in Latin letters, with an Arabic word
    saying what it is. No English sentences.
  - Answer in Arabic even when they write or send screenshots in German or
    English. Don't quote German or English words back; describe in Arabic
    what to tap (its place and look) instead.
- They usually can't reach their Mac. Never ask them to run Terminal
  commands. GitHub builds the app for them (see below).

## Merging

- Work on a branch and open a pull request. When the **Build Snapfly**
  workflow is green on the latest commit, **merge it into `main` yourself**
  with a merge commit.
- The owner has asked for this standing rule. Don't ask before merging, and
  don't announce each merge.
- Speak up only when something goes wrong: a red build you can't fix, or a
  merge conflict that needs a decision.
- Never merge a red build. Fix it first.

## Building and releases

- There is no Mac here. `.github/workflows/build.yml` builds on GitHub's
  macOS 26 runners (Xcode, macOS 26 SDK) at every push, then publishes
  `Snapfly.zip` to the Releases page:
  - **latest** from `main`: https://github.com/mgrd281/Screenshots/releases/tag/latest
  - **preview** from any other branch
- **Signing.** With the repository secret `SNAPFLY_SIGNING`, builds are signed
  with the owner's Developer ID, and builds from `main` are notarized and
  stapled (`scripts/signing.sh`). Without it they are ad-hoc signed, and the
  first open needs Privacy & Security, Open Anyway.
  - The owner makes that secret once, on their Mac, with
    `scripts/mac-signing.sh`. It holds the App Store Connect API key, its key
    ID and issuer, and the Developer ID key and certificate.
  - Never write secrets from a workflow or a script: the owner pastes them.
- **Mac App Store edition.** `STORE=1 scripts/build-app.sh` builds it with
  `APP_STORE` (`Edition.swift`).
  - It runs sandboxed: it watches Pictures › Snapfly, shows where to point the
    Screenshot app instead of changing its settings, keeps watched folders as
    bookmarks, and has no Check for Updates or Save to Desktop.
  - The **App Store** workflow signs and uploads it to TestFlight with
    `scripts/app-store.sh`. It needs the secrets `SNAPFLY_SIGNING` and
    `SNAPFLY_STORE` (made by `scripts/mac-store-signing.sh` on the owner's Mac),
    and the app record in App Store Connect. It runs on every push to `main`
    that touches the app (the owner asked for TestFlight to always be current),
    and by hand.
  - It may send Apple Events to the browsers listed in `scripts/app-store.sh`
    (a temporary exception), only to read the front page's address, so the
    send button over chats shows on chat websites alone. The direct edition
    signs with `com.apple.security.automation.apple-events` for the same.
  - No private Apple functions in it: the store refuses the app. Gate them
    with `#if !APP_STORE` and give the store edition a public way, as
    `FullScreen.swift` does. `scripts/check-private-apis.sh` checks the
    binary in both workflows.
  - The privacy policy for the store listing is the website's privacy page
    (below). `PRIVACY.md` is the short version in the repository.
- **Website.** `website/` builds https://mgrd281.github.io/Screenshots/ (English),
  `/de/` and `/ar/`: the landing page, `privacy.html` and `support.html`, the
  URLs App Store Connect links to.
  - `python3 website/build.py` writes it to `website/_site/` (standard
    library only). The **Website** workflow builds it at every push and
    publishes it from `main` on GitHub Pages.
  - Words live in `website/content.py`. Labels the app shows come from its
    `Localizable.strings`, so change them there.
  - **For now, site edits are German only** (the owner's request). Words in
    `website/content.py` change in `de` alone. The newest parts (the scroll
    story and the question glyphs) show only in the languages listed in
    `NEW_PARTS_LANGS` in `build.py`, which is German. English and Arabic stay
    as they were until the owner says the others follow.
  - System fonts only, and nothing loaded from another host.
  - `vercel.json` builds the same site on Vercel. `SNAPFLY_SITE_URL` (ending in
    a slash) sets the address the pages point to; set it to the custom domain.
    Its Content Security Policy lets in nothing from another host, which also
    keeps Vercel's toolbar off the previews, and allows the inline scripts
    (`INLINE_JS` in `build.py`) by their hashes. The build stops if they drift.
  - The page is an airmail envelope: aerogramme paper inside a chevron edge
    round the window, every screenshot a perforated stamp on the line, a
    postmark with the time on what is sent. Mac windows on it stay native.
  - A look switch beside the theme swatches offers two more looks, each a
    stylesheet scoped to `<html data-look="…">` and kept in `localStorage`
    as `snapfly-look`:
    - the classic Mac desktop the site had before (`static/classic.css`,
      the earlier stylesheet);
    - bold colour (`static/bold.css`): one colour field per theme, giant
      type, cards dealt onto the line and a band of the app's words.
    - The owner asked to keep all three. A change to shared parts must hold
      in every look; check all three.
  - Three brand themes, Original Sunset (the default), Emerald Petrol and
    Signature Orange, are chosen with the swatches in the menu bar and kept
    in `localStorage` (`snapfly-brand`). Light or dark stays the system's.
    Brand colours are tokens in `site.css`; see "Brand themes" in
    `DESIGN.md`.
  - Its design rules are under "Website" in `DESIGN.md`; its brief is
    `website/BRIEF.md`.
  - `site-tests/` checks it in a real browser with Playwright: every page in
    three languages, the theme switcher, Reduce Motion. Run `npm ci` and
    `npm test` there before pushing a change to the site. It is not part of
    the site and runs in no workflow; see `site-tests/README.md`.
- **Promo video.** `promo/` makes the vertical motion graphic in three
  languages; see `promo/README.md`. It reuses the website's drawings and the
  app's strings, so update it when either changes in a way the video shows.
  - It also makes the German Instagram ad, in a short and a long cut
    (`ad.js`, `ad-sound.py`), with voices and music from vidIQ that the owner
    approved. They are kept out of
    the repository.
- **iPhone app.** `iOS/` holds Snapfly for the iPhone: a SwiftUI app with
  the screenshots from Photos covered, and App Intents for Shortcuts and
  Back Tap. Same bundle ID as the Mac app, so one App Store record can hold
  both.
  - `iOS/Snapfly.xcodeproj` is written by hand and uses folder-synced groups:
    `iOS/Snapfly`, `Sources/Tendedero/Shared` and the translations in
    `Sources/Tendedero/Resources`. New files in those folders are picked up
    without touching it.
  - Code both apps use goes in `Sources/Tendedero/Shared`, without AppKit or
    UIKit. The Mac's SwiftPM target compiles it too.
  - The Build Snapfly workflow's `iphone` job archives it unsigned, with the
    shared scheme `Snapfly`. `check-strings.swift` reads `iOS/Snapfly` too.
  - `iOS/Snapfly/PrivacyInfo.xcprivacy` declares the APIs Apple asks a reason
    for (UserDefaults so far). Add to it when the app uses another.
  - The **iPhone App Store** workflow (`scripts/iphone-store.sh`) archives,
    signs and uploads it to TestFlight at every push to `main` that touches
    it, and by hand. It needs `SNAPFLY_SIGNING` and `SNAPFLY_IPHONE`, the
    Apple Distribution key and certificate, made by `scripts/iphone-signing.sh`
    on the owner's Mac. Without `SNAPFLY_IPHONE` it uploads nothing. The app's
    record in App Store Connect needs the iPhone (iOS) added beside macOS.
- **Tests.** `Tests/TendederoTests` holds XCTest tests for logic that needs no
  screen (parsing, sizes, file kinds). The Build Snapfly workflow runs
  `swift test` before building, so add a test with each new piece of such
  logic. A failure that would leave the user guessing gets a `Notice`, not a
  beep.
- Swift 5 language mode, macOS 14 deployment target, universal binary.
  Gate newer APIs with `if #available` and `#if canImport(...)`. Examples:
  - Translation needs macOS 15;
  - FoundationModels needs macOS 26 and is missing on Intel.

## Strings

- Every user-facing text goes through `L("English text")`, with a literal
  key.
- The key goes into each of the 13 `Sources/Tendedero/Resources/*.lproj/Localizable.strings`
  files: ar, az, de, en, es, fr, gl, hi, ja, ko, pt-BR, tr, zh-Hans.
- CI runs `swift scripts/check-strings.swift`, which fails on any key that
  is missing, unused or has mismatched placeholders. Without Swift here,
  check the same rules with a short Python script before pushing.
- In German, address the reader as "du", and put a space before "…"
  ("Suchen …").

## Design

- **`DESIGN.md` is the design system and it wins.** It sets the tokens,
  components, motion and accessibility rules, plus a list of banned patterns.
  `PRODUCT.md` holds the product context.
- **The brand and motion documents explain and apply it; they set no values
  of their own.**
  - `BRAND_IDENTITY.md`: what the brand is (name, icon, colour layers, the
    three themes as one brand, type, icons, motifs, voice).
  - `BRAND_GUIDELINES.md`: how to apply it, including social and store
    assets, and a checklist before shipping.
  - `MOTION_SYSTEM.md`: motion tokens named from what ships, the signature
    (take off and hang), concepts not yet built, engineering rules, and
    where videos are made.
- **Read both before any UI work.** That means any view, panel, menu, window,
  setting, icon, copy or motion.
- **When a change adds a color, radius, size or component,** add it to
  `DESIGN.md` in the same pull request.
- Agent skills sit in `.claude/skills/`, and four MCP servers (Context7,
  Playwright, Motion, shadcn) are set up for the project in `.mcp.json`. See
  `.claude/skills/VENDORED.md` for what was installed, what was left out,
  and why. None of them is part of the app or the website; they only guide
  the coding agent.
  - **Website libraries** the owner asked for (GSAP, Rive, dotLottie,
    Floating UI, daisyUI, Lucide and Phosphor icons) sit unused in
    `website/vendor/`, which is never published. A page takes one only for a
    job `DESIGN.md` allows; `website/vendor/README.md` says how.
  - The **shadcn** MCP server browses shadcn/ui's React components, as
    references to rebuild in the site's own HTML and CSS, never to add
    React.
  - **`impeccable`** handles design direction, critique and polish.
    - Commands: `/impeccable critique|audit|polish|layout|typeset|clarify|harden|distill|quieter <target>`.
    - Its launcher and hooks are deliberately not installed. When it says the
      launcher is unavailable, that's expected. Follow its fallback and read
      `PRODUCT.md` and `DESIGN.md`.
    - Use `audit.native.md` and `adapt.native.md` rather than the web
      variants.
  - **`ui-ux-pro-max`** is a searchable guideline database.
    - Search it like this:
      `python3 .claude/skills/ui-ux-pro-max/scripts/search.py "<query>" --stack swiftui`,
      or with `--domain ux|style|color|typography` in place of the stack.
    - Its web advice (CSS, Tailwind, breakpoints, 44 px touch targets) has to
      be translated into SwiftUI and AppKit for a pointer-driven Mac app. Where
      the two disagree, `DESIGN.md` wins.
  - **`frontend-design`** (Anthropic) gives direction for new visual work.
    Its advice to pick distinctive typefaces does not apply here: the app and
    the website use system fonts only.
  - **`web-design-guidelines`** (Vercel) reviews website code against Vercel's
    Web Interface Guidelines, which it fetches fresh each time.
  - **`context7-mcp`** with the **Context7** MCP server looks up current
    documentation for libraries and frameworks. It reads the key from the
    `CONTEXT7_API_KEY` environment variable; without one, the shared free quota
    may already be used up.
  - The **Playwright** MCP server gives the agent a browser to try the
    website in (`.claude/mcp/playwright-mcp.sh`, a pinned version).
  - **`ui-animation`** and **`motion`** (with the **Motion** docs server)
    guide motion work. On the website that means CSS and the Web Animations
    API, not the Motion library or React; values come from
    `MOTION_SYSTEM.md`.
  - **`remotion-best-practices`** (with create, markup, studio and render
    inside it) is for videos only, in their own workspace, never in the
    website. Nothing is rendered or published without the owner.
  - **`brand-context`, `brand-identity`, `brand-guidelines`, `brand-audit`,
    `brand-voice`** document and check the existing brand. They read
    `.agents/brand-context.md`, a summary that points to the brand
    documents. Never use them to rename or rebrand.
  - **`canvas-design`** makes static compositions (store art, boards) on
    Snapfly's brand, in the system font.
  - Every design skill gives way to `DESIGN.md`, `PRODUCT.md` and the owner's
    brief.
- **No redesign without the owner asking.** Refinement keeps the existing
  look.

## Code

- Match the surrounding style. Comments are plain English sentences about
  what the code is for, not how it works.
- UI types are `@MainActor`. From GCD callbacks, hop back with
  `DispatchQueue.main.async { MainActor.assumeIsolated { … } }`.
- Update `README.md` when behaviour changes. That covers the gesture table,
  the feature sections and the file table.

# Snapfly: working notes for Claude

Snapfly is a macOS menu bar app that hangs screenshots on a line, made by
Mgrdegh Ghazarian. It started as a copy of Tendedero (MIT). The Swift target
and folder are still called `Tendedero`. The owner wants no mention of it
in the app's interface; the MIT License is satisfied by the notice in
`LICENSE`, which `scripts/build-app.sh` copies into the app bundle, and by
the website's footer. Both stay.

## Talking with the owner

- **Always answer the owner in Arabic**, whatever language they write in
  (the owner's request). Even when they write, or send screenshots, in
  German or English, the answer is in Arabic, in short, simple words. They
  are not a programmer.
  - That covers everything they see in the chat: replies, progress notes,
    and the short description shown with each command or tool call.
  - A tool's or file's name may stay in Latin letters, with an Arabic word
    saying what it is. No English sentences.
  - Don't quote German or English words back; describe in Arabic what to
    tap (its place and look) instead.
- They usually can't reach their Mac. Never ask them to run Terminal
  commands. GitHub builds the app for them (see below).
- Send them one update when a task is finished, not a note at each step
  (the owner's request).

## Merging

- Work on a branch and open a pull request. When the **Build Snapfly**
  workflow is green on the latest commit, **merge it into `main` yourself**
  with a merge commit.
- The owner has asked for this standing rule. Don't ask before merging, and
  don't announce each merge.
- Speak up only when something goes wrong: a red build you can't fix, or a
  merge conflict that needs a decision.
- Never merge a red build. Fix it first.
- **Push once per task** (the owner's request). Commit as you go, but push
  the branch only when the whole task is done and checked: code, strings,
  tests and docs. Every push, and every merge into `main`, makes a Vercel
  deployment, and the free plan allows 100 a day; it ran out in October
  2026.
  - A fix for a red build is the one exception. Check it well first, so one
    push does it.
  - Vercel's status reading "Deployment rate limited" is that limit, not the
    pull request's fault. It doesn't gate merging; Build Snapfly does.

## Building and releases

- There is no Mac here. `.github/workflows/build.yml` builds on GitHub's
  macOS 26 runners (Xcode, macOS 26 SDK) at every push, then publishes
  `Snapfly.zip` to the Releases page:
  - **latest** from `main`: https://github.com/mgrd281/Screenshots/releases/tag/latest
  - **preview** from any other branch
- **Versions.** `VERSION` holds the version every edition carries (x.y.z),
  and `CHANGELOG.md` needs a `## x.y.z` section for it, or the build stops.
  - Add a line there with each change people notice.
  - Raise the middle number for a batch of features and the last for fixes,
    and always after a version goes to App Review: the store takes no more
    builds of it.
  - From `main`, the build also keeps a release of each version (`v1.1.0`)
    with its newest build, beside `latest`.
- **Pro, later.** `Shared/Plan.swift` lists the features that will need Pro.
  Nothing is held back until `Plan.proStarts` is set, which waits for the
  owner. A new feature of that kind joins the list and ships free. Covering
  private details is never Pro. See "Plans" in `PRODUCT.md`.
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
  - `docs/store/app-review.md` holds the notes for App Review and what
    each review asked for; add to it with each rejection.
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
  - **All three languages follow together** (the owner's decision, October
    2026, after a time of German-only edits). A change to the words in
    `website/content.py` is made in `en`, `de` and `ar` alike, each in its
    own natural words, with the app's own labels in that language. The
    newest parts (the scroll story, the short words over the titles, the
    question glyphs and the clean ground) show in every language listed in
    `NEW_PARTS_LANGS` in `build.py`, which is all three. Arabic reads right
    to left: check new parts there too, in both looks.
  - System fonts only, and nothing loaded from another host.
  - `vercel.json` builds the same site on Vercel. `SNAPFLY_SITE_URL` (ending in
    a slash) sets the address the pages point to; set it to the custom domain.
    Its Content Security Policy lets in nothing from another host, which also
    keeps Vercel's toolbar off the previews, and allows the inline scripts
    (`INLINE_JS` in `build.py`) by their hashes. The build stops if they drift.
  - **The airmail look was removed at the owner's request (October 2026).**
    The site now has two looks, the Mac desktop (the default) and bold
    colour. Its envelope rules remain in `site.css` as the base the two
    restyle; `DESIGN.md`'s airmail passages describe that base.
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
    - The Mac desktop look takes the clean ground
      (`static/clean.css`, linked for `NEW_PARTS_LANGS`): the theme's
      colour in the first view and the closing call, clean sections in
      ink between, a short word over each title. See "The clean ground"
      in `DESIGN.md`.
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
- **Share links.** `share/` is the Cloudflare Worker and R2 bucket behind
  Copy Link (see `share/README.md`). The **Share Links** workflow deploys it
  from `main` with the secrets `CLOUDFLARE_API_TOKEN` and
  `CLOUDFLARE_ACCOUNT_ID`, which the owner pastes. Builds put its address in
  Info.plist through `scripts/share-url.sh`; without it, Copy Link is left
  out. Files are deleted after seven days. Run `node --test
  share/worker.test.mjs` after changing the Worker.
- **Sync.** Mac and iPhone as one, through the owner's own iCloud (CloudKit,
  CKSyncEngine). `SYNC.md` holds the audit, the design, the threat model,
  the owner's Apple steps and what is verified; keep it current.
  - The rules live in `Shared/SyncModel.swift`, `SyncLedger.swift` and
    `SyncPolicy.swift`, tested by `SyncTests` on Linux too. What may leave a
    device is decided in `SyncPolicy` alone, and asked again just before it
    goes.
  - `Shared/CloudSync.swift` touches iCloud only when Info.plist names a
    container (`SnapflyCloudContainer`). A build adds that key together with
    the iCloud entitlement, never one without the other: opening a container
    the app is not entitled to stops it.
  - Off until the owner turns it on; covered copies only unless they choose
    originals. Never claim end-to-end encryption.
  - The builds add the iCloud entitlements and the Info.plist line only when
    Apple's profile allows them (`scripts/signing.sh cloud-profile` for the
    direct edition, `app-store.sh`, `iphone-store.sh`); otherwise syncing is
    left out and the build goes on.
  - `cloudkit/schema.ckdb` holds the record types. The **CloudKit Schema**
    workflow puts it into development with the secret
    `SNAPFLY_CLOUDKIT_TOKEN`; the owner deploys it to production in the
    CloudKit Console. A new record type or field needs both again.
  - `SyncCenter` (Shared) is the apps' way in; `MacSync` and `PhoneSync`
    connect the line and the iPhone's screens.
  - A Mac and an iPhone on different Apple accounts pair with a code
    (`Shared/Pairing.swift`, `PairingCloud.swift`): six digits, new every 30
    seconds, met in the public database (record type `Pairing`), then the
    Mac shares its zones with that account alone. Sharing needs the
    `cloudkit.share` type in production (`cloudkit/share.ckdb`, SYNC.md).
  - README, `PRIVACY.md`, the website and the app's texts describe syncing
    as it is; change them with it.
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
    for (UserDefaults and file timestamps so far). Add to it when the app uses another.
  - The first run's story is `Shared/FirstRun.swift`, tested on Linux; see
    `FIRST_RUN.md`. The **First Run Captures** workflow plays it on the
    simulator when it changes, and puts still frames, a recording and how
    soon it showed on the `first-run-captures` pre-release: the way to see
    iPhone UI without an iPhone. It also shows Protect Picture on the
    made-up invoice (`editor-*`, from `-SnapflyEditorSample` in debug
    builds) when the editor changes.
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
- **Covering.** Finding, telling what a find is, and covering only what the
  owner chose are kept apart (`Finder.findings`, then `decided`). Names
  means people's names: `DocumentSense` tells a person from a company and
  whose a name is. `RedactionTests` hold the cases; add one with each fix,
  and never fit the engine to one screenshot.
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
- Agent skills sit in `.claude/skills/`, and six MCP servers (Context7,
  Playwright, Motion, shadcn, LottieFiles Creator, Creatomate) are set up
  for the project in `.mcp.json`. See
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
  - **`swiftui-animation`** guides SwiftUI motion in both apps. It is
    written for iOS 26 and Swift 6, so gate newer APIs, and take values from
    `MOTION_SYSTEM.md`.
  - **`text-to-lottie`** writes Lottie files and checks them in its player,
    which is set up outside the repository.
    - Lottie, Pow and Rive join the iPhone app only when a motion needs them
      (the owner's choice, October 2026). See "Libraries and tools" in
      `MOTION_SYSTEM.md`.
    - Flutter and Capacitor tools don't apply.
  - **`remotion-best-practices`** (with create, markup, studio and render
    inside it) is for videos only, in their own workspace, never in the
    website. Nothing is rendered or published without the owner.
  - **Video tools** (the owner's list, October 2026):
    - `video-shotcraft` makes product videos in Remotion from shot recipe
      cards;
    - the `hyperframes` skills (start at `hyperframes`) make HTML and GSAP
      videos with `npx hyperframes@0.8.181`, its usage counters off in
      `.claude/settings.json`;
    - `figma-use-motion` and `figma-implement-motion` animate Figma designs
      and turn their motion into code;
    - the LottieFiles Creator server works only beside Creator open on the
      owner's Mac, and Creatomate only with the owner's paid account.
    - Videos are made outside `website/` (`MOTION_SYSTEM.md`, "Creative
      production"), and nothing is rendered for release or published
      without the owner. `.claude/skills/VENDORED.md` says what was left
      out (DaVinci Resolve, Blender, Runway, Claude Motion) and why.
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
- `.ua/` is Understand Anything's map of the code (files, types, what
  depends on what, tests, layers, a tour), written in Arabic for the owner.
  Read `.ua/knowledge-graph.json` to find your way around. After a change
  to the code, update it with `/understand` (it reads only the changed
  files) when the plugin is on. See "Understand Anything" in
  `.claude/skills/VENDORED.md`.

# Snapfly: working notes for Claude

Snapfly is a macOS menu bar app that hangs screenshots on a line, made by
Mgrdegh Ghazarian. It started as a copy of Tendedero (MIT). The Swift target
and folder are still called `Tendedero`. The credit in the About pane is
required by the license and stays.

## Talking with the owner

- Write to the owner in **Arabic only**, in short, simple words. They are
  not a programmer.
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
- **Read both before any UI work.** That means any view, panel, menu, window,
  setting, icon, copy or motion.
- **When a change adds a color, radius, size or component,** add it to
  `DESIGN.md` in the same pull request.
- Two design skills sit in `.claude/skills/`. See `.claude/skills/VENDORED.md`
  for what was installed and why.
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
- **No redesign without the owner asking.** Refinement keeps the existing
  look.

## Code

- Match the surrounding style. Comments are plain English sentences about
  what the code is for, not how it works.
- UI types are `@MainActor`. From GCD callbacks, hop back with
  `DispatchQueue.main.async { MainActor.assumeIsolated { … } }`.
- Update `README.md` when behaviour changes. That covers the gesture table,
  the feature sections and the file table.

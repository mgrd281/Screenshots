# Vendored design skills

Two third-party Claude Code skills live here. Each was copied from its
official Claude Code distribution and checked before it was added. Claude Code
picks them up from `.claude/skills/<name>/SKILL.md` at the start of every
session in this repository.

| Skill | Source | Version | License |
|---|---|---|---|
| `impeccable/` | https://github.com/pbakaus/impeccable | 4.5.2, commit c686908 | Apache 2.0 (`impeccable/LICENSE`, `impeccable/NOTICE.md`) |
| `ui-ux-pro-max/` | https://github.com/nextlevelbuilder/ui-ux-pro-max-skill | commit 56ea9cf | MIT (`ui-ux-pro-max/LICENSE`) |

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

## Updating

Clone the source again and repeat the same copy, with the same exclusions.
Record the new commit in the table above. Never install either project's hooks,
CLI or launcher in this repository without reading them first.

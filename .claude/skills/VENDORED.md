# Vendored agent skills and MCP servers

These are tools for the coding agent, not parts of Snapfly. None of them is a
dependency of the app or the website: nothing here is built, shipped or loaded
by a visitor.

- **Skills.** Third-party Claude Code skills live in this folder. Each was
  copied from its official source and read before it was added. Claude Code
  picks them up from `.claude/skills/<name>/SKILL.md` at the start of every
  session in this repository.
- **MCP servers.** Project MCP servers are listed in `.mcp.json` at the
  repository root. Claude Code asks once before it connects to one.

| Skill or server | Source | Version | License |
|---|---|---|---|
| `impeccable/` | https://github.com/pbakaus/impeccable | 4.5.2, commit c686908 | Apache 2.0 (`impeccable/LICENSE`, `impeccable/NOTICE.md`) |
| `ui-ux-pro-max/` | https://github.com/nextlevelbuilder/ui-ux-pro-max-skill | commit 56ea9cf | MIT (`ui-ux-pro-max/LICENSE`) |
| `frontend-design/` | https://github.com/anthropics/skills, `skills/frontend-design` | commit dbd4588 | Apache 2.0 (`frontend-design/LICENSE.txt`) |
| `web-design-guidelines/` | https://github.com/vercel-labs/agent-skills, `skills/web-design-guidelines` | 1.0.0, commit 063bee9 | MIT (stated in the repository's README; it has no license file) |
| `context7-mcp/` | https://github.com/upstash/context7, `skills/context7-mcp` | commit 1658cc4 | MIT (`context7-mcp/LICENSE`) |
| Context7 MCP server (`.mcp.json`) | https://github.com/upstash/context7, hosted at `https://mcp.context7.com/mcp` | hosted | MIT |

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

## Updating

- Clone the source again and repeat the same copy, with the same exclusions.
- Record the new commit in the table above.
- Never install a project's hooks, CLI, installer or launcher in this
  repository without reading it first.

# Website tests

Browser tests for the website in `website/`, written with
[Playwright](https://playwright.dev). They are a tool for whoever changes
the site, not part of it: nothing here is built, published or loaded by a
visitor, and no workflow runs them.

They build the site, serve it on `http://127.0.0.1:4173/` with the Content
Security Policy from `vercel.json`, and check in Chromium, at desktop and
phone sizes:

- every page in English, German and Arabic (the landing page, privacy,
  terms, withdrawal and support) loads without errors, in the right
  language and direction, with nothing from another host and no sideways
  scroll;
- the theme switcher: Original Sunset by default, each theme kept after a
  reload from the first paint, the arrows (in reading direction), another
  open tab following;
- the look switch: the Mac desktop by default, with no airmail look; the
  classic and bold colour looks kept after a reload from the first paint
  and loading cleanly in every language, the landing page and the three
  legal pages, the themes still working in them, the bold look's band
  running; the arrows between them;
- with Reduce Motion, the first view is all there at once, and in the bold
  look its band stands still.
- with a mouse, each look and brand chip takes a click 24 pt tall (the
  target reaches past its cell);
- after photos are sent into the chat, the page's ids are still unique;
- the cover switches in the privacy section change the preview and never
  send or reload the page (their pane is no form);
- the newest parts in every language: how a screenshot travels, the short
  word over each title, the clean ground and the support page's question
  glyphs, in English and Arabic in their own words; the story's moments
  play once as they come into view, or show how they end with Reduce
  Motion; and in Arabic the story and the glyphs read from the right, the
  keys ⌃⌥S still left to right;
- the terms and the withdrawal page: every footer, on every page and in
  every language, links to both in its own words (Terms and Withdrawal,
  AGB and Widerruf, الشروط and الانسحاب), right after Privacy, and both
  answer; the withdrawal page's two buttons lead to Apple, Withdraw from
  contract (`.btn.btn-primary`, reportaproblem.apple.com) and Cancel
  contracts here (`.btn-secondary`, the App Store's subscriptions), in
  each language's words, at least 48 px tall, filled, on the first screen
  and withdrawing at the reading start, in both looks; both pages link to
  Apple's terms in the reader's language, the standard EULA, the
  subscriptions and Apple's page on cancelling, number the same sections
  in every language, and the withdrawal page quotes the model form; the
  sitemap lists both in every language.

## Running them

```sh
cd site-tests
npm ci
npx playwright install chromium   # once per machine; not needed in a Claude Code cloud session
npm test
```

`@playwright/test` is pinned to 1.63.0, the version whose Chromium (build
1243) the Claude Code cloud container ships in `/opt/pw-browsers`, so there
it runs with no download. It needs Node 20 or later. When the container's
Chromium changes, the tests stop before they start, asking for a browser
that is not there: raise the pin to the Playwright version that matches
(`npm install --save-exact @playwright/test@<version>`), then check that
`npm ci` still installs it.

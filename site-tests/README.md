# Website tests

Browser tests for the website in `website/`, written with
[Playwright](https://playwright.dev). They are a tool for whoever changes
the site, not part of it: nothing here is built, published or loaded by a
visitor, and no workflow runs them.

They build the site, serve it on `http://127.0.0.1:4173/` with the Content
Security Policy from `vercel.json`, and check in Chromium, at desktop and
phone sizes:

- every page in English, German and Arabic loads without errors, in the
  right language and direction, with nothing from another host and no
  sideways scroll;
- the theme switcher: Original Sunset by default, each theme kept after a
  reload from the first paint, the arrows (in reading direction), another
  open tab following;
- the look switch: the airmail envelope by default; the classic Mac desktop
  and bold colour looks kept after a reload from the first paint and
  loading cleanly in every language, the themes still working in them, the
  bold look's band running; the arrows through all three;
- with Reduce Motion, the first view is all there at once, and in the bold
  look its band stands still.
- with a mouse, each look and brand chip takes a click 24 pt tall (the
  target reaches past its cell);
- after photos are sent into the chat, the page's ids are still unique.

## Running them

```sh
cd site-tests
npm ci
npx playwright install chromium   # once per machine; not needed in a Claude Code cloud session
npm test
```

`@playwright/test` is pinned to the version whose Chromium the Claude Code
cloud container ships in `/opt/pw-browsers`, so there it runs with no
download.

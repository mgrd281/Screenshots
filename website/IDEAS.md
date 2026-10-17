# Website: UX review and next features

Working notes for whoever changes `website/`. Never shipped: `build.py`
copies only the pages and `static/`.

## What was checked

The English, German and Arabic home pages, the privacy policy and the
support page, at 1440 px wide and at 390 px. Each section was looked at, and
these were measured in Chromium with Reduced Motion on:

- No console errors and no page errors, in any page, language or width.
- No sideways scroll.
- Every image has alt text, or is marked decorative.
- One `h1` per page. Each page has a meta description, an Open Graph image,
  a canonical link and four `hreflang` links.
- The English home page loads 552 KB in 7 requests (Arabic: 559 KB). No
  request is over 150 KB.

## Fixed in this pass

1. **Mouse targets for the look and brand chips.** The chips are 30 × 22 pt.
   WCAG 2.2 (2.5.8) asks for 24 pt. With a mouse, a pseudo-element now
   reaches a point past each edge, so the target is 24 pt tall. The cells
   keep their size and look. Touch already had a 44 pt target.
2. **Duplicate ids after sending photos.** Sending copies each picture into
   the chat, and the copy kept its gradient id, so the page held three
   elements with the id `sky-hero4`. A copy now renames its ids, and the
   `url(#…)` and `href="#…"` references that point at them. The copies still
   draw their gradients.
3. **Two new checks** in `site-tests`: the chip target with a mouse, and
   ids unique after photos are sent. The full suite passes: 81 tests, and
   the one mouse check is skipped on the phone project by design.

## Known, not changed yet

These need a decision first.

- **The phone menu bar hides Support** below 400 px, in every look. The
  footer keeps it, and the App Store support link points to the support
  page. Idea 6 would fix this.
- **The chat button's count** ("5") overlaps the newest thumbnail in the
  Arabic layout. It looks minor. Check it on a real Mac before changing it.

## Feature ideas

Each one says how to try it. Effort: S (about a day), M (a few days),
L (more). None adds a host, a font, a script, a cookie or an upload, so the
brief and the Content Security Policy still hold.

1. **Try it on your own screenshot** (M). Drop a picture on a demo line in
   the browser, drag boxes over what to hide, and copy the result. The
   picture never leaves the browser. *Try:* drop any PNG or JPG on the demo.
   *Limit:* nothing is read automatically, because text recognition needs a
   script the page cannot load. Hiding is by hand.
2. **What's new** (S). A short page with the latest releases, from a list in
   the repository that is updated with each release. Linked from the footer.
   *Try:* open `/whats-new/` and read the newest entry.
3. **Compare with the built-in screenshot tool** (S). A plain table of what
   Snapfly keeps on the line and what the macOS tool does with the file. Only
   facts that can be checked. *Try:* move through the rows with the keyboard.
4. **Keyboard shortcut sheet** (S). Press `?` for the shortcuts from the
   README's gesture table. *Try:* press `?` on the home page, then Escape.
5. **Press kit** (S). The icon in its sizes, each theme's colours, and the
   screenshots, in one zip, linked from the footer. The owner decides what
   goes in it. *Try:* download it from the footer.
6. **Phone menu** (M). On phones, one menu button holds Features, Privacy,
   Support, the look switch and the theme switch. The bar keeps the name and
   the button. This needs a design decision recorded in `DESIGN.md` first.
   *Try:* open the site at 390 px and tap the menu.
7. **Watch the film** (S, rights first). The 75-second German ad, with
   captions and a play button. The voice and music come from vidIQ: check
   that their licence covers a website before hosting the film, and keep the
   sound files out of the repository. *Try:* press play with the sound on.

## Rules for any new idea

- No outside host, font, script or cookie. The Content Security Policy in
  `vercel.json` would block them anyway.
- All three looks and all three themes must hold it. `site-tests` checks them.
- New words go in `content.py`, in English, German and Arabic.
- Anything that adds a size, colour or component goes in `DESIGN.md` in the
  same change.

## How to repeat the checks

`cd site-tests && npm test` runs the browser checks. The audit numbers above
came from a one-off run of the same steps: build the site, serve it with
`site-tests/serve.py`, then measure in the browser.

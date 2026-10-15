# Snapfly motion graphic

A 21-second vertical video (1080 × 1920, 30 fps) for TikTok, Instagram,
YouTube Shorts and the website, in English, German and Arabic. It has seven
scenes:

1. The icon takes off.
2. A Desktop fills with screenshots.
3. Snapfly sweeps them onto a line.
4. Private details are covered.
5. One click sends them all into the chat.
6. Holding a photo opens its menu, and a PDF is made.
7. The end card.

To make it:

```sh
python3 promo/build.py          # writes promo/promo-en.html, -de and -ar
node promo/render.js            # renders promo/out/Snapfly-en.mp4, -de and -ar
node promo/render.js de --stills 4.6,9.9,13.2   # a few frames as PNGs
```

`render.js` needs Playwright with its Chromium and ffmpeg. Set `PLAYWRIGHT`
to Playwright's folder and `CHROMIUM` to a Chromium binary if they are not
found on their own.

- **What drives it.** `promo.js` holds the whole timeline. `seek(t)` draws
  the frame at t seconds. Nothing animates on its own, so every render is
  the same.
- **What it reuses.**
  - The screenshots are the website's drawings (`website/build.py`).
  - The menu items and the tagline are the app's own words, from its
    `Localizable.strings`.
- **Safe area.** TikTok and Instagram draw buttons down the right side and
  a caption over the bottom. Text and buttons stay above y = 1500 and clear
  of the right 140 px from y = 850 down.
- **Fonts.** Inter and Noto Sans Arabic, from Google Fonts under the SIL
  Open Font License, are in `fonts/`.
- **Sound.** The video has none. Add music in the app it is posted to.

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

## The Instagram ad

A 21.5-second ad in German (1080 × 1920, 30 fps) with a voice, music and
small sound effects, made to bring in customers. A hook, then the answer,
one click into any chat, private details covered, and the offer:

1. "Schon wieder 30 Screenshots auf dem Desktop?" A Desktop fills up.
2. Snapfly arrives in the menu bar and every file flies onto the line; a
   close look at the top of the screen.
3. One click on a paper plane, and the screenshot lands in the chat:
   WhatsApp, ChatGPT, then any chat.
4. The name and the account number on an invoice light up, then are
   covered.
5. The end card: the icon, "Kostenlos für deinen Mac", the website.

```sh
python3 promo/build.py ad                                    # writes promo/ad-de.html
python3 promo/ad-sound.py voice.mp3 music.wav ad-sound.m4a   # effects, then the mix
node promo/render.js ad --audio ad-sound.m4a                 # renders promo/out/Snapfly-ad-de.mp4
node promo/render.js ad --stills 2.6,9.6,16.2                # a few frames as PNGs
```

- **Timing.** `ad.js` holds the timeline and the captions, each chunk at
  the moment the voice says it. `ad-sound.py` holds the same moments for
  the effects. The voice starts 0.2 s in (`VO` in both). A new voice
  needs new times in both.
- **Voice and music.** Made with vidIQ, which the owner chose and pays
  for: the voice "Sarah" reading the script below, and an instrumental
  track. They are not in the repository; pass them to `ad-sound.py`.
  The script: "Schon wieder dreißig Screenshots auf dem Desktop? Mit
  Snapfly hängt jeder Screenshot sofort an einer Leine, oben am
  Bildschirm. Ein Klick, und er ist im Chat. WhatsApp, ChatGPT, egal wo.
  Namen und Kontonummern? Werden automatisch verdeckt. Snapfly. Kostenlos
  für deinen Mac."
- **Sound.** The music steps back while the voice speaks and fades out
  on the end card; the effects (ticks, a chime, whooshes, clicks, a
  thunk) are drawn in code. The mix meets Instagram's −14 LUFS.
- **Safe area.** As above: words and buttons stay above y = 1500.

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
3. In WhatsApp, Lena asks for yesterday's invoice. One click on its paper
   plane, and the screenshot lands in her chat; the ticks turn blue, she
   types and thanks. Then a chart into ChatGPT, and three chats fan out,
   Claude among them: any chat.
4. The name and the account number on an invoice light up, then are
   covered.
5. The end card: the icon, "Kostenlos für deinen Mac", the website.

```sh
python3 promo/build.py ad                                    # writes promo/ad-de.html
python3 promo/ad-sound.py voice.mp3 music.wav ad-sound.m4a   # effects, then the mix
node promo/render.js ad --audio ad-sound.m4a                 # renders promo/out/Snapfly-ad-de.mp4
node promo/render.js ad --stills 2.6,9.6,16.2                # a few frames as PNGs
```

### The long cut

A 75-second version that explains more and ends on a high, with its own
voice and its own upbeat music. After the hook it asks "which one was it?"
while a pointer looks from file to file, and the line leaves the Desktop
clear. Then:

1. The screenshot button at the screen's edge: one click, a drag over an
   order, a flash, and the screenshot hangs on the line.
2. The paper plane sends the invoice to Lena in WhatsApp.
3. The button over the chat sends two photos into ChatGPT at once, and
   three chats fan out.
4. One click sends the invoice into a new e-mail to Lena.
5. The covering, after which the covered invoice is sent off.
6. Search: "Rechnung" is typed, and the screenshots that say it stay
   bright, marked where they say it.
7. Three screenshots are picked with ⌘ and become one PDF.
8. An English screenshot, Translate Text from its menu, and the words turn
   German where they stand.
9. One is sent and leaves the line, and the History still holds it for 30
   days.
10. No account, no cloud: everything stays on the Mac.
11. "Und das ist nicht alles!": tiles for Record Screen, Capture Whole
    Page, the time stamp and much more.
12. The end card, where "Entdecke viel mehr!" takes the tagline's place
    with a burst of confetti.

```sh
python3 promo/build.py ad-long                                            # writes promo/ad-long-de.html
python3 promo/ad-sound.py --long voice-long.mp3 music.wav ad-long-sound.m4a
node promo/render.js ad-long --audio ad-long-sound.m4a                    # renders promo/out/Snapfly-ad-long-de.mp4
```

Both cuts share `ad.js`. Each cut in its `CUTS` table has its captions and
the moments of each scene in its own voice; a scene a cut leaves out is not
built.

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
  für deinen Mac." The long cut's script: "Schon wieder 30 Screenshots auf
  dem Desktop? Und welcher war noch mal der richtige? Mit Snapfly hängt
  jeder Screenshot sofort an einer Leine, oben am Bildschirm. Dein Desktop
  bleibt aufgeräumt. Neuer Screenshot? Ein Klick auf den Knopf am
  Bildschirmrand. Fertig. Ein Klick auf den Papierflieger, und er ist im
  Chat. Noch schneller: Der Knopf über dem Chat schickt alle Fotos auf
  einmal. WhatsApp, ChatGPT, egal wo. Und per E-Mail? Genauso einfach.
  Namen und Kontonummern? Werden automatisch verdeckt, bevor etwas
  rausgeht. Du suchst eine alte Rechnung? Snapfly findet jedes Wort in
  deinen Screenshots. Mehrere Screenshots? Werden zu einem PDF. Fremde
  Sprache? Wird übersetzt, direkt auf deinem Mac. Was gesendet ist,
  verschwindet von der Leine. Der Verlauf hebt es 30 Tage auf. Kein Konto.
  Keine Cloud. Alles bleibt auf deinem Mac. Und das ist nicht alles:
  Bildschirm aufnehmen, ganze Seiten erfassen, Zeitstempel und vieles mehr.
  Snapfly. Kostenlos für deinen Mac. Hol es dir und entdecke viel mehr!"
  Its music is a separate upbeat track; pass it to `ad-sound.py --long`.
- **Sound.** The music steps back while the voice speaks and fades out
  on the end card; the effects (ticks, a chime, whooshes, clicks, a
  thunk) are drawn in code. The mix meets Instagram's −14 LUFS.
- **The chats.** Claude, WhatsApp and ChatGPT are drawn after their own
  layout and colours, never with their logos. WhatsApp looks like its Mac
  app, with a made-up chat list and conversation. The chats keep clear of
  the safe area's right side, and the end card says they
  are their owners' marks and Snapfly is not connected with them. Meta
  can refuse an ad that seems to speak for another company.
- **Safe area.** As above: words and buttons stay above y = 1500.

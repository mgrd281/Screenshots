#!/usr/bin/env python3
"""Writes the motion graphic's pages, promo-en.html, promo-de.html and
promo-ar.html, next to this file. render.js turns each into an MP4.

The screenshots in it are the website's drawings (website/build.py), and
the menu items and tagline are the app's own words (Localizable.strings),
so the video, the site and the app all say the same thing.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "website"))

from build import L, art  # noqa: E402  (the website's builder)
from content import TEXT as SITE  # noqa: E402

WORDS = {
    "en": dict(
        cap_problem="A Desktop full of screenshots?",
        cap_line="Snapfly hangs them on a line.",
        cap_private="Names and private details? Covered for you.",
        cap_send="All of them into WhatsApp or ChatGPT. One click.",
        cap_menu="Hold one for everything else.",
        file="Screenshot 2026-10-15 at 09.{n}.12",
        hide=None,
        send_all="Send all",
        chat_title="Chat",
        chat_in="Can you send me the invoices?",
        chat_reply="Got them all, thanks!",
        free="Free for Mac",
    ),
    "de": dict(
        cap_problem="Der Schreibtisch voller Bildschirmfotos?",
        cap_line="Snapfly hängt sie an eine Leine.",
        cap_private="Namen und private Daten? Automatisch verdeckt.",
        cap_send="Alle auf einmal in WhatsApp oder ChatGPT. Ein Klick.",
        cap_menu="Gedrückt halten für alles andere.",
        file="Bildschirmfoto 2026-10-15 um 09.{n}.12",
        hide=None,
        send_all="Alle senden",
        chat_title="Chat",
        chat_in="Kannst du mir die Rechnungen schicken?",
        chat_reply="Alle angekommen, danke!",
        free="Kostenlos für Mac",
    ),
    "ar": dict(
        cap_problem="سطح المكتب مليء بلقطات الشاشة؟",
        cap_line="Snapfly يعلّقها على حبل.",
        cap_private="الأسماء والمعلومات الخاصة؟ تُغطّى تلقائيًا.",
        cap_send="كلها إلى WhatsApp أو ChatGPT. بنقرة واحدة.",
        cap_menu="اضغط مطوّلًا لكل الباقي.",
        file="لقطة شاشة 2026-10-15 في 9.{n}.12",
        hide=None,
        send_all="إرسال الكل",
        chat_title="دردشة",
        chat_in="ممكن ترسل لي الفواتير؟",
        chat_reply="وصلت كلها، شكرًا!",
        free="مجاني لجهاز Mac",
    ),
}

MENU = ["Copy", "Copy Text", "Paste into %@", "Make PDF", "Combine into one image", "-",
        "Translate Text", "Describe", "-", "Markup", "Hide Part…"]
KINDS = ["invoice", "map", "chart", "calendar", "sunset"]


def page(lang):
    words = dict(WORDS[lang])
    words["hide"] = L(lang, "Hide private details")
    words["tagline"] = L(lang, "Screenshots, one click from any chat.")
    chat = SITE[lang]["chat_app"]
    words["menu"] = [item if item == "-" else L(lang, item).replace("%@", chat) for item in MENU]
    words["menuPdfIndex"] = [m for m in MENU if m != "-"].index("Make PDF")
    data = {
        "lang": lang,
        "dir": SITE[lang]["dir"],
        "text": words,
        "invoice": SITE[lang]["inv"],
        "art": [art(k, lang, f"p{i}") for i, k in enumerate(KINDS)],
        "artByKind": {k: art(k, lang, f"k{k}") for k in KINDS},
        "icon": "../assets/icon.png",
    }
    template = (HERE / "promo.template.html").read_text(encoding="utf-8")
    html = template.replace("/*DATA*/null", json.dumps(data, ensure_ascii=False))
    (HERE / f"promo-{lang}.html").write_text(html, encoding="utf-8")


# The Instagram ad, in German only (ad.js holds its timeline). Its voice
# says these words; the captions in ad.js follow them.
AD = {
    "de": dict(
        file="Bildschirmfoto 2026-10-15 um 09.{n}.12",
        apps=dict(
            claude=dict(ask="Wann habe ich diese Woche noch Zeit?",
                        reply="Am 14. vormittags ist noch alles frei.",
                        field="Antworten …"),
            # WhatsApp is a whole conversation: Lena asks for the invoice,
            # gets the screenshot and thanks. The chat list is made up.
            whatsapp=dict(title="Chats", search="Suchen", day="Heute", status="online", typing="schreibt …",
                          ask="Hey! Hast du die Rechnung von gestern? 🙂", wait="Moment, schick ich dir gleich",
                          reply="Perfekt, danke! 🙏", field="Nachricht eingeben",
                          chats=[dict(name="Lena", initial="L", color="#E9A178", last="Moment, schick ich dir gleich", time="09:39"),
                                 dict(name="Familie", initial="F", color="#7FB8A4", last="Mama: Essen um sieben?", time="08:57"),
                                 dict(name="Büro", initial="B", color="#8EA3D6", last="Tom: Meeting verschoben", time="Gestern"),
                                 dict(name="Max", initial="M", color="#C495C9", last="Bis Samstag! 👋", time="Gestern")]),
            chatgpt=dict(ask="Was zeigt dieses Diagramm?",
                         reply="Die Balken steigen Monat für Monat: Der Umsatz wächst stetig.",
                         field="Frag irgendwas"),
        ),
        free="Kostenlos für deinen Mac",
        legal="WhatsApp, ChatGPT und Claude sind Marken ihrer Inhaber. Snapfly ist mit ihnen nicht verbunden.",
    ),
}


def ad(lang):
    words = dict(AD[lang])
    words["tagline"] = L(lang, "Screenshots, one click from any chat.")
    data = {
        "lang": lang,
        "text": words,
        "invoice": SITE[lang]["inv"],
        "art": [art(k, lang, f"a{i}") for i, k in enumerate(KINDS)],
        "artByKind": {k: art(k, lang, f"ak{k}") for k in KINDS},
        "icon": "../assets/icon.png",
        "url": "mgrd281.github.io/Screenshots",
    }
    template = (HERE / "ad.template.html").read_text(encoding="utf-8")
    html = template.replace("/*DATA*/null", json.dumps(data, ensure_ascii=False))
    (HERE / f"ad-{lang}.html").write_text(html, encoding="utf-8")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["ad"]:
        for lang in (args[1:] or ["de"]):
            ad(lang)
            print(f"Wrote promo/ad-{lang}.html")
        sys.exit()
    for lang in (args or ["en", "de", "ar"]):
        page(lang)
        print(f"Wrote promo/promo-{lang}.html")

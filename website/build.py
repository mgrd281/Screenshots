#!/usr/bin/env python3
"""Builds the Snapfly website into website/_site, for GitHub Pages.

Run it with no arguments:

    python3 website/build.py

Only the Python standard library is used. The words live in content.py;
labels the app itself shows come from its Localizable.strings, so the site
and the app always agree.
"""
import base64
import hashlib
import html
import json
import re
import shutil
import sys
from pathlib import Path
from urllib.parse import quote, urlparse

from content import DOWNLOAD, EMAIL, LANGS, MAKER, REPO, SITE_URL, TEXT

HERE = Path(__file__).resolve().parent
OUT = HERE / "_site"

# The English home page's one inline script. vercel.json's Content Security
# Policy allows it by its hash, and nothing from another host, which also
# keeps Vercel's toolbar off the preview pages.
REDIRECT_JS = ('try{if(!localStorage.getItem("snapfly-lang")){var l=(navigator.language||"").toLowerCase();'
               'if(l.indexOf("de")==0)location.replace("de/");else if(l.indexOf("ar")==0)location.replace("ar/")}}catch(e){}')
# Every page's first script: the brand theme chosen on this device, set
# before the page paints, and the mark that scripts run.
BRAND_JS = ('try{if(localStorage.getItem("snapfly-brand")==="emerald")'
            'document.documentElement.setAttribute("data-brand","emerald")}catch(e){}'
            'document.documentElement.classList.add("js")')
INLINE_JS = (BRAND_JS, REDIRECT_JS)
STATIC = HERE / "static"
STRINGS = HERE.parent / "Sources" / "Tendedero" / "Resources"
BASE_PATH = urlparse(SITE_URL).path  # "/Screenshots/"


# MARK: The app's own words

def load_strings(lang):
    text = (STRINGS / f"{lang}.lproj" / "Localizable.strings").read_text(encoding="utf-8")
    pairs = re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', text, re.M)
    unescape = lambda s: s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
    return {unescape(k): unescape(v) for k, v in pairs}


APP = {code: load_strings(code) for code, _, _ in LANGS}


def L(lang, key):
    """A label exactly as the app shows it."""
    return APP[lang][key]


def esc(text):
    return html.escape(text, quote=True)


# MARK: Icons, drawn for the site in one stroke weight

def icon(name, cls="icon"):
    return f'<svg class="{cls}" viewBox="0 0 24 24" aria-hidden="true" focusable="false">{ICONS[name]}</svg>'


ICONS = {
        "plane": '<path d="M4.1 11.3 19.6 4.6c.6-.3 1.1.3.9.9l-6.7 15.5c-.3.6-1.1.5-1.3-.1l-2-5.7a1 1 0 0 0-.6-.6L4.2 12.6c-.6-.2-.7-1-.1-1.3Z" fill="currentColor"/><path d="m10.4 13.6 9.4-8.8" stroke="var(--plane-crease, rgba(255,255,255,.55))" stroke-width="1.4" stroke-linecap="round" fill="none"/>',
        "mac": '<path d="M6 4h12a2.5 2.5 0 0 1 2.5 2.5V16h-17V6.5A2.5 2.5 0 0 1 6 4Zm.4 2.4v7.2h11.2V6.4Z" fill="currentColor" fill-rule="evenodd"/><path d="M1 17h22v.7a2.3 2.3 0 0 1-2.3 2.3H3.3A2.3 2.3 0 0 1 1 17.7Z" fill="currentColor"/>',
        "xmark": '<path d="m7 7 10 10M17 7 7 17" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" fill="none"/>',
        "lock": '<rect x="5.5" y="10.5" width="13" height="9.5" rx="2.4" fill="currentColor"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5" stroke="currentColor" stroke-width="2" fill="none"/>',
        "check": '<path d="m6 12.5 4 4 8-9" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
        "download": '<path d="M12 4v10.5M7.5 10.5 12 15l4.5-4.5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/><path d="M5 16.5v1.5A2 2 0 0 0 7 20h10a2 2 0 0 0 2-2v-1.5" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>',
        "mail": '<rect x="3.5" y="6" width="17" height="12.5" rx="2.5" stroke="currentColor" stroke-width="1.9" fill="none"/><path d="m4.5 7.5 7.5 6 7.5-6" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round" fill="none"/>',
        "chevron": '<path d="m9.5 6.5 5.5 5.5-5.5 5.5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
        "globe": '<circle cx="12" cy="12" r="8" stroke="currentColor" stroke-width="1.7" fill="none"/><path d="M4 12h16M12 4c2.4 2.3 3.5 5 3.5 8s-1.1 5.7-3.5 8c-2.4-2.3-3.5-5-3.5-8S9.6 6.3 12 4Z" stroke="currentColor" stroke-width="1.7" fill="none"/>',
        "arrow": '<path d="M5 12h13M13 6.5 18.5 12 13 17.5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
        "replay": '<path d="M5.5 12a6.5 6.5 0 1 0 2-4.7" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/><path d="M6.8 3.8v3.9h3.9" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
        "gear": '<circle cx="12" cy="12" r="3.2" stroke="currentColor" stroke-width="1.8" fill="none"/><path d="M12 3.5v2.2M12 18.3v2.2M3.5 12h2.2M18.3 12h2.2M6 6l1.6 1.6M16.4 16.4 18 18M6 18l1.6-1.6M16.4 7.6 18 6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
        "shirt": '<path d="M8.5 4.5 4 7l1.8 4 2.2-1v9.5h8V10l2.2 1L20 7l-4.5-2.5a3.5 3.5 0 0 1-7 0Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" fill="none"/>',
        "hand": '<path d="M8.5 12V6.2a1.3 1.3 0 0 1 2.6 0V11m0-6.2a1.3 1.3 0 0 1 2.6 0V11m0-5a1.3 1.3 0 0 1 2.6 0V12m0-3.5a1.3 1.3 0 0 1 2.6 0v5.5a6.5 6.5 0 0 1-6.5 6.5h-.6a6 6 0 0 1-4.7-2.3L4.6 14.4a1.4 1.4 0 0 1 2.1-1.8l1.8 1.6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
        "info": '<circle cx="12" cy="12" r="8.3" stroke="currentColor" stroke-width="1.7" fill="none"/><path d="M12 11v5.5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="7.8" r="1.2" fill="currentColor"/>',
        "pointer": '<path d="M5 3.2v15.6l4.1-3.7 2.6 6 2.7-1.2-2.6-5.9 5.6-.3Z" fill="#000" stroke="#fff" stroke-width="1.3" stroke-linejoin="round"/>',
        # camera.viewfinder, the screenshot button's glyph.
        "viewfinder": '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8V5.5A2.5 2.5 0 0 1 5.5 3H8M16 3h2.5A2.5 2.5 0 0 1 21 5.5V8M21 16v2.5a2.5 2.5 0 0 1-2.5 2.5H16M8 21H5.5A2.5 2.5 0 0 1 3 18.5V16"/><rect x="7" y="9" width="10" height="7.5" rx="1.6"/><path d="m10 9 .8-1.6h2.4L14 9"/><circle cx="12" cy="12.8" r="2"/></g>',
        "sparkles": '<g fill="currentColor"><path d="M10 3.5c.7 3.7 2.6 5.6 6.3 6.3-3.7.7-5.6 2.6-6.3 6.3-.7-3.7-2.6-5.6-6.3-6.3 3.7-.7 5.6-2.6 6.3-6.3Z"/><path d="M18.2 13.6c.35 1.9 1.3 2.85 3.2 3.2-1.9.35-2.85 1.3-3.2 3.2-.35-1.9-1.3-2.85-3.2-3.2 1.9-.35 2.85-1.3 3.2-3.2Z"/><path d="M18 2.5c.25 1.3.9 1.95 2.2 2.2-1.3.25-1.95.9-2.2 2.2-.25-1.3-.9-1.95-2.2-2.2 1.3-.25 1.95-.9 2.2-2.2Z"/></g>',
        "timer": '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="13.5" r="7.5"/><path d="M12 13.5V9.5M10 3h4M18.4 7.1l1.4-1.4"/></g>',
        "stop": '<rect x="6.5" y="6.5" width="11" height="11" rx="2.2" fill="currentColor"/>',
        "play": '<path d="M8 5.6v12.8c0 .8.9 1.3 1.6.9l10-6.4c.6-.4.6-1.4 0-1.8l-10-6.4c-.7-.4-1.6.1-1.6.9Z" fill="currentColor"/>',
        "eye": '<g fill="none" stroke="currentColor" stroke-width="1.9"><path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z" stroke-linejoin="round"/><circle cx="12" cy="12" r="3"/></g>',
}


# MARK: The screenshots that hang on the line, drawn as illustrations

class Art:
    """Draws one illustration, mirrored for right-to-left pages."""

    def __init__(self, lang, uid):
        self.lang, self.uid = lang, uid
        self.rtl = TEXT[lang]["dir"] == "rtl"

    def x(self, x, w=300):
        return w - x if self.rtl else x

    def anchor(self, a):
        # With direction="rtl" on the drawing, start and end already follow
        # the reading direction; only the positions are mirrored.
        return a

    def text(self, x, y, s, size, weight=400, fill="#1d1d1f", anchor="start", cls=""):
        c = f' class="{cls}"' if cls else ""
        return (f'<text x="{self.x(x)}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{fill}" '
                f'text-anchor="{self.anchor(anchor)}"{c}>{esc(s)}</text>')

    def rect(self, x, y, w, h, fill, rx=0, cls=""):
        c = f' class="{cls}"' if cls else ""
        rx_ = f' rx="{rx}"' if rx else ""
        return f'<rect x="{self.x(x + w) if self.rtl else x}" y="{y}" width="{w}" height="{h}"{rx_} fill="{fill}"{c}/>'


def svg_open(lang):
    d = ' direction="rtl"' if TEXT[lang]["dir"] == "rtl" else ""
    return (f'<svg viewBox="0 0 300 200" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" focusable="false" '
            f'font-family="-apple-system, BlinkMacSystemFont, system-ui, sans-serif"{d}>')


def window_bar(a, fill="#F2F2F4", dark=False):
    out = [f'<rect width="300" height="26" fill="{fill}"/>']
    for i, c in enumerate(["#FF5F57", "#FEBC2E", "#28C840"]):
        out.append(f'<circle cx="{a.x(14 + i * 13)}" cy="13" r="4.2" fill="{c}"/>')
    return "".join(out)


def art_invoice(lang, uid, covered=True):
    a, t = Art(lang, uid), TEXT[lang]["inv"]
    ink = "#1F1F1F"
    parts = [svg_open(lang), '<rect width="300" height="200" fill="#fff"/>', window_bar(a)]
    parts.append(a.text(18, 52, t["title"], 14, 700))
    parts.append(a.text(18, 66, t["date"], 8.5, 400, "#6e6e73"))
    parts.append(a.text(282, 52, t["total_v"], 14, 700, "#1d1d1f", "end"))
    parts.append(a.text(282, 66, t["total"], 8.5, 400, "#6e6e73", "end"))
    parts.append(a.text(18, 84, t["bill"], 8, 600, "#6e6e73"))
    # The name, the street and the email: covered, as Snapfly covers them.
    if covered:
        parts.append(a.rect(17, 89, 70, 11, ink, 2.5))
        parts.append(a.rect(17, 103, 86, 11, ink, 2.5))
        parts.append(a.rect(17, 117, 118, 11, ink, 2.5))
    else:
        parts.append(a.text(18, 98, t["name"], 9))
        parts.append(a.text(18, 112, t["street"], 9))
        parts.append(a.text(18, 126, t["email"], 9))
    parts.append(f'<line x1="{a.x(18)}" y1="138" x2="{a.x(282)}" y2="138" stroke="#e5e5ea"/>')
    # The items sit on the far side, so the lock badge in the near bottom
    # corner covers nothing.
    for i, (item, price) in enumerate(t["items"]):
        y = 154 + i * 14
        parts.append(a.text(150, y, item, 9))
        parts.append(a.text(282, y, price, 9, 400, "#1d1d1f", "end"))
    parts.append("</svg>")
    return "".join(parts)


def art_map(lang, uid):
    # A map reads the same in either direction, so it is never mirrored.
    return (svg_open(lang) +
            '<rect width="300" height="200" fill="#ECEFE6"/>'
            '<path d="M0 132c40-10 70 6 104-4s58-38 98-34 66 26 98 18v88H0Z" fill="#CFE3C4"/>'
            '<path d="M196 0c-6 30 10 52 40 62s52 30 64 58V0Z" fill="#BCD9EE"/>'
            '<path d="M-5 70h310M-5 150h310M70-5v210M178-5v210M250-5v210" stroke="#fff" stroke-width="9"/>'
            '<path d="M120 -5 40 205" stroke="#fff" stroke-width="6"/>'
            '<path d="M70 168V150h108V70h72V44" stroke="#0A84FF" stroke-width="5.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
            '<circle cx="70" cy="168" r="6.5" fill="#fff" stroke="#0A84FF" stroke-width="3"/>'
            '<path d="M250 44c0-9-7-15-14-15s-14 6-14 15c0 10 14 22 14 22s14-12 14-22Z" transform="translate(14 -10)" fill="#FF453A"/>'
            '<circle cx="250" cy="34" r="4.6" fill="#fff"/>'
            '<rect x="88" y="98" width="62" height="24" rx="12" fill="#fff"/>'
            '<text x="119" y="114" font-size="10" font-weight="700" text-anchor="middle" direction="ltr" unicode-bidi="embed" fill="#1d1d1f">12 min</text>'
            '</svg>')


def art_chart(lang, uid):
    a = Art(lang, uid)
    bars = [46, 70, 54, 96, 78, 124, 104]
    out = [svg_open(lang), '<rect width="300" height="200" fill="#1B1B22"/>']
    out.append(f'<rect x="{a.x(22 + 84) if a.rtl else 22}" y="22" width="84" height="9" rx="4.5" fill="#55556a"/>')
    out.append(f'<rect x="{a.x(22 + 48) if a.rtl else 22}" y="38" width="48" height="7" rx="3.5" fill="#3a3a48"/>')
    for i, h in enumerate(bars):
        x = 26 + i * 37
        fill = "#7C8CFF" if i == 5 else "#3F4A9E"
        out.append(f'<rect x="{a.x(x + 22) if a.rtl else x}" y="{176 - h}" width="22" height="{h}" rx="4" fill="{fill}"/>')
    out.append('<line x1="18" y1="178" x2="282" y2="178" stroke="#3a3a48" stroke-width="1.5"/>')
    out.append("</svg>")
    return "".join(out)


def art_calendar(lang, uid):
    a = Art(lang, uid)
    out = [svg_open(lang), '<rect width="300" height="200" fill="#fff"/>', window_bar(a)]
    days = ["13", "14", "15", "16", "17"]
    for i, d in enumerate(days):
        x = 42 + i * 52
        today = d == "15"
        if today:
            out.append(f'<circle cx="{a.x(x)}" cy="44" r="10" fill="#FF3B30"/>')
        out.append(f'<text x="{a.x(x)}" y="48" font-size="11" font-weight="700" text-anchor="middle" fill="{"#fff" if today else "#1d1d1f"}">{d}</text>')
        if i:
            out.append(f'<line x1="{a.x(16 + i * 52)}" y1="60" x2="{a.x(16 + i * 52)}" y2="200" stroke="#eeeef0"/>')
    for y in (90, 120, 150, 180):
        out.append(f'<line x1="0" y1="{y}" x2="300" y2="{y}" stroke="#f2f2f4"/>')
    events = [(0, 66, 40, "#DCEBFF", "#2F6FD6"), (1, 96, 56, "#FFE3CC", "#C8611A"), (2, 70, 30, "#E6DCFF", "#6B45C8"),
              (2, 124, 44, "#D8F3E0", "#2B8A4B"), (3, 84, 70, "#DCEBFF", "#2F6FD6"), (4, 64, 34, "#FFDDE3", "#C2364F"),
              (4, 140, 40, "#E6DCFF", "#6B45C8")]
    for col, y, h, bg, fg in events:
        x = 20 + col * 52
        out.append(a.rect(x, y, 46, h, bg, 5))
        out.append(a.rect(x + 6, y + 7, 28, 5, fg, 2.5))
        out.append(a.rect(x + 6, y + 16, 18, 4, fg + "88", 2))
    out.append("</svg>")
    return "".join(out)


def art_sunset(lang, uid):
    g = f"sky-{uid}"
    return (svg_open(lang) +
            f'<defs><linearGradient id="{g}" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#6E47D6"/><stop offset=".55" stop-color="#FF6D8A"/><stop offset="1" stop-color="#FFB26B"/>'
            '</linearGradient></defs>'
            f'<rect width="300" height="200" fill="url(#{g})"/>'
            '<circle cx="150" cy="118" r="30" fill="#FFE4A1"/>'
            '<path d="M0 132c46-18 92-20 150-4s106 14 150-4v76H0Z" fill="#5A2F8C"/>'
            '<path d="M0 160c60-16 120-12 170 2s92 10 130-2v40H0Z" fill="#33195E"/>'
            '</svg>')


ART = {
    "invoice": art_invoice,
    "map": art_map,
    "chart": art_chart,
    "calendar": art_calendar,
    "sunset": art_sunset,
}
CARDS = ["invoice", "map", "chart", "calendar", "sunset"]
TILTS = ["-3deg", "2.2deg", "-1.4deg", "3deg", "-2.2deg"]


def art(kind, lang, uid):
    return ART[kind](lang, uid)


# MARK: Pieces of every page

def prefix(lang):
    return "" if lang == "en" else "../"


def lang_dir(lang):
    return dict((c, d) for c, d, _ in LANGS)[lang]


def href_to(from_lang, to_lang, page):
    """A relative link from a page in one language to a page in another."""
    target = lang_dir(to_lang) + ("" if page == "index" else f"{page}.html")
    if from_lang == to_lang:
        return "./" if page == "index" else f"{page}.html"
    return prefix(from_lang) + (target or "./")


def menubar(lang, page):
    t = TEXT[lang]
    here = lambda p: ' aria-current="page"' if p == page else ""
    home = href_to(lang, lang, "index")
    features = "#features" if page == "index" else f"{home}#features"
    mark = lambda code: ' aria-current="true"' if code == lang else ""
    langs = "".join(
        f'<li><a href="{href_to(lang, code, page)}" hreflang="{code}" lang="{code}" data-lang="{code}"'
        f'{mark(code)}>{icon("check", "icon tick")}{esc(name)}</a></li>'
        for code, _, name in LANGS)
    current = dict((c, n) for c, _, n in LANGS)[lang]
    # The brand theme, as two swatches; site.js keeps the checked one in
    # step with <html data-brand>.
    brands = "".join(
        f'<button type="button" class="brand-chip" role="radio" aria-checked="{str(key == "sunset").lower()}"'
        f' tabindex="{0 if key == "sunset" else -1}" data-brand-pick="{key}" aria-label="{esc(t["brand_" + key])}"'
        f' data-tip="{esc(t["brand_" + key])}"><span class="brand-dot brand-dot-{key}"></span></button>'
        for key in ("sunset", "emerald"))
    return f"""<header class="menubar">
  <nav class="menubar-row" aria-label="Snapfly">
    <a class="app-menu" href="{home}"><img src="{prefix(lang)}assets/icon-64.png" alt="" width="18" height="18"><span>Snapfly</span></a>
    <ul class="menus">
      <li class="wide-only"><a href="{features}">{esc(t["nav_features"])}</a></li>
      <li><a href="{href_to(lang, lang, "privacy")}"{here("privacy")}>{esc(t["nav_privacy"])}</a></li>
      <li><a href="{href_to(lang, lang, "support")}"{here("support")}>{esc(t["nav_support"])}</a></li>
    </ul>
    <div class="status">
      <div class="brand-switch" role="radiogroup" aria-label="{esc(t["brand_label"])}"><span class="brand-thumb" aria-hidden="true"></span>{brands}</div>
      <details class="lang-menu">
        <summary aria-label="{esc(t["lang_label"])}: {esc(current)}">{icon("globe")}<span class="lang-current">{esc(current)}</span></summary>
        <ul class="menu-panel">{langs}</ul>
      </details>
      <time class="clock" aria-hidden="true"></time>
    </div>
  </nav>
</header>"""


def footer(lang, page):
    t = TEXT[lang]
    home = href_to(lang, lang, "index")
    features = "#features" if page == "index" else f"{home}#features"
    mark = lambda code: ' aria-current="true"' if code == lang else ""
    langs = " ".join(
        f'<a href="{href_to(lang, code, page)}" hreflang="{code}" lang="{code}" data-lang="{code}"'
        f'{mark(code)}>{esc(name)}</a>'
        for code, _, name in LANGS)
    return f"""<footer class="footer">
  <div class="wrap footer-grid">
    <div class="footer-brand">
      <img src="{prefix(lang)}assets/icon-64.png" alt="" width="32" height="32">
      <p><strong>Snapfly</strong><br><span class="muted">{esc(L(lang, "Screenshots, one click from any chat."))}</span></p>
    </div>
    <ul class="footer-links">
      <li><a href="{features}">{esc(t["nav_features"])}</a></li>
      <li><a href="{href_to(lang, lang, "privacy")}">{esc(t["nav_privacy"])}</a></li>
      <li><a href="{href_to(lang, lang, "support")}">{esc(t["nav_support"])}</a></li>
      <li><a href="{REPO}">{esc(t["footer_source"])}</a></li>
      <li><a href="mailto:{EMAIL}">{esc(t["footer_contact"])}</a></li>
    </ul>
    <p class="footer-langs">{langs}</p>
    <p class="fine">{esc(t["footer_made"])} {esc(t["footer_based"])} {esc(t["footer_tm"])}</p>
  </div>
</footer>"""


def head(lang, page, title, desc):
    t = TEXT[lang]
    path = lang_dir(lang) + ("" if page == "index" else f"{page}.html")
    alternates = "\n".join(
        f'<link rel="alternate" hreflang="{code}" href="{SITE_URL}{d}{"" if page == "index" else page + ".html"}">'
        for code, d, _ in LANGS)
    default = f'<link rel="alternate" hreflang="x-default" href="{SITE_URL}{"" if page == "index" else page + ".html"}">'
    # The home page in English sends a German or Arabic browser to its own
    # language once, until the visitor picks one.
    redirect = ""
    if lang == "en" and page == "index":
        redirect = f"<script>{REDIRECT_JS}</script>"
    p = prefix(lang)
    return f"""<!doctype html>
<html lang="{lang}" dir="{t["dir"]}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{esc(title)}</title>
<meta name="description" content="{esc(desc)}">
<meta name="color-scheme" content="light dark">
<meta name="theme-color" content="#F5F5F7" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#161618" media="(prefers-color-scheme: dark)">
<link rel="canonical" href="{SITE_URL}{path}">
{alternates}
{default}
<link rel="icon" href="{p}assets/favicon.png" type="image/png">
<link rel="apple-touch-icon" href="{p}assets/icon-180.png">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Snapfly">
<meta property="og:title" content="{esc(title)}">
<meta property="og:description" content="{esc(desc)}">
<meta property="og:url" content="{SITE_URL}{path}">
<meta property="og:image" content="{SITE_URL}assets/og.png">
<meta property="og:locale" content="{ {"en": "en_US", "de": "de_DE", "ar": "ar_AR"}[lang] }">
<meta name="twitter:card" content="summary_large_image">
<script>{BRAND_JS}</script>
{redirect}
<link rel="stylesheet" href="{p}assets/site.css">
<script src="{p}assets/site.js" defer></script>
</head>"""


def document(lang, page, title, desc, main):
    t = TEXT[lang]
    return f"""{head(lang, page, title, desc)}
<body class="page-{page}">
<a class="skip" href="#main">{esc(t["skip"])}</a>
{menubar(lang, page)}
<main id="main">
{main}
</main>
{footer(lang, page)}
</body>
</html>
"""


def download_button(lang):
    """The download link as a badge, like the stores' own: two lines beside a Mac."""
    t = TEXT[lang]
    return (f'<a class="badge-get" href="{DOWNLOAD}">{icon("mac")}<span class="badge-text">'
            f'<small>{esc(t["badge_for"])}</small> <span>macOS</span></span></a>')


# MARK: The home page

ROPE = '<svg class="rope{cls}" viewBox="0 0 1000 100" preserveAspectRatio="none" aria-hidden="true" focusable="false"><path d="M-20 14 Q500 86 1020 14"/></svg>'


def rope(cls=""):
    return ROPE.replace("{cls}", f" {cls}" if cls else "")


def hero(lang):
    t = TEXT[lang]
    copy_word, discard = L(lang, "Copy"), L(lang, "Discard")
    pegs = []
    for i, kind in enumerate(CARDS):
        name = t["card_names"][i]
        lock = f'<span class="badge-lock" aria-hidden="true">{icon("lock")}</span>' if kind == "invoice" else ""
        pegs.append(f"""<li class="peg" data-kind="{kind}" style="--t:{(i + 0.5) / len(CARDS):.4f};--tilt:{TILTS[i]};--i:{i}">
  <span class="clip" aria-hidden="true"></span>
  <div class="photo">
    <button class="photo-hit" type="button" aria-label="{esc(copy_word)}: {esc(name)}" aria-keyshortcuts="Alt+ArrowLeft Alt+ArrowRight"><span class="photo-img">{art(kind, lang, f"hero{i}")}</span></button>
    {lock}
    <button class="corner corner-x" type="button" aria-label="{esc(discard)}: {esc(name)}">{icon("xmark")}</button>
    <button class="corner corner-send" type="button" aria-label="{esc(t["send_label"])}: {esc(name)}">{icon("plane")}</button>
  </div>
  <span class="copied" aria-hidden="true">{icon("check")}{esc(L(lang, "Copied"))}</span>
</li>""")
    return f"""<section class="hero intro" aria-labelledby="hero-title">
  <div class="line" data-line data-earlier="{esc(L(lang, "Move Earlier"))}" data-later="{esc(L(lang, "Move Later"))}">
    {rope()}
    <ul class="pegs" aria-label="{esc(t["line_label"])}">
      {"".join(pegs)}
    </ul>
    <div class="line-tag">
      <span class="clip" aria-hidden="true"></span>
      <button class="tag-send" type="button" data-send-all aria-label="{esc(t["send_all_label"])}">{icon("plane")}</button>
      <span class="tag-label" aria-hidden="true">{esc(t["send_all"])}</span>
    </div>
    <p class="vh" role="status" aria-live="polite" data-status data-sent="{esc(t["send_label"])}"></p>
  </div>
  <div class="hero-body">
    <div class="hero-copy">
      <h1 id="hero-title">{esc(L(lang, "Screenshots, one click from any chat."))}</h1>
      <p class="hero-sub">{esc(t["hero_sub"])}</p>
      <p class="hero-actions">{download_button(lang)}</p>
      <p class="hero-note">{esc(t["cta_note"])}</p>
    </div>
    <section class="window chat" aria-label="{esc(t["chat_label"])}" data-chat>
      <div class="titlebar"><span class="lights" aria-hidden="true"><i></i><i></i><i></i></span><span class="window-title">{esc(t["chat_title"])}</span></div>
      <ol class="thread" data-thread>
        <li class="note">{esc(t["try_hint"])}</li>
        <li class="msg in"><p>{esc(t["chat_in"])}</p></li>
      </ol>
      <div class="composer" aria-hidden="true"><span class="field">{esc(t["chat_placeholder"])}</span><span class="composer-send">{icon("plane")}</span></div>
      <button class="chat-btn" type="button" data-chat-btn aria-label="{esc(t["chatbtn_label"])}" aria-description="{esc(t["chatbtn_hold"])}" title="{esc(t["chatbtn_hold"])}">
        <span class="cb-thumbs" aria-hidden="true"><span class="cb-thumb"></span><span class="cb-thumb"></span></span>
        <span class="cb-count" aria-hidden="true"></span>
        <span class="cb-send" aria-hidden="true">{icon("plane")}{icon("check", "icon done")}</span>
      </button>
      <form class="caption-bar" data-caption hidden>
        <input class="caption-field" type="text" placeholder="{esc(L(lang, "Add a message…"))}" aria-label="{esc(L(lang, "Add a message…"))}" autocomplete="off" enterkeyhint="send">
        <span class="caption-count" data-format="{esc(L(lang, "%d photos"))}"></span>
        <button type="submit" class="caption-send" aria-label="{esc(L(lang, "Send"))}" title="{esc(L(lang, "Send"))}">{icon("plane")}</button>
      </form>
      <ul class="ctx-menu chat-menu" role="menu" hidden>
        <li role="none"><button type="button" role="menuitem" class="ctx-item" data-act="caption"><span>{esc(L(lang, "Send with a Message…"))}</span></button></li>
      </ul>
      <template data-reply><li class="msg in"><p>{esc(t["chat_reply"])}</p></li></template>
      <template data-reply-all><li class="msg in"><p>{esc(t["chat_reply_all"])}</p></li></template>
      <template data-reply-caption><li class="msg in"><p>{esc(t["caption_reply"])}</p></li></template>
    </section>
  </div>
</section>"""


def section_send(lang):
    t = TEXT[lang]
    caps = [("⌃", t["keys"][0]), ("⌥", t["keys"][1]), ("V", t["keys"][2])]
    keys = "".join(f'<span class="keycap"><span class="keycap-glyph">{esc(g)}</span><span class="keycap-word">{esc(w)}</span></span>' for g, w in caps)
    return f"""<section class="section send" id="features" aria-labelledby="send-h">
  <div class="wrap split">
    <div class="copy">
      <h2 id="send-h">{esc(t["send_h"])}</h2>
      <p>{t["send_p"]}</p>
    </div>
    <div class="keys" dir="ltr" role="img" aria-label="{esc(t["keys_label"])}">{keys}</div>
  </div>
</section>"""


# MARK: A Mac desktop to try Snapfly on

# One desktop in three layouts, each drawn at its own size in CSS pixels and
# scaled as a whole to fit its column: wide from 1280 px, medium from 768 px,
# tall below. The browser sits in the middle of each, the same size on wide
# and medium, so on medium it fills more of the screen.
DESK = {
    "wide": dict(w=1280, h=800, win=(304, 156, 672, 396), icon=48, card=160, cards=4, shot=(1244, 304), compact=False),
    "medium": dict(w=1024, h=720, win=(152, 148, 720, 396), icon=40, card=144, cards=4, shot=(988, 276), compact=False),
    "tall": dict(w=360, h=572, win=(8, 148, 344, 412), icon=48, card=96, cards=3, shot=(324, 244), compact=True),
}
MENU_BAR = 28

# The Dock's icons share one 64-point grid: a rounded square, a gradient lit
# from the top, a white or grey glyph with a one-point shade under it.
SQUIRCLE = "M20 0H44C57 0 64 7 64 20V44C64 57 57 64 44 64H20C7 64 0 57 0 44V20C0 7 7 0 20 0Z"


def dock_icon(kind, uid, full=False):
    def shaded(art):
        return f'<g transform="translate(0 1)" opacity=".16">{art.replace("#FFFFFF", "#000000")}</g>{art}'
    if kind == "browser":
        top, bottom = "#62C6FF", "#1A6FE0"
        art = ('<g fill="none" stroke="#FFFFFF" stroke-width="3.2" stroke-linecap="round">'
               '<circle cx="32" cy="32" r="17"/><path d="M15 32h34"/>'
               '<path d="M32 15c5.5 4.6 8.2 10.3 8.2 17S37.5 44.4 32 49c-5.5-4.6-8.2-10.3-8.2-17S26.5 19.6 32 15Z"/></g>'
               '<path d="M17.5 24h29M17.5 40h29" stroke="#FFFFFF" stroke-width="2.4" stroke-linecap="round"/>')
        glyph = shaded(art)
    elif kind == "chat":
        top, bottom = "#67DE6F", "#1EAD3B"
        art = ('<path d="M32 15c-10.5 0-19 6.9-19 15.4 0 4.6 2.5 8.7 6.4 11.6L18 50l7.7-3.4c2 .6 4.1.9 6.3.9 '
               '10.5 0 19-6.9 19-15.4S42.5 15 32 15Z" fill="#FFFFFF"/>')
        glyph = shaded(art)
    else:
        top, bottom = "#FAFAFB", "#D3D3D8"
        papers = ('<path d="M21 25c2.5-5 6-6.5 10-4.5 3.5-3 8.5-2.5 12 4.5Z" fill="#FFFFFF" stroke="#AEAEB2" stroke-width="1.2"/>'
                  if full else
                  '<rect x="17.5" y="18" width="29" height="4" rx="2" fill="#636366"/>'
                  '<path d="M27 18v-2.5a1.5 1.5 0 0 1 1.5-1.5h7a1.5 1.5 0 0 1 1.5 1.5V18" fill="none" stroke="#636366" stroke-width="2.4"/>')
        glyph = (papers + '<path d="M20.5 25h23l-2 23.5a3 3 0 0 1-3 2.5h-13a3 3 0 0 1-3-2.5Z" fill="#8E8E93"/>'
                 '<path d="M27 30v16M32 30v16M37 30v16" stroke="#FFFFFF" stroke-opacity=".75" stroke-width="2" stroke-linecap="round"/>')
    return (f'<svg viewBox="0 0 64 64" aria-hidden="true" focusable="false"><defs><linearGradient id="{uid}" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient></defs>'
            f'<path d="{SQUIRCLE}" fill="url(#{uid})"/>'
            f'<path d="{SQUIRCLE}" fill="none" stroke="#000000" stroke-opacity=".1"/>{glyph}</svg>')


class Draw:
    """Draws in a window's own left-to-right numbers, mirrored for Arabic.
    Colours are the desktop's tokens, so the windows follow light and dark."""

    def __init__(self, w, rtl):
        self.w, self.rtl = w, rtl

    def X(self, x):
        return self.w - x if self.rtl else x

    def L(self, x, w):
        return self.w - x - w if self.rtl else x

    def rect(self, x, y, w, h, style, rx=0, extra=""):
        r = f' rx="{rx:g}"' if rx else ""
        return f'<rect x="{self.L(x, w):g}" y="{y:g}" width="{w:g}" height="{h:g}"{r} style="{style}"{extra}/>'

    def text(self, x, y, s, size, weight=400, style="fill:var(--d-g9)", anchor="start", extra=""):
        return (f'<text x="{self.X(x):g}" y="{y:g}" font-size="{size:g}" font-weight="{weight}" style="{style}" '
                f'text-anchor="{anchor}"{extra}>{esc(s)}</text>')

    def circle(self, cx, cy, r, style, extra=""):
        return f'<circle cx="{self.X(cx):g}" cy="{cy:g}" r="{r:g}" style="{style}"{extra}/>'

    def glyph(self, name, cx, cy, size, color):
        s = size / 24
        return (f'<g transform="translate({self.X(cx) - size / 2:g} {cy - size / 2:g}) scale({s:g})" color="{color}" '
                f'style="--plane-crease: transparent">{ICONS[name]}</g>')


def window_frame(d, w, h, pid, title=""):
    """A window: rounded body, title bar, the three lights (the third greyed,
    as on a window that cannot be zoomed) and an optional title."""
    out = [d.rect(0, 0, w, h, "fill:var(--d-g0)", 14, f' filter="url(#{pid}shadow)"'),
           f'<path d="M0 14a14 14 0 0 1 14-14h{w - 28:g}a14 14 0 0 1 14 14v30H0Z" style="fill:var(--d-g1)"/>',
           d.rect(0, 44, w, 1, "fill:var(--d-g3)"),
           d.rect(0.25, 0.25, w - 0.5, h - 0.5, "fill:none;stroke:var(--d-hair);stroke-width:.5", 14)]
    for i, style in enumerate(["fill:var(--d-close)", "fill:var(--d-minimize)", "fill:var(--d-g4)"]):
        out.append(d.circle(20 + i * 20, 22, 6, style))
    if title:
        out.append(d.text(w / 2, 27, title, 13, 600, anchor="middle"))
    return out


def browser_window(lang, w, h, compact, pid):
    t = TEXT[lang]["desk"]
    d = Draw(w, TEXT[lang]["dir"] == "rtl")
    out = window_frame(d, w, h, pid)
    fx, fw = (88, w - 100) if compact else ((w - 280) / 2, 280)
    out.append(d.rect(fx, 8, fw, 28, "fill:var(--d-g2)", 6))
    out.append(d.text(fx + fw / 2, 26.5, t["url"], 13, 500, "fill:var(--d-g8)", "middle"))
    ty = 84
    out.append(d.text(24, ty, t["route"], 20 if compact else 22, 600))
    out.append(d.text(24, ty + 22, t["when"], 13, 400, "fill:var(--d-g7)"))
    sw, sh = 160, 32
    sx, sy = (24, ty + 36) if compact else (w - 24 - sw, ty - 26)
    out.append(d.rect(sx, sy, sw, sh, "fill:var(--d-g0);stroke:var(--d-g4)", 6))
    out.append(d.text(sx + 12, sy + 21, f'{t["sort"]}: {t["sort_items"][0]}', 13, 500, extra=' class="sort-label"'))
    out.append(f'<path d="M-4 -2 0 2 4 -2" transform="translate({d.X(sx + sw - 16):g} {sy + 16:g})" '
               'style="fill:none;stroke:var(--d-g7);stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round"/>')
    top = sy + sh + 16 if compact else ty + 40
    row_h, step = (68, 80) if compact else (72, 88)
    colors = ["#0A84FF", "#FF9F0A", "#BF5AF2"]
    by_price = sorted(range(3), key=lambda i: t["flights"][i][3])
    for i, (times, detail, price, *_numbers) in enumerate(t["flights"]):
        best = i == by_price[0]
        style = "fill:var(--d-success-wash);stroke:var(--d-success);stroke-width:1.5" if best else "fill:var(--d-g1)"
        row = [d.rect(24, 0, w - 48, row_h, style, 10),
               d.circle(52, row_h / 2, 14, f"fill:{colors[i]}"),
               d.glyph("plane", 52, row_h / 2, 16, "#FFFFFF"),
               d.text(80, row_h / 2 - 3, times, 15, 600),
               d.text(80, row_h / 2 + 16, detail, 13, 400, "fill:var(--d-g7)"),
               d.text(w - 40, row_h / 2 + (0 if best else 6), price, 17, 600, anchor="end")]
        if best:
            row.append(d.text(w - 40, row_h / 2 + 18, t["cheapest"], 11, 600, "fill:var(--d-success-text)", "end"))
        out.append(f'<g class="row" data-i="{i}" transform="translate(0 {top + by_price.index(i) * step:g})"><g class="row-in">{"".join(row)}</g></g>')
    # The sort menu as it is drawn when open, so a screenshot with a timer
    # can catch it; the one to use is the page's own menu over it.
    my = sy + sh + 4
    menu = [d.rect(sx, my, sw, 3 * 28 + 8, "fill:var(--d-g0);stroke:var(--d-hair)", 10, f' filter="url(#{pid}pop)"'),
            d.rect(sx + 4, my + 4, sw - 8, 28, "fill:var(--d-accent)", 6, ' class="sort-hl"')]
    for j, item in enumerate(t["sort_items"]):
        menu.append(d.text(sx + 28, my + 22 + j * 28, item, 13, 400, "fill:var(--d-on-accent)" if j == 0 else "fill:var(--d-g9)",
                           extra=f' class="sort-item" data-j="{j}"'))
    menu.append(f'<path class="sort-check" data-x="{d.X(sx + 15):g}" d="M-4 0 -1 3 4.5 -3.5" transform="translate({d.X(sx + 15):g} {my + 18:g})" '
                'style="fill:none;stroke:var(--d-g9);stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round"/>')
    out.append(f'<g class="sort-copy" display="none">{"".join(menu)}</g>')
    meta = {"sort": [d.L(sx, sw), sy, sw, sh], "rowsTop": top, "rowStep": step, "menuTop": my}
    return "".join(out), meta


def chat_window(lang, w, h, pid):
    t = TEXT[lang]["desk"]
    d = Draw(w, TEXT[lang]["dir"] == "rtl")
    out = window_frame(d, w, h, pid, t["person"])
    area = (12, 52, w - 24, h - 52 - 64)
    out.append(f'<clipPath id="{pid}msgs"><rect x="{area[0]}" y="{area[1]}" width="{area[2]}" height="{area[3]}"/></clipPath>')
    out.append(f'<g clip-path="url(#{pid}msgs)"><g class="msgs"></g></g>')
    out.append(d.rect(0, h - 56, w, 1, "fill:var(--d-g3)"))
    out.append(d.rect(16, h - 44, w - 72, 32, "fill:var(--d-g0);stroke:var(--d-g4)", 16))
    out.append(d.text(30, h - 23, t["field"], 13, 400, "fill:var(--d-g7)"))
    out.append(d.circle(w - 32, h - 28, 14, "fill:var(--d-accent)"))
    out.append(f'<path d="M0 6V-6M-5 -1 0 -6 5 -1" transform="translate({d.X(w - 32):g} {h - 28:g})" '
               'style="fill:none;stroke:#FFFFFF;stroke-width:2.2;stroke-linecap:round;stroke-linejoin:round"/>')
    meta = {"area": area, "send": [d.X(w - 32), h - 28]}
    return "".join(out), meta


def desk_scene(lang, name):
    """One layout of the desktop as a single SVG, the source of every
    screenshot taken on it, with the ids it needs prefixed by layout."""
    t = TEXT[lang]["desk"]
    rtl = TEXT[lang]["dir"] == "rtl"
    lay = DESK[name]
    W, H = lay["w"], lay["h"]
    x, y, w, h = lay["win"]
    pid = f"d{name[0]}-"
    browser, bmeta = browser_window(lang, w, h, lay["compact"], pid)
    chat, cmeta = chat_window(lang, w, h, pid)
    d = ' direction="rtl"' if rtl else ""
    out = [f'<svg class="desk-svg" data-layout="{name}" viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" '
           f'focusable="false" aria-hidden="true" font-family="-apple-system, BlinkMacSystemFont, system-ui, sans-serif"{d}>',
           f'<defs><linearGradient id="{pid}wall" x1="0" y1="0" x2="1" y2="1">'
           '<stop offset="0" style="stop-color:var(--d-wall-1)"/><stop offset=".55" style="stop-color:var(--d-wall-2)"/>'
           '<stop offset="1" style="stop-color:var(--d-wall-3)"/></linearGradient>'
           f'<filter id="{pid}shadow" x="-20%" y="-20%" width="140%" height="150%">'
           '<feDropShadow dx="0" dy="4" stdDeviation="6" flood-color="#000" flood-opacity=".1"/>'
           '<feDropShadow dx="0" dy="24" stdDeviation="28" flood-color="#000" flood-opacity=".22"/></filter>'
           f'<filter id="{pid}pop" x="-20%" y="-20%" width="140%" height="160%">'
           '<feDropShadow dx="0" dy="1" stdDeviation="1" flood-color="#000" flood-opacity=".1"/>'
           '<feDropShadow dx="0" dy="6" stdDeviation="8" flood-color="#000" flood-opacity=".12"/></filter></defs>',
           f'<rect width="{W}" height="{H}" fill="url(#{pid}wall)"/>',
           f'<g transform="translate({x} {y})"><g class="win" data-win="browser">{browser}</g></g>',
           f'<g transform="translate({x} {y})"><g class="win" data-win="chat" display="none">{chat}</g></g>']
    # The menu bar and the Dock as a screenshot shows them; on the page the
    # live ones sit over these, which stay hidden.
    clock = len(t["clock"]) * 13 * 0.55
    snap = W - 16 - clock - 20 if not rtl else 16 + clock + 20
    bar = [f'<rect width="{W}" height="{MENU_BAR}" style="fill:var(--d-g0);fill-opacity:.72"/>',
           f'<text class="cap-app" x="{W - 16 if rtl else 16}" y="18.5" font-size="13" font-weight="600" style="fill:var(--d-g9)">{esc(t["browser"])}</text>',
           f'<text x="{16 if rtl else W - 16}" y="18.5" font-size="13" text-anchor="end" style="fill:var(--d-g9)" xml:space="preserve">{esc(t["clock"])}</text>',
           f'<g transform="translate({snap - 8:g} 6) scale(.667)" style="color:var(--d-g9)">{ICONS["shirt"]}</g>']
    out.append(f'<g data-cap display="none">{"".join(bar)}</g>')
    if not lay["compact"]:
        icon, gap, pad = lay["icon"], 12, 8
        items = ["browser", "chat", None, "trash"]
        width = 3 * icon + 2 * gap + 1 + gap + 2 * pad
        dx, dy = (W - width) / 2, H - 16 - (icon + 2 * pad)
        dock = [f'<rect x="{dx:g}" y="{dy:g}" width="{width:g}" height="{icon + 2 * pad}" rx="16" '
                'style="fill:var(--d-g0);fill-opacity:.62;stroke:var(--d-hair)"/>']
        cx = dx + pad
        for kind in items:
            if kind is None:
                dock.append(f'<rect x="{cx:g}" y="{dy + pad + 8:g}" width="1" height="{icon - 16}" style="fill:var(--d-g4)"/>')
                cx += 1 + gap
                continue
            art = dock_icon(kind, f"{pid}cap-{kind}").replace('<svg viewBox="0 0 64 64"',
                                                               f'<svg class="cap-{kind}" x="{cx:g}" y="{dy + pad:g}" width="{icon}" height="{icon}" viewBox="0 0 64 64"')
            dock.append(art)
            cx += icon + gap
        out.append(f'<g data-cap display="none">{"".join(dock)}</g>')
    out.append("</svg>")
    meta = {
        "w": W, "h": H, "win": [x, y, w, h], "compact": lay["compact"], "card": lay["card"], "cards": lay["cards"],
        "shot": [W - lay["shot"][0] if rtl else lay["shot"][0], lay["shot"][1]],
        "sort": [x + bmeta["sort"][0], y + bmeta["sort"][1], bmeta["sort"][2], bmeta["sort"][3]],
        "rowsTop": bmeta["rowsTop"], "rowStep": bmeta["rowStep"], "menuTop": y + bmeta["menuTop"],
        "chatArea": cmeta["area"], "chatSend": [x + cmeta["send"][0], y + cmeta["send"][1]],
        "lights": [[x + (w - 20 - i * 20 if rtl else 20 + i * 20), y + 22] for i in range(3)],
    }
    return "".join(out), meta


def section_capture(lang):
    t = TEXT[lang]
    D = t["desk"]
    rtl = t["dir"] == "rtl"
    scenes, layouts = [], {}
    for name in DESK:
        svg, meta = desk_scene(lang, name)
        scenes.append(svg)
        layouts[name] = meta
    words = {k: D[k] for k in ("browser", "chat", "trash", "desktop", "shot", "rec", "person", "chat_in", "chat_reply",
                                "sort", "sort_items", "toast", "step_of", "show", "skip", "again", "done", "steps",
                                "put_back", "trash_empty", "close", "minimize")}
    words.update({"copy": L(lang, "Copy"), "discard": L(lang, "Discard"), "take": L(lang, "Take Screenshot"),
                  "stop": L(lang, "Stop Recording"), "record": L(lang, "Record Screen"),
                  "cancelTimer": L(lang, "Cancel the timer"), "send": t["chatbtn_label"],
                  "hints": {"shot": L(lang, "Drag over an area or click a window. Return takes the whole screen, Escape cancels."),
                            "timer": L(lang, "Choose what to take: drag over an area, click a window, or press Return for the whole screen. It is taken when the countdown ends."),
                            "record": L(lang, "Drag over an area or click a window to record it. Return records the whole screen, Escape cancels.")},
                  "flights": [list(f[3:]) for f in D["flights"]]})
    data = json.dumps({"layouts": layouts, "words": words, "menuBar": MENU_BAR}, ensure_ascii=False).replace("</", "<\\/")
    chord = lambda k: f'<span class="dmenu-key" dir="ltr">⌃⌥{k}</span>'
    seconds = "".join(
        f'<li role="none"><button type="button" role="menuitem" class="dmenu-item" data-act="timer" data-n="{n}"><span>{esc(L(lang, f"{n} Seconds"))}</span></button></li>'
        for n in (3, 5, 10))
    sf_menu = f"""<ul class="dmenu sf-menu" role="menu" aria-label="Snapfly" hidden>
          <li role="none"><button type="button" role="menuitem" class="dmenu-item" data-act="shot"><span>{esc(L(lang, "Take Screenshot"))}</span>{chord("S")}</button></li>
          <li role="none" class="has-sub"><button type="button" role="menuitem" class="dmenu-item" aria-haspopup="menu" aria-expanded="false" data-act="sub"><span>{esc(L(lang, "Take Screenshot with Timer"))}</span>{icon("chevron", "icon dmenu-chev")}</button>
            <ul class="dmenu dmenu-sub" role="menu" aria-label="{esc(L(lang, "Take Screenshot with Timer"))}">{seconds}</ul></li>
          <li role="none"><button type="button" role="menuitem" class="dmenu-item" data-act="record"><span>{esc(L(lang, "Record Screen"))}</span>{chord("R")}</button></li>
          <li role="none"><button type="button" role="menuitemcheckbox" aria-checked="true" class="dmenu-item" data-act="button"><span>{esc(L(lang, "Screenshot Button"))}</span>{icon("check", "icon dmenu-tick")}</button></li>
          <li class="dmenu-sep" role="separator"></li>
          <li role="none"><button type="button" role="menuitem" class="dmenu-item" data-act="clear" disabled><span>{esc(L(lang, "Take everything down"))}</span></button></li>
        </ul>"""
    shot_menu = f"""<ul class="dmenu shot-menu" role="menu" aria-label="{esc(L(lang, "Screenshot Button"))}" hidden>
          <li role="none"><button type="button" role="menuitem" class="dmenu-item" data-act="shot"><span>{esc(L(lang, "Choose an area"))}</span></button></li>
          <li role="none"><button type="button" role="menuitem" class="dmenu-item" data-act="whole"><span>{esc(L(lang, "Take the whole screen"))}</span></button></li>
          <li role="none"><button type="button" role="menuitem" class="dmenu-item" data-act="record"><span>{esc(L(lang, "Record Screen"))}</span></button></li>
        </ul>"""
    sort_menu = "".join(
        f'<li role="none"><button type="button" role="menuitemradio" aria-checked="{"true" if j == 0 else "false"}" class="dmenu-item" data-j="{j}">'
        f'<span>{esc(item)}</span>{icon("check", "icon dmenu-tick")}</button></li>'
        for j, item in enumerate(D["sort_items"]))
    lights = lambda app: (f'<button type="button" class="dlight dlight-close" data-act="close" aria-label="{esc(D["close"])}: {esc(D[app])}">{icon("xmark")}</button>'
                          f'<button type="button" class="dlight dlight-min" data-act="min" aria-label="{esc(D["minimize"])}: {esc(D[app])}"><svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 12h12" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/></svg></button>')
    dock_items = []
    for kind in ("browser", "chat", None, "trash"):
        if kind is None:
            dock_items.append('<span class="dock-sep" aria-hidden="true"></span>')
            continue
        popup = ' aria-haspopup="dialog" aria-expanded="false"' if kind == "trash" else ""
        art = dock_icon(kind, f"dock-{kind}")
        full = dock_icon("trash", "dock-trash-full", full=True).replace("<svg ", '<svg class="dock-full" ', 1) if kind == "trash" else ""
        dock_items.append(
            f'<button type="button" class="dock-item" data-app="{kind}" aria-label="{esc(D[kind])}"{popup} tabindex="{0 if kind == "browser" else -1}">'
            f'<span class="dock-icon">{art}{full}</span><span class="dock-tip" aria-hidden="true">{esc(D[kind])}</span>'
            f'<span class="dock-dot" aria-hidden="true"></span></button>')
    dock = f'<div class="dock" role="toolbar" aria-label="{esc(D["dock"])}">{"".join(dock_items)}</div>'
    send_button = (f'<button type="button" class="dsend" hidden aria-label="{esc(t["chatbtn_label"])}">'
                   f'<span class="dsend-thumbs" aria-hidden="true"><span></span><span></span></span>'
                   f'<span class="dsend-count" aria-hidden="true"></span>'
                   f'<span class="dsend-plane" aria-hidden="true">{icon("plane")}</span></button>')
    guide = f"""<div class="guide" role="dialog" aria-modal="false" aria-labelledby="guide-title" hidden tabindex="-1">
          <div class="guide-head"><p class="guide-step" data-guide-step></p>
            <button type="button" class="guide-x" data-guide-close aria-label="{esc(D["close_guide"])}">{icon("xmark")}</button></div>
          <div class="guide-bar" aria-hidden="true"><span></span></div>
          <h3 class="guide-title" id="guide-title"></h3>
          <p class="guide-text"></p>
          <div class="guide-actions">
            <button type="button" class="guide-skip" data-guide-skip>{esc(D["skip"])}</button>
            <button type="button" class="guide-go" data-guide-go>{esc(D["show"])}</button>
            <a class="guide-go guide-get" href="{DOWNLOAD}" hidden>{icon("download")}<span>{esc(t["cta"])}</span></a>
          </div>
          <span class="guide-arrow" aria-hidden="true"></span>
        </div>"""
    card = f"""<template data-card><li class="dcard landing">
          <span class="dclip" aria-hidden="true"></span>
          <div class="dphoto">
            <button type="button" class="dcard-hit"><span class="dcard-img"></span></button>
            <span class="dbadge" aria-hidden="true">{icon("play")}<span dir="ltr"></span></span>
            <button type="button" class="dcard-x">{icon("xmark")}</button>
          </div>
        </li></template>"""
    return f"""<section class="section capture" aria-labelledby="cap-h">
  <div class="wrap">
    <div class="copy center">
      <h2 id="cap-h">{esc(t["cap_h"])}</h2>
      <p>{t["cap_p"]}</p>
    </div>
  </div>
  <div class="desk-stage" data-try-desk>
    <script type="application/json" data-desk-data>{data}</script>
    <div class="desk-frame">
      <div class="desk-fit">
        <div class="dscreen" role="group" aria-label="{esc(D["label"])}" data-layout="wide">
          <div class="desk-scene">{"".join(scenes)}</div>
          <div class="desk-grain" aria-hidden="true"></div>
          <header class="desk-bar">
            <span class="bar-app" aria-live="polite">{esc(D["browser"])}</span>
            <span class="bar-end">
              <button type="button" class="bar-snapfly" aria-haspopup="menu" aria-expanded="false" aria-label="Snapfly">{icon("shirt", "icon bar-shirt")}{icon("stop", "icon bar-stop")}</button>
              <span class="bar-clock" xml:space="preserve">{esc(D["clock"])}</span>
            </span>
          </header>
          <div class="dline">
            <svg class="dline-rope" viewBox="0 0 1000 100" preserveAspectRatio="none" aria-hidden="true" focusable="false"><path d="M-20 12 Q500 70 1020 12"/></svg>
            <ul class="dline-pegs" aria-label="{esc(D["line"])}"></ul>
          </div>
          <div class="wctl" data-for="browser">{lights("browser")}
            <button type="button" class="sort-btn" aria-haspopup="menu" aria-expanded="false"><span class="vh" data-sort-label></span></button>
          </div>
          <div class="wctl" data-for="chat" hidden>{lights("chat")}{send_button}</div>
          <ul class="dmenu sort-menu" role="menu" aria-label="{esc(D["sort"])}" hidden>{sort_menu}</ul>
          <button type="button" class="dshot" aria-label="{esc(L(lang, "Take Screenshot"))}">{icon("viewfinder", "icon dshot-glyph")}{icon("stop", "icon dshot-stop")}</button>
          <span class="dpointer" aria-hidden="true" hidden>{icon("pointer")}</span>
          <div class="rec-edge" aria-hidden="true" hidden></div>
          <div class="cap-flash" aria-hidden="true"></div>
          <div class="cap-overlay" tabindex="-1" hidden role="dialog" aria-label="{esc(L(lang, "Take Screenshot"))}" aria-describedby="cap-hint">
            <div class="cap-dim"></div>
            <div class="cap-win" hidden></div>
            <div class="cap-area" hidden><span class="cap-size" dir="ltr"></span></div>
            <p class="cap-hint" id="cap-hint"><span data-hint></span> <button type="button" class="cap-cancel">{esc(L(lang, "Cancel"))}</button></p>
          </div>
          <div class="dring" aria-hidden="true" hidden></div>
          <div class="dstack">
            <div class="dtoasts" role="status" aria-live="polite"></div>
            <button type="button" class="capsule" hidden>
              <span class="cap-timer" data-for="countdown">{icon("timer")}</span><span class="cap-count" data-for="countdown" dir="ltr"></span><span class="cap-x" data-for="countdown">{icon("xmark")}</span>
              <span class="cap-stop" data-for="recording">{icon("stop")}</span><span class="cap-time" data-for="recording" dir="ltr">0:00</span>
            </button>
          </div>
          {sf_menu}
          {shot_menu}
          <div class="trash-pop" role="dialog" aria-label="{esc(D["trash"])}" hidden>
            <p class="trash-title">{esc(D["trash"])}</p>
            <ul class="trash-list"></ul>
            <p class="trash-empty">{esc(D["trash_empty"])}</p>
            <button type="button" class="trash-clear">{esc(D["empty_trash"])}</button>
          </div>
          <div class="dock-slot" data-slot="desk">{dock}</div>
          <div class="guide-slot" data-slot="desk">{guide}</div>
        </div>
      </div>
      <div class="desk-foot">
        <div class="guide-slot" data-slot="sheet"></div>
        <div class="dock-slot" data-slot="bar"></div>
      </div>
    </div>
    <div class="guide-slot" data-slot="below"></div>
    {card}
  </div>
  <p class="desk-note">{esc(D["note"])} <button type="button" class="desk-guide-btn" data-guide-start>{icon("replay")}<span>{esc(D["guide"])}</span></button></p>
</section>"""


def section_start(lang):
    """Four steps from the download to the first screenshot on the line."""
    t = TEXT[lang]
    symbols = ["download", "shirt", "lock", "viewfinder"]
    steps = "".join(
        f'<li class="step"><span class="step-top"><span class="step-n">{i + 1}</span>'
        f'<span class="step-icon">{icon(symbols[i])}</span></span><h3>{esc(h)}</h3><p>{esc(b)}</p></li>'
        for i, (h, b) in enumerate(t["start"]))
    return f"""<section class="section start" aria-labelledby="start-h">
  <div class="wrap">
    <div class="copy center">
      <h2 id="start-h">{esc(t["start_h"])}</h2>
      <p>{esc(t["start_p"])}</p>
    </div>
    <ol class="steps">{steps}</ol>
  </div>
</section>"""


# MARK: Hide Part, said in a sentence

def section_say(lang):
    t, r = TEXT[lang], TEXT[lang]["rcpt"]
    piece = lambda k, s, ltr=False: f'<span class="pc{" ltr" if ltr else ""}" data-k="{k}">{esc(s)}</span>'
    rows = [
        (r["from_l"], piece("name", r["from_name"]) + "<br>" + piece("bank", r["from_iban"], True)),
        (r["to_l"], piece("name", r["to_name"]) + "<br>" + piece("bank", r["to_iban"], True)),
        (r["ref_l"], piece("ref", r["ref"])),
        (r["addr_l"], piece("address", r["addr"])),
        (r["email_l"], piece("email", r["email"], True)),
        (r["phone_l"], piece("phone", r["phone"], True)),
    ]
    dl = "".join(f"<div><dt>{esc(a)}</dt><dd>{b}</dd></div>" for a, b in rows)
    examples = "".join(f'<button type="button" class="mac-btn small" data-example>{esc(L(lang, k))}</button>'
                       for k in ("Names and addresses", "Everything but the amount and the date", "Phone numbers and emails"))
    say = L(lang, "Say what to hide, like “everything but the amount and the date”")
    return f"""<section class="section say" aria-labelledby="say-h">
  <div class="wrap split">
    <div class="copy">
      <h2 id="say-h">{esc(t["say_h"])}</h2>
      <p>{esc(t["say_p"])}</p>
      <p class="try-note">{esc(t["say_try"])}</p>
    </div>
    <div class="window hide-win" role="group" aria-label="{esc(t["say_label"])}" data-hide
         data-note="{esc(L(lang, "Parts hidden: %d. Click a box to show it again."))}" data-nothing="{esc(L(lang, "Nothing found to hide."))}">
      {window_titlebar(t["say_file"])}
      <div class="hide-canvas" data-hide-canvas>
        <div class="photo-shot">
          <div class="rc" data-doc>
            <div class="rc-head">
              <span class="rc-check" aria-hidden="true">{icon("check")}</span>
              <p class="rc-title">{esc(r["title"])}</p>
              <p class="rc-date">{piece("date", r["date"])}</p>
              <p class="rc-amount">{piece("amount", r["amount"], True)}</p>
            </div>
            <dl class="rc-rows">{dl}</dl>
          </div>
          <div class="hide-boxes" data-boxes></div>
          <span class="badge-lock" aria-hidden="true">{icon("lock")}</span>
        </div>
        <template data-eye>{icon("eye")}</template>
      </div>
      <form class="saying" data-saying>
        <div class="say-row">
          <span class="say-glyph" aria-hidden="true">{icon("sparkles")}</span>
          <input class="say-field" type="text" placeholder="{esc(say)}" aria-label="{esc(say)}" autocomplete="off" enterkeyhint="done">
          <span class="spinner" aria-hidden="true" hidden></span>
          <button type="submit" class="mac-btn" data-hide-btn disabled>{esc(L(lang, "Hide"))}</button>
        </div>
        <div class="say-examples">{examples}</div>
        <p class="say-note" aria-live="polite" data-note-text></p>
      </form>
      <div class="hide-foot">
        <p>{esc(L(lang, "Drag over anything to hide it. Click a box to show it again."))}</p>
        <span class="foot-buttons">
          <button type="button" class="mac-btn" data-remove-all disabled>{esc(L(lang, "Remove All"))}</button>
          <button type="button" class="mac-btn" data-cancel>{esc(L(lang, "Cancel"))}</button>
          <button type="button" class="mac-btn primary" data-done>{esc(L(lang, "Done"))}</button>
        </span>
      </div>
    </div>
  </div>
</section>"""


def still_pegs(lang, kinds, uid, cls="pegs", held=None):
    """Screenshots hanging still on a line, for the demos further down."""
    out = []
    for i, kind in enumerate(kinds):
        extra = " held" if i == held else ""
        out.append(f'<li class="peg still{extra}" style="--t:{(i + 0.5) / len(kinds):.4f};--tilt:{TILTS[i]};--i:{i}">'
                   f'<span class="clip"></span><div class="photo"><span class="photo-img">{art(kind, lang, f"{uid}{i}")}</span></div></li>')
    return f'<ul class="{cls}" aria-hidden="true">{"".join(out)}</ul>'


def window_titlebar(title):
    return (f'<div class="titlebar"><span class="lights" aria-hidden="true"><i></i><i></i><i></i></span>'
            f'<span class="window-title">{esc(title)}</span></div>')


def settings_sidebar(lang, current):
    items = [("gear", "General"), ("shirt", "Line"), ("hand", "Privacy"), ("info", "About")]
    mark = lambda key: ' class="on"' if key == current else ""
    rows = "".join(f'<li{mark(key)}>{icon(sym)}<span>{esc(L(lang, key))}</span></li>' for sym, key in items)
    return f'<ul class="settings-side" aria-hidden="true">{rows}</ul>'


def section_desk(lang):
    t = TEXT[lang]
    # Where each file sits on the Desktop, arranged the way macOS arranges
    # icons, from the top corner down.
    spots = [(84, 4), (84, 37), (84, 70), (60, 10), (60, 43), (60, 76), (36, 22), (36, 56), (13, 38)]
    files = []
    for i, (x, y) in enumerate(spots):
        kind = CARDS[i % len(CARDS)]
        name = t["desk_file"].format(m=f"{41 + i:02d}", s=f"{(i * 7 + 12) % 60:02d}")
        files.append(f'<li class="file" style="--x:{x}%;--y:{y}%;--i:{i}"><span class="file-thumb">{art(kind, lang, f"desk{i}")}</span><span class="file-name">{esc(name)}</span></li>')
    return f"""<section class="section desk" aria-labelledby="desk-h" data-desk>
  {rope("desk-rope")}
  <div class="wrap split">
    <div class="copy">
      <h2 id="desk-h">{esc(t["desk_h"])}</h2>
      <p>{esc(t["desk_p"])}</p>
      <p><button class="replay" type="button" data-replay>{icon("replay")}<span>{esc(t["replay"])}</span></button></p>
    </div>
    <div class="desk-files" role="img" aria-label="{esc(t["desk_label"])}"><ul aria-hidden="true">{"".join(files)}</ul></div>
  </div>
</section>"""


def section_private(lang):
    t, inv = TEXT[lang], TEXT[lang]["inv"]
    kinds = [("names", "Names"), ("addresses", "Addresses"), ("emails", "Emails"),
             ("phones", "Phone numbers"), ("bank", "Bank cards and accounts")]
    switches = "".join(
        f'<label class="row"><span>{esc(L(lang, label))}</span><input type="checkbox" role="switch" value="{k}" checked data-kind></label>'
        for k, label in kinds)
    field = lambda kind, text, cls="": f'<span class="pd{(" " + cls) if cls else ""}" data-pd="{kind}">{esc(text)}</span>'
    items = "".join(f'<li><span>{esc(a)}</span><span>{esc(b)}</span></li>' for a, b in inv["items"])
    return f"""<section class="section private" aria-labelledby="priv-h">
  <div class="wrap split">
    <div class="copy">
      <h2 id="priv-h">{esc(t["priv_h"])}</h2>
      <p>{esc(t["priv_p"])}</p>
    </div>
    <div class="window settings">
      {window_titlebar(L(lang, "Settings"))}
      <div class="settings-body">
        {settings_sidebar(lang, "Privacy")}
        <form class="settings-pane" data-cover onsubmit="return false">
          <fieldset class="group">
            <legend class="group-label">{esc(L(lang, "Hide private details"))}</legend>
            <div class="group-box">{switches}</div>
            <p class="group-note">{esc(L(lang, "What is checked is covered in whatever leaves the line"))}</p>
          </fieldset>
          <div class="group">
            <p class="group-label">{esc(L(lang, "Preview"))} · <span class="example">{esc(t["example"])}</span></p>
            <div class="group-box preview">
              <div class="photo photo-preview" data-invoice aria-hidden="true">
                <div class="doc-shot">
                  <div class="doc-top"><div><p class="doc-title">{esc(inv["title"])}</p><p class="doc-dim">{esc(inv["date"])}</p></div>
                    <div class="doc-total"><p class="doc-title">{esc(inv["total_v"])}</p><p class="doc-dim">{esc(inv["total"])}</p></div></div>
                  <p class="doc-label">{esc(inv["bill"])}</p>
                  <p>{field("names", inv["name"])}</p>
                  <p>{field("addresses", inv["street"])} · {field("addresses", inv["city"])}</p>
                  <p>{field("emails", inv["email"], "ltr")}</p>
                  <p>{field("phones", inv["phone"], "ltr")}</p>
                  <ul class="doc-items">{items}</ul>
                  <p>{field("bank", inv["iban"], "ltr")}</p>
                </div>
                <span class="badge-lock">{icon("lock")}</span>
              </div>
            </div>
          </div>
        </form>
      </div>
    </div>
  </div>
</section>"""


def section_menu(lang):
    t = TEXT[lang]
    d = t["menu_desc"]
    # The photo's menu, in the app's order and with the app's words.
    rows = [("Copy", False), ("Copy Text", False), ("Paste into %@", False), ("Make PDF", False),
            ("Combine into one image", True), ("Pin", False), None,
            ("Translate Text", True), ("Describe", False), None,
            ("Quick Look", False), ("Markup", False), ("Hide Part…", False), ("Show in Finder", False), None,
            ("Discard", False)]
    items = []
    for row in rows:
        if row is None:
            items.append('<li class="ctx-sep" aria-hidden="true"></li>')
            continue
        key, sub = row
        label = L(lang, key).replace("%@", t["chat_app"])
        selected = ' aria-pressed="true"' if key == "Make PDF" else ' aria-pressed="false"'
        chevron = icon("chevron", "icon chev") if sub else ""
        items.append(f'<li><button type="button" class="ctx-item" data-title="{esc(label)}" data-desc="{esc(d[key])}"{selected}><span>{esc(label)}</span>{chevron}</button></li>')
    return f"""<section class="section menu-demo" aria-labelledby="menu-h">
  <div class="wrap">
    <div class="copy center">
      <h2 id="menu-h">{esc(t["menu_h"])}</h2>
      <p>{esc(t["menu_p"])}</p>
    </div>
  </div>
  <div class="menu-stage">
    {rope("menu-rope")}
    {still_pegs(lang, ["map", "calendar", "sunset"], "menu", held=1)}
    {icon("pointer", "pointer")}
    <ul class="ctx-menu" data-menu>{"".join(items)}</ul>
    <div class="menu-desc" aria-live="polite" data-menu-desc>
      <p class="menu-desc-title">{esc(L(lang, "Make PDF"))}</p>
      <p>{esc(d["Make PDF"])}</p>
      <p class="menu-hint">{esc(t["menu_hint"])}</p>
    </div>
  </div>
</section>"""


def tile_art(style):
    """The little picture on each line-style tile, as in the app's settings."""
    card = lambda x, y, r=0: f'<rect x="{x}" y="{y}" width="20" height="14" rx="2.5" fill="#fff" transform="rotate({r} {x + 10} {y})"/>'
    body = {
        "clothesline": '<path d="M2 9 Q44 26 86 9" stroke="#4a3a4e" stroke-width="1.2" fill="none"/>' + card(16, 14, -5) + card(34, 18, 3) + card(54, 15, -2),
        "shelf": '<rect x="14" y="34" width="60" height="9" rx="4.5" fill="rgba(255,255,255,.55)"/>' + card(18, 20) + card(34, 20) + card(50, 20),
        "island": '<path d="M18 0h52v24a10 10 0 0 1-10 10H28a10 10 0 0 1-10-10Z" fill="#000"/>' + card(23, 10) + card(34, 10) + card(45, 10),
        "stack": card(58, 20, -8) + card(60, 21, 5) + card(61, 22) + '<circle cx="80" cy="18" r="5" fill="#FF3B30"/>',
    }[style]
    return (f'<svg viewBox="0 0 88 56" aria-hidden="true" focusable="false">'
            f'<rect width="88" height="56" rx="6" fill="url(#tile-wall)"/>{body}</svg>')


def section_styles(lang):
    t = TEXT[lang]
    styles = [("clothesline", "Clothesline"), ("shelf", "Glass shelf"), ("island", "Island"), ("stack", "Card stack")]
    tiles = "".join(
        f'<label class="tile"><input type="radio" name="line-style" value="{v}"{" checked" if v == "clothesline" else ""} data-caption="{esc(t["styles"][k])}">'
        f'<span class="tile-art">{tile_art(v)}</span><span class="tile-name">{esc(L(lang, k))}</span></label>'
        for v, k in styles)
    cards = "".join(f'<span class="sty s{i + 1}" style="--i:{i};--tilt:{TILTS[i]}"><span class="mini-clip"></span><span class="photo"><span class="photo-img">{art(k, lang, f"style{i}")}</span></span></span>'
                    for i, k in enumerate(["map", "invoice", "sunset"]))
    gradient = ('<svg width="0" height="0" style="position:absolute" aria-hidden="true" focusable="false"><defs>'
                '<linearGradient id="tile-wall" x1="0" y1="0" x2="1" y2="1"><stop offset="0" style="stop-color:var(--tile-a)"/>'
                '<stop offset=".5" style="stop-color:var(--tile-b)"/><stop offset="1" style="stop-color:var(--tile-c)"/></linearGradient></defs></svg>')
    return f"""<section class="section styles" aria-labelledby="styles-h" data-style-stage data-style="clothesline">
  <div class="style-line" aria-hidden="true">
    {rope("style-rope")}
    <span class="shelf"></span><span class="island"></span>
    {cards}
    <span class="count">3</span>
  </div>
  <div class="wrap split">
    <div class="copy">
      <h2 id="styles-h">{esc(t["styles_h"])}</h2>
      <p>{esc(t["styles_p"])}</p>
    </div>
    <div class="window settings settings-line">
      {window_titlebar(L(lang, "Settings"))}
      <div class="settings-body">
        {settings_sidebar(lang, "Line")}
        <div class="settings-pane">
          {gradient}
          <fieldset class="group tiles" data-styles>
            <legend class="group-label">{esc(L(lang, "Line style"))}</legend>
            <div class="tile-grid">{tiles}</div>
          </fieldset>
          <p class="group-note" aria-live="polite" data-style-caption>{esc(t["styles"]["Clothesline"])}</p>
        </div>
      </div>
    </div>
  </div>
</section>"""


def section_design(lang):
    t = TEXT[lang]
    points = "".join(f'<span class="point">{esc(p)}</span> ' for p in t["design_points"]).strip()
    return f"""<section class="section design" aria-labelledby="design-h">
  <div class="wrap narrow">
    <h2 id="design-h" class="points">{points}</h2>
    <p><strong>{esc(t["design_h"])}</strong> {esc(t["design_p"])}</p>
    <p><a class="link-arrow" href="{href_to(lang, lang, "privacy")}">{esc(t["design_link"])}{icon("arrow")}</a></p>
  </div>
</section>"""


def section_close(lang):
    t = TEXT[lang]
    return f"""<section class="close" aria-labelledby="close-h">
  <div class="wrap center">
    <img class="close-icon" src="{prefix(lang)}assets/icon-256.png" alt="" width="128" height="128">
    <h2 id="close-h">{esc(t["close_h"])}</h2>
    <p class="hero-actions">{download_button(lang)}</p>
    <p class="hero-note">{esc(t["close_note"])}</p>
  </div>
</section>"""


def home(lang):
    t = TEXT[lang]
    main = "\n".join([hero(lang), section_send(lang), section_capture(lang), section_desk(lang), section_private(lang),
                      section_say(lang), section_menu(lang), section_styles(lang), section_design(lang), section_start(lang),
                      section_close(lang)])
    return document(lang, "index", t["title_home"], t["desc_home"], main)


# MARK: Privacy and support

def doc_head(lang, title, extra=""):
    return f"""<header class="doc-head">
    <img src="{prefix(lang)}assets/icon-128.png" alt="" width="64" height="64">
    <h1>{esc(title)}</h1>
    {extra}
  </header>"""


def privacy(lang):
    t = TEXT[lang]
    updated = f'<p class="muted">{esc(t["updated_label"])}: <time datetime="2026-10-15">{esc(t["updated"])}</time></p>'
    sections = "\n".join(f'<section><h2>{esc(h)}</h2>{body}</section>' for h, body in t["privacy"])
    main = f"""<article class="doc wrap narrow">
  {doc_head(lang, t["privacy_title"], updated)}
  <aside class="summary"><h2>{esc(t["privacy_short_h"])}</h2><p>{esc(t["privacy_short"])}</p></aside>
  {sections}
</article>"""
    return document(lang, "privacy", t["title_privacy"], t["desc_privacy"], main)


def support(lang):
    t = TEXT[lang]
    mail = f"mailto:{EMAIL}?subject={quote(t['support_subject'])}"
    contact = f"""<p class="muted">{esc(t["support_intro"])}</p>
    <p class="contact"><a class="btn btn-primary" href="{mail}">{icon("mail")}<span>{esc(t["support_mail"])}</span></a> <bdi class="email">{EMAIL}</bdi></p>"""
    faq = "\n".join(f'<details class="faq"><summary>{esc(q)}{icon("chevron", "icon chev")}</summary><div class="faq-body">{a}</div></details>'
                    for q, a in t["faq"])
    main = f"""<article class="doc wrap narrow">
  {doc_head(lang, t["support_title"], contact)}
  <h2>{esc(t["faq_h"])}</h2>
  <div class="faqs">{faq}</div>
</article>"""
    return document(lang, "support", t["title_support"], t["desc_support"], main)


def not_found():
    t = TEXT["en"]
    base = BASE_PATH
    return f"""<!doctype html>
<html lang="en" dir="ltr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(t["notfound_title"])} · Snapfly</title>
<meta name="color-scheme" content="light dark">
<meta name="robots" content="noindex">
<script>{BRAND_JS}</script>
<link rel="icon" href="{base}assets/favicon.png" type="image/png">
<link rel="stylesheet" href="{base}assets/site.css">
</head>
<body class="page-404">
<main id="main" class="doc wrap narrow center">
  <img src="{base}assets/icon-128.png" alt="" width="96" height="96">
  <h1>{esc(t["notfound_title"])}</h1>
  <p class="muted">{esc(t["notfound_p"])}</p>
  <p><a class="btn btn-primary" href="{base}">{esc(t["notfound_link"])}</a></p>
</main>
</body>
</html>
"""


def sitemap():
    urls = []
    for page in ("index", "privacy", "support"):
        for code, d, _ in LANGS:
            loc = f"{SITE_URL}{d}{'' if page == 'index' else page + '.html'}"
            alts = "".join(
                f'<xhtml:link rel="alternate" hreflang="{c}" href="{SITE_URL}{dd}{"" if page == "index" else page + ".html"}"/>'
                for c, dd, _ in LANGS)
            urls.append(f"<url><loc>{loc}</loc>{alts}</url>")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">'
            + "".join(urls) + "</urlset>\n")


def check_policy():
    """Stops the build when vercel.json no longer allows an inline script."""
    config = json.loads((HERE.parent / "vercel.json").read_text(encoding="utf-8"))
    policy = " ".join(h["value"] for rule in config.get("headers", []) for h in rule["headers"]
                      if h["key"].lower() == "content-security-policy")
    for script in INLINE_JS:
        digest = base64.b64encode(hashlib.sha256(script.encode()).digest()).decode()
        if f"'sha256-{digest}'" not in policy:
            sys.exit(f"vercel.json: put 'sha256-{digest}' in script-src of the Content-Security-Policy.")


def main():
    check_policy()
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "assets").mkdir(parents=True)
    for f in STATIC.iterdir():
        if f.is_file():
            shutil.copy2(f, OUT / "assets" / f.name)
    for code, d, _ in LANGS:
        folder = OUT / d
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "index.html").write_text(home(code), encoding="utf-8")
        (folder / "privacy.html").write_text(privacy(code), encoding="utf-8")
        (folder / "support.html").write_text(support(code), encoding="utf-8")
    (OUT / "404.html").write_text(not_found(), encoding="utf-8")
    (OUT / "sitemap.xml").write_text(sitemap(), encoding="utf-8")
    (OUT / "robots.txt").write_text(f"User-agent: *\nAllow: /\nSitemap: {SITE_URL}sitemap.xml\n", encoding="utf-8")
    # GitHub Pages serves the files as they are, without Jekyll.
    (OUT / ".nojekyll").write_text("", encoding="utf-8")
    pages = sum(1 for _ in OUT.rglob("*.html"))
    print(f"Built {pages} pages into {OUT.relative_to(HERE.parent)}")


if __name__ == "__main__":
    main()

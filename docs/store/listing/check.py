#!/usr/bin/env python3
"""Checks the App Store listing texts before they are pasted into App Store
Connect: every file is there, plain UTF-8 text with one trailing newline, and
within Apple's limits. Run it from anywhere: python3 docs/store/listing/check.py
"""

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

LOCALES = ["en-US", "de-DE", "ar-SA", "es-ES", "fr-FR", "hi", "ja", "ko",
           "pt-BR", "tr", "zh-Hans"]
PLATFORMS = ["ios", "macos"]

# App Store Connect's limits, in characters.
SHARED = {"name.txt": 30, "subtitle.txt": 30}
PER_PLATFORM = {
    "description.txt": 4000,
    "keywords.txt": 100,
    "promotional_text.txt": 170,
    "release_notes.txt": 4000,
}
# What a description should aim for; outside it is a warning, not a failure.
DESCRIPTION_AIM = (1200, 2200)
# Languages written without spaces between words, where the same text is
# far shorter in characters.
DENSE = {"ja", "ko", "zh-Hans"}

# Words that must never appear: the project Snapfly came from, claims the
# app can't back, and other screenshot apps.
BANNED = [
    "tendedero", "end-to-end", "end to end", "ende-zu-ende", "no. 1", "nr. 1",
    "#1", "best ", "beste ", "snagit", "cleanshot", "lightshot", "skitch",
    "shottr", "monosnap", "greenshot", "pro version", "snapfly pro",
]

errors = []
warnings = []


def read(path):
    rel = path.relative_to(HERE)
    if not path.is_file():
        errors.append(f"missing: {rel}")
        return None
    raw = path.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        errors.append(f"not UTF-8: {rel}")
        return None
    if raw.startswith(b"\xef\xbb\xbf"):
        errors.append(f"has a byte order mark: {rel}")
    if not text.endswith("\n"):
        errors.append(f"no trailing newline: {rel}")
    if text.endswith("\n\n"):
        errors.append(f"blank line at the end: {rel}")
    if "\r" in text:
        errors.append(f"Windows line endings: {rel}")
    body = text.rstrip("\n")
    if not body.strip():
        errors.append(f"empty: {rel}")
    if re.search(r"\*\*|^#|`|\]\(", body, re.M):
        errors.append(f"looks like Markdown: {rel}")
    lower = body.lower()
    for word in BANNED:
        if word in lower:
            errors.append(f"banned word {word.strip()!r}: {rel}")
    return body


def words(text):
    parts = re.split(r"[\s,.;:!?·،、。，：！？\-–—/()«»„“”\"']+", text.lower())
    return {w for w in parts if w}


def check_limit(rel, body, limit):
    n = len(body)
    if n > limit:
        errors.append(f"{rel}: {n} characters, limit {limit}")
    return n


rows = []
for locale in LOCALES:
    folder = HERE / locale
    name = read(folder / "name.txt")
    subtitle = read(folder / "subtitle.txt")
    if name is not None:
        check_limit(f"{locale}/name.txt", name, SHARED["name.txt"])
        if name != "Snapfly":
            errors.append(f"{locale}/name.txt: should be Snapfly, is {name!r}")
    if subtitle is not None:
        check_limit(f"{locale}/subtitle.txt", subtitle, SHARED["subtitle.txt"])
        if "\n" in subtitle:
            errors.append(f"{locale}/subtitle.txt: more than one line")
    taken = words(f"{name or ''} {subtitle or ''}")
    row = [locale, len(subtitle or "")]
    for platform in PLATFORMS:
        for file, limit in PER_PLATFORM.items():
            rel = f"{locale}/{platform}/{file}"
            body = read(folder / platform / file)
            if body is None:
                row.append("-")
                continue
            n = check_limit(rel, body, limit)
            row.append(n)
            if file == "description.txt":
                low, high = DESCRIPTION_AIM
                if locale in DENSE:
                    low, high = low // 3, high
                if not low <= n <= high:
                    warnings.append(f"{rel}: {n} characters, aim {low}-{high}")
            if file == "promotional_text.txt" and "\n" in body:
                errors.append(f"{rel}: more than one line")
            if file == "keywords.txt":
                if "\n" in body:
                    errors.append(f"{rel}: more than one line")
                if re.search(r",\s|\s,", body):
                    errors.append(f"{rel}: a space beside a comma")
                items = body.split(",")
                if any(not item.strip() for item in items):
                    errors.append(f"{rel}: an empty keyword")
                if len({i.lower() for i in items}) != len(items):
                    errors.append(f"{rel}: a keyword twice")
                for item in items:
                    low_item = item.lower()
                    for w in low_item.split():
                        if w in taken:
                            errors.append(f"{rel}: {w!r} is already in the name or subtitle")
                    # Without spaces between words, a keyword found inside the
                    # subtitle is wasted too.
                    if locale in DENSE and subtitle and low_item in subtitle.lower():
                        errors.append(f"{rel}: {item!r} is already in the subtitle")
    rows.append(row)

short = {"description.txt": "desc", "keywords.txt": "keyw",
         "promotional_text.txt": "promo", "release_notes.txt": "notes"}
head = ["locale", "subtitle"] + [f"{p}.{short[f]}" for p in PLATFORMS for f in PER_PLATFORM]
print(" ".join(f"{h:>11}" for h in head))
for row in rows:
    print(" ".join(f"{str(c):>11}" for c in row))
print()
for w in warnings:
    print("warning:", w)
for e in errors:
    print("error:", e)
print(f"{len(LOCALES)} locales, {len(errors)} errors, {len(warnings)} warnings")
sys.exit(1 if errors else 0)

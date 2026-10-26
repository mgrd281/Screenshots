# App Store listing

The texts for Snapfly's page in App Store Connect, ready to paste. Nothing
here is uploaded by a workflow or a script: the owner copies each file into
App Store Connect by hand.

## Folders

One folder per App Store Connect language:

| Folder | Language in App Store Connect |
|:--|:--|
| `en-US` | English (U.S.) |
| `de-DE` | German |
| `ar-SA` | Arabic |
| `es-ES` | Spanish (Spain) |
| `fr-FR` | French |
| `hi` | Hindi |
| `ja` | Japanese |
| `ko` | Korean |
| `pt-BR` | Portuguese (Brazil) |
| `tr` | Turkish |
| `zh-Hans` | Chinese (Simplified) |

App Store Connect has no Azerbaijani or Galician listing, though the app
speaks both. People whose App Store is in one of those languages see the
English listing.

## Files

| File | Limit | Where it goes |
|:--|:--|:--|
| `name.txt` | 30 characters | App Information › Name |
| `subtitle.txt` | 30 characters | App Information › Subtitle |
| `ios/description.txt`, `macos/description.txt` | 4000 characters | the version page › Description |
| `ios/keywords.txt`, `macos/keywords.txt` | 100 characters | the version page › Keywords |
| `ios/promotional_text.txt`, `macos/promotional_text.txt` | 170 characters | the version page › Promotional Text |
| `ios/release_notes.txt`, `macos/release_notes.txt` | 4000 characters | the version page › What's New in This Version |

Name and subtitle belong to the app record, so the iPhone and the Mac share
them. Description, keywords, promotional text and release notes belong to
each platform's version, so `ios/` goes on the iOS App version page and
`macos/` on the macOS App one. The release notes are for version 1.1.0, from
the 1.1.0 section of `CHANGELOG.md`; replace them for each new version.
Promotional text can change at any time without a new build.

## Rules for the texts

- Plain text, UTF-8, no Markdown. App Store Connect shows line breaks as
  they are.
- Keywords are separated by commas with no spaces after them, and repeat no
  word of the name or the subtitle: Apple already searches those.
- Only what the app really does, as `README.md` and `CHANGELOG.md` describe
  it. No numbers, ratings, quotes or comparisons that can't be shown; never
  "end-to-end encrypted"; nothing about Pro.
- Each language uses the words the app itself shows, from
  `Sources/Tendedero/Resources/<language>.lproj/Localizable.strings`.
  German says "du", French and Spanish "tu" and "tú", like the app.

## Check

```
python3 docs/store/listing/check.py
```

It checks that every file is there, plain UTF-8 with one trailing newline,
within its limit, and that the keywords follow the rules above. It warns when
a description is outside 1200 to 2200 characters (less for Japanese, Korean
and Chinese, which are shorter in characters).

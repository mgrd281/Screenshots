# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Snapfly is a native macOS app (AppKit and SwiftUI), not a web app. Impeccable's
schema only knows `web`, `ios`, `android` and `adaptive`. Its `ios.md`
reference is the closest native guidance, but read it for Apple conventions,
not for touch sizes: Snapfly is used with a pointer and a keyboard.

## Users

The owner is the main user. They are not a programmer and they work in German
and Arabic on a Mac set to German. Each day they take screenshots, often of
Shopify orders and invoices, and send them into chats, ChatGPT among them. The
job is to get the right screenshot, with private details covered, into the
right chat in as few moves as possible.

## Product Purpose

Snapfly hangs every screenshot on a line at the top of the screen. From there
it can be copied, sent straight into the app in front, combined, translated,
described or searched. Screenshots don't pile up on the Desktop. Success means
the screenshot is in the chat, covered where it should be, and the line holds
only what is still to send.

## Positioning

The line itself: a physical metaphor that sits out of the way above every app
and comes down when needed. It is built for sending into a chat. That means a
paper plane on each photo and ⌃⌥V, private details covered before anything
leaves, and photos that leave the line once sent.

## Operating Context

- A menu bar accessory with no Dock icon. The line is a non-activating panel,
  so the app the user is typing in stays in front.
- The user works in another app, usually a chat. Snapfly must never steal
  focus from it when sending.
- The user has shortcuts: ⌃⌥T shows the line, ⌃⌥V sends, ⌃⌥F searches,
  ⌃⌥S takes a screenshot from Snapfly itself and ⌃⌥R starts or stops a screen
  recording. Settings opens from the menu bar.

## Capabilities and Constraints

- macOS 14 and later, universal binary. Some features need newer systems:
  - Liquid Glass and FoundationModels need macOS 26.
  - Translation needs macOS 15.
- No server. Text recognition, covering, translation and descriptions all run
  on the Mac.
- 13 languages, including right-to-left Arabic. The interface must hold up in
  German (long words) and in Arabic (RTL).
- Builds come from GitHub Actions only. Nobody can run the app here, so
  visual changes ship unseen until the owner tries the build.
- Eight line styles: clothesline, glass shelf, island, card stack, wire,
  floating, filmstrip and fan. Every feature must work in all eight.

## Brand Commitments

- The name is **Snapfly**.
- The icon is a screenshot card taking off up and to the right, on a gradient
  from amber through coral to violet (`assets/icon.png`, drawn by
  `scripts/make-icon.py`).
- The app names no other project. The MIT notice travels in `LICENSE` inside
  the app, and the website's footer credits Tendedero.
- Voice: plain and short. German copy addresses the reader as "du".

## Evidence on Hand

- `README.md` describes every gesture and feature.
- There are no testimonials, customer counts or benchmarks. Never invent them.

## Product Principles

1. Sending is the main act: the shortest path from a screenshot to a chat wins.
2. Never take focus from the app in front.
3. Private by default: nothing leaves without the chosen covering, and nothing
   leaves the Mac.
4. Quiet until needed. The line stays tucked away and nothing nags.
5. One feature, every style. A capability added for one line style must work
   in all of them.

## Plans

- Everything in Snapfly is free for now.
- Pro, a subscription, comes later. It adds the features listed in
  `Shared/Plan.swift` for people who send orders and receipts every day: the
  order binder, the send log, the order card, covering profiles, saved
  messages and the hand-off to bookkeeping. Each is built free first.
- Nothing is held back until the owner sets the day Pro begins
  (`Plan.proStarts`). Whoever used Snapfly before that day keeps every
  feature.
- Covering private details, of every kind, is never Pro, and neither is
  anything Snapfly does today.
- Pro needs no account, no server and no tracking.
- At most one note about Pro a day, and never a badge on the line.

## Accessibility & Inclusion

- Every icon-only control needs a spoken label.
- Must hold up with Increase Contrast, Reduce Transparency and Reduce Motion.
- Must hold up in right-to-left languages.

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
- Pro, a subscription by the year or the month, comes later. It adds the
  features listed in `Shared/Plan.swift` for people who send orders and
  receipts every day, in the three groups the Pro screen shows
  (`ProCatalog`): orders and receipts (the order binder, the order card,
  the send log, saved messages, the hand-off to bookkeeping, the shop
  header), pictures and videos (drawing and cropping, backgrounds, Studio,
  step-by-step guides), and sharing and routines (share links, covering
  profiles, covering a folder, AI apps). Each is built free first.
- Nothing is held back until the owner sets the day Pro begins
  (`Plan.proStarts`). Whoever used Snapfly before that day keeps every
  feature.
- Covering private details, of every kind, is never Pro, and neither is
  anything Snapfly does today.
- Pro needs no account, no server and no tracking.
- **The Pro screen** (November 2026) is built and waits for that day: a
  window on the Mac, a full screen on the iPhone. A locked feature opens
  it (below), and so, once Pro has begun, do Settings › About on the Mac
  and More › Features on the iPhone; nothing else does. It says what Pro
  adds, the price as the App Store gives it, what is billed and when it
  renews, before its one Subscribe button, and that covering stays free.
- **Once a day, then a note** (decided November 2026). The first locked
  feature chosen on a day opens the Pro screen; for the rest of that day a
  note says so instead ("Studio is part of Snapfly Pro."), and a click on
  it opens the screen (`ProNudge`). What runs on its own (covering a
  folder, Studio after a recording, the AI apps' server) stays still and
  says nothing. Never a badge on the line.
- **The website's edition cannot subscribe.** Pro is bought in Snapfly
  from the Mac App Store and on the iPhone. The download from the website
  never asks the App Store; its Pro window says where Pro is bought.
- **Apple sells it.** One subscription group, Snapfly Pro, with a yearly
  and a monthly plan (`ProProducts`). Apple is the seller: it takes the
  payment and handles renewing, cancelling, withdrawal and refunds
  through the Apple account. One subscription opens Pro on the Mac and the
  iPhone with the same Apple account. Prices come only from the App Store;
  the yearly plan's "Saves N%" is worked out from its two prices and shown
  only from 5%.
- **The legal links** are always on the Pro screen: Terms of Use, Privacy
  Policy and Withdrawal Policy (the website's pages, in English, German or
  Arabic as Snapfly shows), Withdraw from Contract (Apple's own withdrawal
  online) and Cancel Subscription (the App Store's subscriptions). Every
  page of the website links to the same terms and withdrawal pages.

## Accessibility & Inclusion

- Every icon-only control needs a spoken label.
- Must hold up with Increase Contrast, Reduce Transparency and Reduce Motion.
- Must hold up in right-to-left languages.

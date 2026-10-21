# Scan audit, before clean scans

What the iPhone's Scan tab did before clean scans were added (October
2026), read from the code, and what the upgrade builds on. Nothing here was
run on a device; it is what the code says.

## Targets

- iPhone app: iOS 17.0 (`IPHONEOS_DEPLOYMENT_TARGET` in
  `iOS/Snapfly.xcodeproj`), Swift 5 language mode, built with the iOS 26 SDK
  in CI. Unchanged.
- Mac app and the shared code: macOS 14 (`Package.swift`). Code in
  `Sources/Tendedero/Shared` is compiled by both apps and by `swift test`
  on GitHub's Macs.

## The scan flow

| Step | Where | What it does |
|---|---|---|
| Open | `ScanTab.swift`, `ScanCard` | "Scan a document", the green Scan Document pill, disabled with a note where `VNDocumentCameraViewController.isSupported` is false. The first run's Try It Now opens the camera through `AppTabs.scanRequested`. |
| Capture | `DocumentScanner` (VisionKit) | The system's document camera, full screen. It finds the page, straightens and crops it, and can filter it itself. `imageOfPage(at:)` gives one upright `CGImage` per page. No original photo is handed over. |
| Keep | `ScannedPages` | Pages in memory only, in the order scanned, never written to disk. Each page keeps the `ProtectSession` it was opened with. |
| Open one | `ProtectView(source: .scanned(id))` | One page opens straight in Protect Picture; several wait under "Scanned pages" as square cards, numbered, with the shield once their copy is checked. |
| Cover | `ProtectSession` | The same engine as screenshots: `Finder.analysis` (patterns, labels, names, the owner's details and rules, Apple Intelligence or the AI assistant where on), the copy made by `Finder.finish`, read again and checked by `Finder.coversHold`, ink where a look let something through. Nothing leaves before the copy is checked. |
| Send | `ScannedPages.send(to:)` | Covers every page (an opened page as it was left, once checked; any other with `Covering.cover`, as Settings says) and hands the PNGs to an app (`Handoff`). |
| PDF | `ScannedPages.sharePDF()`, `ScanPDF` | Covers every page the same way, then one PDF: each page the picture's own shape, its short side A4's 595.28 pt, a JPEG at 0.82, at most 3508 px; pictures only, no text; `kCGPDFContextCreator` "Snapfly". The share sheet opens with it. |

## The editor

`ProtectView` with `ProtectSession`, `MarkCanvas`, `EditorParts`:

- Over the page, the status capsule (`PrivacyStatus`) and the eye, held to see
  the picture as it was.
- Beside it, the app rail (`AppRail`): the apps chosen, Photos, Files, Share.
- Under it, one bar of tools (`EditingDock`): Select, Marker, Box, Lasso,
  Eraser, Undo, Redo; a long press gives widths and sizes.
- The menu: Explain (the AI assistant), Details (`ReviewSheet`), Copy, Send
  to Mac, Full Screen, the choice of apps, Clear Hidden by Hand, Reset to
  Suggestions.
- Every way out waits for the checked copy and asks first while places are
  still to check.

## Where results go

- Scanned pages stay in memory in the Scan tab for as long as the app runs.
  Covered copies leave only through the share sheet, Files, Photos or an
  app. Nothing is kept by Snapfly afterwards.
- The Protected tab lists screenshots from Photos only (`Recent`, by their
  place in Photos). A scanned page never appears there, so no file made
  without covers can be shown there as protected.
- The shield on a page card means its covered copy is made and checked.

## Photos

- The Photos tab already opens a picture chosen with the system's picker
  (`PhotosPicker`) in Protect Picture as `.picture(id)` (`Imported`). Photos
  of documents are not straightened or cleaned there.

## Words that change

- "Letters, forms and receipts, straight from the camera. Private details
  are covered on this iPhone before anything leaves it." No longer true once
  a page can be saved without covers. Replaced by the brief's description.
- "Hold your iPhone over the page; it is found and taken by itself." Gets a
  full stop for the semicolon.
- "Check the places, then copy, share or save the covered page." Becomes
  "…save the page as a PDF or a picture".
- "Share Covered PDF" and its footnote ("The PDF holds only pictures of the
  covered pages, no text to copy") give way to Save and Share.

## What the upgrade builds on

- The same camera, the same `ScannedPages`, the same editor and engine: the
  page the engine reads is the cleaned page, so covers are placed in its
  coordinates and drawn into it.
- `ScanPDF` becomes the writer of A4 PDFs with an optional text layer, in
  the same file.
- The camera can't hand over the photo it took, so for camera pages "Before"
  is the page as the camera gave it; for photos, the page straightened, before
  its light is cleaned. Both sides then line up while comparing.

# Logos beside the paper plane

The logos of WhatsApp, Gmail, GMX and WEB.DE that the row under a photo
shows (`ChatTarget.logo`). The owner supplied them as SVG (`source/`, from
SVG Repo); the PNGs are those SVGs drawn at 192 × 192 px with a transparent
background (headless Chromium: the SVG in an `<img>` of that size,
`--default-background-color=00000000`, then cropped to 192 × 192).
`scripts/build-app.sh` copies the PNGs into the app as `chat-logos/`.

The logos belong to their owners (Google, WhatsApp, United Internet). They
only say where a photo goes. ChatGPT and Claude have no logo here on
purpose: their icons come from the apps on the Mac.

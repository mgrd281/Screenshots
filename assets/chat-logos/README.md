# Logos beside the paper plane

The logos that the row under a photo shows for every chat but ChatGPT and
Claude (`ChatTarget.logo`). The owner supplied them as SVG (`source/`, from
SVG Repo, and for Grok, DeepSeek and Perplexity as pictures, which are
only scaled to 192 × 192 px, their white corners made transparent); the
PNGs are those SVGs drawn at 192 × 192 px with a transparent
background (headless Chromium: the SVG in an `<img>` of that size,
`--default-background-color=00000000`, then cropped to 192 × 192).
`scripts/build-app.sh` copies the PNGs into the app as `chat-logos/`.

The logos belong to their owners (Google, WhatsApp, United Internet, Microsoft, Yahoo, Meta, xAI, DeepSeek, Perplexity). They
only say where a photo goes. ChatGPT and Claude have no logo here on
purpose: their icons come from the apps on the Mac.

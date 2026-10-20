# Logos beside the paper plane

The logos that the row under a photo shows for every chat but ChatGPT and
Claude (`ChatTarget.logo`). The owner supplied them as SVG (`source/`, from
SVG Repo, and for Grok, DeepSeek, Perplexity, Antigravity and Qwen as
pictures, which are only cropped to the mark and scaled to 192 × 192 px,
the white round them made transparent; Qwen keeps the white inside its
mark); the
PNGs are those SVGs drawn at 192 × 192 px with a transparent
background (headless Chromium: the SVG in an `<img>` of that size,
`--default-background-color=00000000`, then cropped to 192 × 192).
Airbnb's SVG keeps only its mark: its view box leaves out the word
under it. `scripts/build-app.sh` copies the PNGs into the app as `chat-logos/`.

The logos belong to their owners (Google, WhatsApp, United Internet, Microsoft, Yahoo, Meta, xAI, DeepSeek, Perplexity, Airbnb, Alibaba). They
only say where a photo goes. ChatGPT and Claude have no logo here on
purpose: their icons come from the apps on the Mac.

The iPhone's first run shows ChatGPT, WhatsApp and WEB.DE in its picture of
the share sheet as their apps' icons, as SVG in its asset catalogue
(`iOS/Snapfly/Assets.xcassets/Logo*.imageset`), kept as vectors:
WhatsApp's and WEB.DE's from `source/` (WhatsApp's with its rounded corners
and the `<use>` it was drawn with left out, as the app clips the icon
itself), and ChatGPT's the OpenAI mark from Simple Icons (CC0), white on
black as the ChatGPT app's icon is. OpenAI owns that mark too.

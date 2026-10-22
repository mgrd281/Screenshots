// Renders the motion graphic to MP4: steps promo-<lang>.html through its
// timeline at 30 frames a second and pipes every frame into ffmpeg.
//
//   node promo/render.js            all three languages
//   node promo/render.js de         one language
//   node promo/render.js de --stills 1,3.5,9   a few frames as PNGs, to look at
//   node promo/render.js ad --audio mix.m4a    the Instagram ad (ad-de.html), with its sound
//   node promo/render.js ad-long --audio mix.m4a   its long cut (ad-long-de.html)
//   node promo/render.js ad-neu --audio mix.m4a    the newest cut, with the iPhone (ad-neu-de.html)
//
// Needs Playwright (with its Chromium) and ffmpeg.
const path = require("path");
const { spawn } = require("child_process");
const { chromium } = require(process.env.PLAYWRIGHT || "playwright");

const here = __dirname;
const fps = 30;
const args = process.argv.slice(2);
const stillsAt = args.includes("--stills") ? args[args.indexOf("--stills") + 1].split(",").map(Number) : null;
const langs = args.filter((a) => /^(en|de|ar)$/.test(a));
const audio = args.includes("--audio") ? path.resolve(args[args.indexOf("--audio") + 1]) : null;
// The ads are German only; the motion graphic comes in three languages.
const ad = ["ad-long", "ad-neu", "ad"].find((a) => args.includes(a)) || null;
const isAd = ad !== null;
const pages = isAd ? [["de", `${ad}-de.html`, `Snapfly-${ad}-de.mp4`]]
  : (langs.length ? langs : ["en", "de", "ar"]).map((l) => [l, `promo-${l}.html`, `Snapfly-${l}.mp4`]);
const out = process.env.OUT || path.join(here, "out");

(async () => {
  require("fs").mkdirSync(out, { recursive: true });
  const browser = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
  for (const [lang, html, name] of pages) {
    const page = await (await browser.newContext({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 })).newPage();
    await page.goto("file://" + path.join(here, html));
    await page.waitForFunction(() => window.READY === true);
    if (stillsAt) {
      for (const t of stillsAt) {
        await page.evaluate((t) => window.seek(t), t);
        await page.screenshot({ path: path.join(out, `still-${isAd ? ad + "-" : ""}${lang}-${String(t).replace(".", "_")}.png`) });
      }
      continue;
    }
    const duration = await page.evaluate(() => window.DURATION);
    const file = path.join(out, name);
    const sound = audio ? ["-i", audio, "-map", "0:v", "-map", "1:a", "-c:a", "aac", "-b:a", "192k", "-shortest"] : [];
    const ffmpeg = spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(fps), "-i", "-", ...sound,
      "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", file],
      { stdio: ["pipe", "inherit", "inherit"] });
    const frames = Math.round(duration * fps);
    for (let i = 0; i < frames; i++) {
      await page.evaluate((t) => window.seek(t), i / fps);
      const shot = await page.screenshot({ type: "jpeg", quality: 95 });
      if (!ffmpeg.stdin.write(shot)) await new Promise((r) => ffmpeg.stdin.once("drain", r));
    }
    ffmpeg.stdin.end();
    await new Promise((r) => ffmpeg.on("close", r));
    console.log("Rendered", path.relative(process.cwd(), file));
  }
  await browser.close();
})();

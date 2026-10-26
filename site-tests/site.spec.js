// The website's pages, languages, the look switch (classic, bold),
// the theme switcher and Reduce Motion, checked in a real browser. These
// tests read the site; they never change it.
const { test, expect } = require("@playwright/test");

const pages = ["", "privacy.html", "support.html"];
const languages = [["", "en", "ltr"], ["de/", "de", "ltr"], ["ar/", "ar", "rtl"]];
const themes = ["sunset", "emerald", "orange"];

// A visitor who already chose a language, so the first-visit redirect stays out of the way.
test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    try { if (!localStorage.getItem("snapfly-lang")) localStorage.setItem("snapfly-lang", "x"); } catch (e) {}
  });
});

function watchErrors(page) {
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  page.on("request", (r) => { if (!r.url().startsWith("http://127.0.0.1:4173/") && !r.url().startsWith("data:") && !r.url().startsWith("blob:")) errors.push("other host: " + r.url()); });
  return errors;
}

const brandOf = (page) => page.evaluate(() => document.documentElement.dataset.brand || "sunset");

for (const [dir, lang, direction] of languages) for (const path of pages) {
  test(`${lang} ${path || "home"} loads cleanly`, async ({ page }) => {
    const errors = watchErrors(page);
    await page.goto(dir + path, { waitUntil: "networkidle" });
    await expect(page.locator("html")).toHaveAttribute("lang", lang);
    await expect(page.locator("html")).toHaveAttribute("dir", direction);
    await expect(page.locator("h1")).toBeVisible();
    // Down to the end, so every section has arrived.
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(300);
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth), "no sideways scroll").toBeLessThanOrEqual(0);
    expect(errors).toEqual([]);
  });
}

const lookOf = (page) => page.evaluate(() => document.documentElement.dataset.look || "classic");
const edgeOf = (page) => page.evaluate(() => getComputedStyle(document.body, "::after").content);

for (const look of ["classic", "bold"]) for (const [dir, lang] of languages) for (const path of ["", "privacy.html"]) {
  test(`${lang} ${path || "home"} loads cleanly in the ${look} look`, async ({ page }) => {
    await page.addInitScript((l) => { try { localStorage.setItem("snapfly-look", l); } catch (e) {} }, look);
    const errors = watchErrors(page);
    await page.goto(dir + path, { waitUntil: "networkidle" });
    expect(await lookOf(page)).toBe(look);
    await expect(page.locator("h1")).toBeVisible();
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(300);
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth), "no sideways scroll").toBeLessThanOrEqual(0);
    expect(errors).toEqual([]);
  });
}

test("the Mac desktop look is the default, and there is no airmail look", async ({ page }) => {
  await page.goto("");
  expect(await lookOf(page)).toBe("classic");
  await expect(page.locator(".look-switch")).toHaveAttribute("role", "radiogroup");
  await expect(page.locator(".look-chip")).toHaveCount(2);
  await expect(page.locator('.look-chip[aria-checked="true"]')).toHaveAttribute("data-look-pick", "classic");
  expect(await edgeOf(page), "no chevron edge").toBe("none");
  await expect(page.locator(".airmail")).toBeHidden();
});

test("the classic look is kept from the first paint, in every theme", async ({ page }) => {
  await page.addInitScript(() => {
    document.addEventListener("DOMContentLoaded", () => { window.__first = document.documentElement.dataset.look || "classic"; });
  });
  const errors = watchErrors(page);
  await page.goto("de/", { waitUntil: "networkidle" });
  await page.locator('[data-look-pick="bold"]').click();
  await expect.poll(() => lookOf(page)).toBe("bold");
  await page.locator('[data-look-pick="classic"]').click();
  await expect.poll(() => lookOf(page)).toBe("classic");
  expect(await page.evaluate(() => localStorage.getItem("snapfly-look"))).toBe("classic");
  expect(await edgeOf(page), "no chevron edge").toBe("none");
  await page.reload({ waitUntil: "networkidle" });
  expect(await page.evaluate(() => window.__first)).toBe("classic");
  // The themes still change the classic look, and its own menu bar colour.
  await page.locator('[data-brand-pick="orange"]').click();
  await expect.poll(() => brandOf(page)).toBe("orange");
  expect(await lookOf(page)).toBe("classic");
  await expect(page.locator('meta[name="theme-color"]').first()).toHaveAttribute("content", "#FAFAF8");
  expect(errors).toEqual([]);
});

test("choosing the bold look is kept from the first paint, with its band running", async ({ page }) => {
  await page.addInitScript(() => {
    document.addEventListener("DOMContentLoaded", () => { window.__first = document.documentElement.dataset.look || "classic"; });
  });
  const errors = watchErrors(page);
  await page.goto("ar/", { waitUntil: "networkidle" });
  await expect(page.locator(".marquee")).toBeHidden();
  await page.locator('[data-look-pick="bold"]').click();
  await expect.poll(() => lookOf(page)).toBe("bold");
  expect(await page.evaluate(() => localStorage.getItem("snapfly-look"))).toBe("bold");
  expect(await edgeOf(page), "no chevron edge").toBe("none");
  await expect(page.locator(".marquee")).toBeVisible();
  await expect(page.locator(".postmark").first()).toBeHidden();
  await page.reload({ waitUntil: "networkidle" });
  expect(await page.evaluate(() => window.__first)).toBe("bold");
  // The band of what a screenshot can do runs, and only screen readers skip it.
  expect(await page.locator(".marquee-track").evaluate((e) => e.getAnimations().map((a) => a.animationName))).toEqual(["bold-run-rtl"]);
  await expect(page.locator(".marquee")).toHaveAttribute("aria-hidden", "true");
  // Each theme brings its own field, and its menu bar colour.
  await page.locator('[data-brand-pick="orange"]').click();
  await expect.poll(() => brandOf(page)).toBe("orange");
  expect(await lookOf(page)).toBe("bold");
  await expect(page.locator('meta[name="theme-color"]').first()).toHaveAttribute("content", "#EC632C");
  expect(await page.locator(".hero").evaluate((e) => getComputedStyle(e).backgroundColor)).toBe("rgb(236, 99, 44)");
  expect(errors).toEqual([]);
});

test("the arrows move between the looks", async ({ page }) => {
  await page.goto("", { waitUntil: "networkidle" });
  await page.locator('.look-chip[aria-checked="true"]').focus();
  await page.keyboard.press("ArrowRight");
  await expect.poll(() => lookOf(page)).toBe("bold");
  await page.keyboard.press("ArrowRight");
  await expect.poll(() => lookOf(page)).toBe("classic");
  await page.keyboard.press("ArrowLeft");
  await expect.poll(() => lookOf(page)).toBe("bold");
});

test("Original Sunset is the default", async ({ page }) => {
  await page.goto("");
  expect(await brandOf(page)).toBe("sunset");
  await expect(page.locator(".brand-switch")).toHaveAttribute("role", "radiogroup");
  await expect(page.locator(".brand-chip")).toHaveCount(3);
  await expect(page.locator('.brand-chip[aria-checked="true"]')).toHaveAttribute("data-brand-pick", "sunset");
});

for (const [i, theme] of themes.entries()) {
  test(`choosing ${theme} is kept from the first paint`, async ({ page }) => {
    // Start on another theme, so the choice is a change.
    await page.addInitScript((before) => {
      try { if (!localStorage.getItem("snapfly-brand")) localStorage.setItem("snapfly-brand", before); } catch (e) {}
      document.addEventListener("DOMContentLoaded", () => { window.__first = document.documentElement.dataset.brand || "sunset"; });
    }, themes[(i + 1) % themes.length]);
    const errors = watchErrors(page);
    await page.goto("de/", { waitUntil: "networkidle" });
    await page.locator(`[data-brand-pick="${theme}"]`).click();
    await expect.poll(() => brandOf(page)).toBe(theme);
    expect(await page.evaluate(() => localStorage.getItem("snapfly-brand"))).toBe(theme);
    await expect(page.locator('.brand-chip[aria-checked="true"]')).toHaveAttribute("data-brand-pick", theme);
    await page.reload({ waitUntil: "networkidle" });
    expect(await page.evaluate(() => window.__first)).toBe(theme);
    expect(errors).toEqual([]);
  });
}

test("the arrows move through the themes and wrap round", async ({ page }) => {
  await page.goto("", { waitUntil: "networkidle" });
  await page.locator('.brand-chip[aria-checked="true"]').focus();
  for (const expected of ["emerald", "orange", "sunset"]) {
    await page.keyboard.press("ArrowRight");
    await expect.poll(() => brandOf(page)).toBe(expected);
  }
  await page.keyboard.press("ArrowLeft");
  await expect.poll(() => brandOf(page)).toBe("orange");
});

test("in Arabic the arrows follow the reading direction", async ({ page }) => {
  await page.goto("ar/", { waitUntil: "networkidle" });
  await page.locator('.brand-chip[aria-checked="true"]').focus();
  await page.keyboard.press("ArrowLeft");
  await expect.poll(() => brandOf(page)).toBe("emerald");
});

test("another open tab follows the theme", async ({ page, context }) => {
  await page.goto("", { waitUntil: "networkidle" });
  const other = await context.newPage();
  await other.goto("de/", { waitUntil: "networkidle" });
  await page.locator('[data-brand-pick="emerald"]').click();
  await expect.poll(() => brandOf(other)).toBe("emerald");
});

test.describe("with Reduce Motion", () => {
  test("nothing moves, and nothing waits to arrive", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto("de/", { waitUntil: "networkidle" });
    // Whatever would move, blur or turn is cut to an instant; fades may play.
    const moving = await page.evaluate(() => document.getAnimations().filter((a) => {
      const keys = a.effect.getKeyframes().flatMap((k) => Object.keys(k));
      return keys.some((key) => !["offset", "computedOffset", "easing", "composite", "opacity"].includes(key)) && a.effect.getComputedTiming().duration > 1;
    }).map((a) => `${a.animationName || a.transitionProperty} on ${a.effect.target.className.baseVal ?? a.effect.target.className}`));
    expect(moving).toEqual([]);
    expect(await page.locator(".pre").count()).toBe(0);
    await page.waitForTimeout(1500);
    for (const selector of ["h1", ".hero-sub", ".chat", ".peg", ".line-tag"]) {
      expect(await page.locator(selector).first().evaluate((e) => getComputedStyle(e).opacity), selector).toBe("1");
    }
  });

  test("in the bold look nothing moves either, and the band stands still", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.addInitScript(() => { try { localStorage.setItem("snapfly-look", "bold"); } catch (e) {} });
    await page.goto("", { waitUntil: "networkidle" });
    expect(await lookOf(page)).toBe("bold");
    const moving = await page.evaluate(() => document.getAnimations().filter((a) => {
      const keys = a.effect.getKeyframes().flatMap((k) => Object.keys(k));
      return keys.some((key) => !["offset", "computedOffset", "easing", "composite", "opacity"].includes(key)) && a.effect.getComputedTiming().duration > 1;
    }).map((a) => `${a.animationName || a.transitionProperty} on ${a.effect.target.className.baseVal ?? a.effect.target.className}`));
    expect(moving).toEqual([]);
    expect(await page.locator(".marquee-track").evaluate((e) => getComputedStyle(e).animationName)).toBe("none");
    expect(await page.locator(".pre").count()).toBe(0);
  });

  test("a new theme comes at once", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto("de/", { waitUntil: "networkidle" });
    const after = await page.evaluate(() => {
      document.querySelector('[data-brand-pick="emerald"]').click();
      return { brand: document.documentElement.dataset.brand, revealing: document.documentElement.classList.contains("brand-reveal") };
    });
    expect(after).toEqual({ brand: "emerald", revealing: false });
  });
});

test("a new theme spreads from the swatch that was chosen", async ({ page }) => {
  await page.goto("de/", { waitUntil: "networkidle" });
  const during = await page.evaluate(() => new Promise((resolve) => {
    const chip = document.querySelector('[data-brand-pick="orange"]');
    const box = chip.getBoundingClientRect();
    chip.click();
    requestAnimationFrame(() => requestAnimationFrame(() => resolve({
      x: parseFloat(document.documentElement.style.getPropertyValue("--reveal-x")),
      chip: box.left + box.width / 2,
      revealing: document.getAnimations().some((a) => a.animationName === "brand-reveal"),
    })));
  }));
  expect(during.revealing).toBe(true);
  expect(Math.abs(during.x - during.chip)).toBeLessThan(1);
  // Afterwards nothing is left behind.
  await expect.poll(() => page.evaluate(() => document.documentElement.classList.contains("brand-reveal") || document.documentElement.getAttribute("style")), { timeout: 3000 }).toBeFalsy();
  expect(await brandOf(page)).toBe("orange");
});

test("an answer opens and closes", async ({ page }) => {
  await page.goto("support.html", { waitUntil: "networkidle" });
  const faq = page.locator(".faq").first();
  const height = () => faq.evaluate((d) => d.getBoundingClientRect().height);
  const closed = await height();
  await faq.locator("summary").click();
  await expect.poll(height).toBeGreaterThan(closed + 20);
  await expect(faq).toHaveAttribute("open", "");
  await faq.locator("summary").click();
  await expect.poll(height).toBeLessThan(closed + 1);
});

test("the photos sway only while their line is on screen", async ({ page }) => {
  await page.goto("de/", { waitUntil: "networkidle" });
  const state = () => page.locator(".line .peg").first().evaluate((p) => getComputedStyle(p).animationPlayState.split(", ").pop());
  await expect.poll(state).toBe("running");
  await page.evaluate(() => scrollTo({ top: document.body.scrollHeight, behavior: "instant" }));
  await expect.poll(state).toBe("paused");
  await page.evaluate(() => scrollTo({ top: 0, behavior: "instant" }));
  await expect.poll(state).toBe("running");
});

test("the four steps hang on a line on a wide screen, and stack on a phone", async ({ page }, info) => {
  await page.goto("de/", { waitUntil: "networkidle" });
  const rope = await page.locator(".steps-rope").evaluate((r) => getComputedStyle(r).display);
  const tilts = await page.locator(".step").evaluateAll((steps) => steps.map((s) => getComputedStyle(s).rotate));
  if (info.project.name === "desktop") {
    expect(rope).toBe("block");
    expect(tilts.every((t) => t !== "none")).toBe(true);
  } else {
    expect(rope).toBe("none");
    expect(tilts.every((t) => t === "none")).toBe(true);
  }
});

// WCAG asks for a target 24 pt square; with a mouse the switches' cells reach
// a point past their edges, so the pointer over that point still picks them.
test("a mouse picks each look and brand chip 24 pt tall", async ({ page }, info) => {
  test.skip(info.project.name !== "desktop", "a mouse is the desktop project's pointer");
  await page.goto("", { waitUntil: "networkidle" });
  const reach = await page.evaluate(() => [...document.querySelectorAll(".look-chip, .brand-chip")].map((chip) => {
    const r = chip.getBoundingClientRect();
    const x = r.left + r.width / 2;
    const hit = (y) => { const el = document.elementFromPoint(x, y); return !!el && chip.contains(el); };
    return { name: chip.getAttribute("aria-label"), above: hit(r.top - 0.5), below: hit(r.bottom + 0.5) };
  }));
  expect(reach.length).toBe(5);
  for (const chip of reach) expect.soft(chip.above && chip.below, chip.name).toBe(true);
});

// Sending photos copies their pictures into the chat. A copy keeps the ids
// of the picture, so the page must rename them: two of one id is invalid, and
// a gradient would point at whichever copy comes first.
test("the page keeps its ids unique after the photos are sent", async ({ page }, info) => {
  await page.goto("", { waitUntil: "networkidle" });
  const send = page.locator("[data-send-all]").first();
  if (info.project.name !== "desktop") await send.scrollIntoViewIfNeeded();
  await send.click();
  await page.waitForTimeout(2500);
  const repeated = await page.evaluate(() => {
    const ids = [...document.querySelectorAll("[id]")].map((el) => el.id);
    return ids.filter((id, i) => ids.indexOf(id) !== i);
  });
  expect(repeated).toEqual([]);
});

// The Hide Part window is drawn as the app opens it: the picture on its
// canvas beside the choices on the trailing edge, which move under it on a
// phone. In Arabic the trailing edge is the left.
for (const [dir, lang] of [["", "en"], ["ar/", "ar"]]) {
  test(`${lang}: the Hide Part window keeps the picture beside its choices, or over them on a phone`, async ({ page }, info) => {
    await page.goto(dir, { waitUntil: "networkidle" });
    // Both measured in one frame: the window may still be arriving.
    const { canvas, side } = await page.evaluate(() => {
      const box = (selector) => {
        const r = document.querySelector(selector).getBoundingClientRect();
        return { x: r.x, y: r.y, width: r.width, height: r.height };
      };
      return { canvas: box(".hide-canvas"), side: box(".hide-side") };
    });
    if (info.project.name === "desktop") {
      expect(Math.abs(canvas.y - side.y)).toBeLessThan(2);
      if (lang === "ar") expect(side.x + side.width).toBeLessThanOrEqual(canvas.x + 1);
      else expect(side.x).toBeGreaterThanOrEqual(canvas.x + canvas.width - 1);
    } else {
      expect(side.y).toBeGreaterThanOrEqual(canvas.y + canvas.height - 1);
    }
  });
}

// An example covers parts of the receipt and says how many; Done locks the
// picture, and Cancel clears it again.
test("an example covers parts of the receipt, and Done locks it", async ({ page }) => {
  await page.goto("", { waitUntil: "networkidle" });
  const win = page.locator("[data-hide]");
  await win.scrollIntoViewIfNeeded();
  await win.locator("[data-example]").first().click();
  await expect(win.locator(".cover-box").first()).toBeVisible();
  await expect(win.locator("[data-note-text]")).not.toHaveText("");
  await expect(win.locator("[data-remove-all]")).toBeEnabled();
  await win.locator("[data-done]").click();
  await expect(win.locator(".photo-shot")).toHaveClass(/saved/);
  await win.locator("[data-cancel]").click();
  await expect(win.locator(".cover-box")).toHaveCount(0);
});

// The styles section offers the app's eight line styles: each tile sets
// the stage's style, names it in the caption, and shows what holds the
// photos: a wire, a filmstrip, or a fan whose outer photos lean out.
test("every one of the eight line styles can be picked and shows its holder", async ({ page }) => {
  await page.goto("de/", { waitUntil: "networkidle" });
  const stage = page.locator("[data-style-stage]");
  await stage.scrollIntoViewIfNeeded();
  const tiles = page.locator("[data-styles] input");
  expect(await tiles.count()).toBe(8);
  const values = await tiles.evaluateAll((all) => all.map((i) => i.value));
  expect(values).toEqual(["clothesline", "shelf", "island", "stack", "wire", "floating", "filmstrip", "fan"]);
  for (const value of values) {
    const tile = page.locator(`[data-styles] input[value="${value}"]`);
    await tile.evaluate((input) => input.closest("label").click());
    await expect(stage).toHaveAttribute("data-style", value);
    await expect(page.locator("[data-style-caption]")).toHaveText(await tile.getAttribute("data-caption"));
  }
  const shown = async (style, selector) => {
    await page.locator(`[data-styles] input[value="${style}"]`).evaluate((input) => input.closest("label").click());
    await expect.poll(() => page.locator(selector).evaluate((e) => getComputedStyle(e).opacity)).toBe("1");
  };
  await shown("wire", ".style-line .wire");
  await shown("filmstrip", ".style-line .filmstrip");
  await page.locator('[data-styles] input[value="fan"]').evaluate((input) => input.closest("label").click());
  await expect.poll(async () => {
    const [left, right] = await page.locator(".style-line .sty").evaluateAll((all) => [all[0], all[2]].map((s) => parseFloat(getComputedStyle(s).rotate)));
    return left > 0 && right < 0;
  }).toBe(true);
});

// The newest parts (the story, the short words over the titles, the question
// glyphs and the clean ground) show in all three languages, which follow
// together (NEW_PARTS_LANGS in build.py).
for (const [dir, lang] of languages) {
  test(`${lang}: the story, the short words and the clean ground are there`, async ({ page }) => {
    await page.goto(dir, { waitUntil: "networkidle" });
    await expect(page.locator('link[rel="stylesheet"][href$="assets/clean.css"]')).toHaveCount(1);
    await expect(page.locator("[data-story] .beat")).toHaveCount(5);
    // The menu bar's Features leads to the story.
    await expect(page.locator("#features")).toHaveClass(/\bstory\b/);
    // A short word over the title of every section but the privacy band.
    await expect(page.locator(".section .copy > .eyebrow")).toHaveCount(9);
    await expect(page.locator(".section.story .eyebrow")).toBeVisible();
    // Sections between the first view and the close stand on a clean ground.
    expect(await page.locator(".section.send").evaluate((e) => getComputedStyle(e).backgroundColor)).toBe("rgb(255, 255, 255)");
    // The bold look keeps its titles without them.
    await page.locator('[data-look-pick="bold"]').click();
    await expect.poll(() => lookOf(page)).toBe("bold");
    await expect(page.locator(".section.story .eyebrow")).toBeHidden();
  });
}

// English and Arabic say the new parts in their own words, not in German.
test("the new parts are translated, not German", async ({ page }) => {
  const words = async (dir) => {
    await page.goto(dir, { waitUntil: "networkidle" });
    return page.locator(".eyebrow, #story-h, .beat-words h3, .beat-words p").allTextContents();
  };
  const german = await words("de/");
  for (const dir of ["", "ar/"]) {
    const own = await words(dir);
    expect(own.length, dir || "en").toBe(german.length);
    expect(own.filter((w) => german.includes(w)), dir || "en").toEqual([]);
  }
});

// How a screenshot travels: five moments, each a small screen that waits at
// its first frame and plays once when it is well in view; the ones further
// down wait for the eye to get there.
for (const [dir, lang] of languages) {
  test(`${lang}: the story's moments each play once as they come into view`, async ({ page }) => {
    await page.goto(dir, { waitUntil: "networkidle" });
    const order = await page.evaluate(() => [...document.querySelectorAll("main > section")].map((s) => s.classList[1] || s.classList[0]));
    expect(order.slice(1, 4), "first after the first view, then the desktop to try and sending").toEqual(["story", "capture", "send"]);
    const story = page.locator("[data-story]");
    await expect(story).toHaveClass(/staged/);
    const beats = story.locator(".beat");
    await expect(beats).toHaveCount(5);
    const stamp = page.locator(".sc-hang .sc-peg");
    expect(await stamp.evaluate((e) => getComputedStyle(e).opacity), "waits at its first frame").toBe("0");
    await page.locator(".sc-hang").evaluate((e) => e.scrollIntoView({ block: "center", behavior: "instant" }));
    await expect(beats.nth(1)).toHaveClass(/play/);
    await expect.poll(() => stamp.evaluate((e) => getComputedStyle(e).opacity), { timeout: 4000 }).toBe("1");
    await expect(beats.nth(4)).not.toHaveClass(/play/);
    // Each scene keeps to its column, scaled as a whole.
    const fits = await page.locator(".scene-fit").evaluateAll((all) => all.map((fit) => {
      const box = fit.getBoundingClientRect(), screen = fit.querySelector(".sc-screen").getBoundingClientRect();
      return Math.abs(box.width - screen.width) < 1 && Math.abs(box.height - screen.height) < 1;
    }));
    expect(fits).toEqual([true, true, true, true, true]);
  });

  test(`${lang}: with Reduce Motion the story shows how each moment ends`, async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto(dir, { waitUntil: "networkidle" });
    await expect(page.locator("[data-story]")).not.toHaveClass(/staged/);
    const opacity = (selector) => page.locator(selector).evaluate((e) => getComputedStyle(e).opacity);
    expect(await opacity(".sc-hang .sc-peg")).toBe("1");
    expect(await opacity(".sc-cover .badge-lock")).toBe("1");
    expect(await opacity(".sc-fly .sc-flier")).toBe("0");
    expect(await opacity(".sc-fly .sc-img")).toBe("1");
    expect(await page.locator(".sc-clear .sc-line").evaluate((e) => getComputedStyle(e).transform)).not.toBe("none");
  });
}

// The story reads from the reading start: in Arabic everything in it is
// mirrored but the keys, which read left to right in every language.
for (const [dir, lang, direction] of [["", "en", "ltr"], ["ar/", "ar", "rtl"]]) {
  test(`${lang}: the story reads from the ${direction === "rtl" ? "right" : "left"}`, async ({ page }, info) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto(dir, { waitUntil: "networkidle" });
    const rtl = direction === "rtl";
    const boxes = await page.evaluate(() => {
      const box = (selector) => {
        const r = document.querySelector(selector).getBoundingClientRect();
        return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, mid: r.left + r.width / 2 };
      };
      return {
        words: box(".beat:first-child .beat-words"), art: box(".beat:first-child .beat-art"),
        screen: box(".sc-take .sc-screen"), keys: box(".sc-take .sc-keys"), cross: box(".sc-take .sc-cross"),
        first: box(".sc-take .sc-keys kbd:first-child"), last: box(".sc-take .sc-keys kbd:last-child"),
        fly: box(".sc-fly .sc-screen"), chat: box(".sc-fly .sc-chat"),
      };
    });
    // The keys sit at the reading start and the drag ends at the other side,
    // clear of them; ⌃ comes first, on the left.
    expect(boxes.keys.mid > boxes.screen.mid, "keys at the reading start").toBe(rtl);
    expect(boxes.cross.mid > boxes.screen.mid, "drag ends at the reading end").toBe(!rtl);
    expect(rtl ? boxes.cross.right <= boxes.keys.left : boxes.keys.right <= boxes.cross.left, "drag's end clear of the keys").toBe(true);
    expect(boxes.first.left).toBeLessThan(boxes.last.left);
    // The chat it flies into sits toward the reading end.
    expect(boxes.chat.mid > boxes.fly.mid, "chat at the reading end").toBe(!rtl);
    // The first moment's words lead: beside the screen on a wide window,
    // over it on a phone.
    if (info.project.name === "desktop") expect(rtl ? boxes.words.left >= boxes.art.right : boxes.words.right <= boxes.art.left).toBe(true);
    else expect(boxes.words.bottom).toBeLessThanOrEqual(boxes.art.top + 1);
  });
}

// Every question on the support page leads with its own glyph, at the
// reading start; the ones that point toward the reading end turn round in
// Arabic.
for (const [dir, lang, direction] of languages) {
  test(`${lang}: every question on the support page has its glyph`, async ({ page }) => {
    await page.goto(dir + "support.html", { waitUntil: "networkidle" });
    const questions = await page.locator(".faq").count();
    expect(questions).toBeGreaterThan(10);
    expect(await page.locator(".faq summary > svg.faq-icon").count()).toBe(questions);
    const first = await page.locator(".faq").first().evaluate((faq) => {
      const icon = faq.querySelector(".faq-icon").getBoundingClientRect(), words = faq.querySelector(".faq-q").getBoundingClientRect();
      return { iconLeft: icon.left, iconRight: icon.right, wordsLeft: words.left, wordsRight: words.right };
    });
    if (direction === "rtl") expect(first.iconLeft).toBeGreaterThanOrEqual(first.wordsRight);
    else expect(first.iconRight).toBeLessThanOrEqual(first.wordsLeft);
    const turned = await page.locator(".faq-icon.turn").evaluateAll((all) => all.map((i) => getComputedStyle(i).transform));
    expect(turned.length).toBe(2);
    for (const t of turned) expect(t).toBe(direction === "rtl" ? "matrix(-1, 0, 0, 1, 0, 0)" : "none");
  });
}

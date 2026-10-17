// The website's pages, languages, the look switch (airmail, classic, bold),
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

const lookOf = (page) => page.evaluate(() => document.documentElement.dataset.look || "airmail");
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

test("the airmail look is the default", async ({ page }) => {
  await page.goto("");
  expect(await lookOf(page)).toBe("airmail");
  await expect(page.locator(".look-switch")).toHaveAttribute("role", "radiogroup");
  await expect(page.locator(".look-chip")).toHaveCount(3);
  await expect(page.locator('.look-chip[aria-checked="true"]')).toHaveAttribute("data-look-pick", "airmail");
  expect(await edgeOf(page), "the chevron edge is drawn").not.toBe("none");
});

test("choosing the classic look is kept from the first paint, in every theme", async ({ page }) => {
  await page.addInitScript(() => {
    document.addEventListener("DOMContentLoaded", () => { window.__first = document.documentElement.dataset.look || "airmail"; });
  });
  const errors = watchErrors(page);
  await page.goto("de/", { waitUntil: "networkidle" });
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
  // And back to airmail.
  await page.locator('[data-look-pick="airmail"]').click();
  await expect.poll(() => lookOf(page)).toBe("airmail");
  expect(await edgeOf(page)).not.toBe("none");
  expect(errors).toEqual([]);
});

test("choosing the bold look is kept from the first paint, with its band running", async ({ page }) => {
  await page.addInitScript(() => {
    document.addEventListener("DOMContentLoaded", () => { window.__first = document.documentElement.dataset.look || "airmail"; });
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
  await expect.poll(() => lookOf(page)).toBe("classic");
  await page.keyboard.press("ArrowRight");
  await expect.poll(() => lookOf(page)).toBe("bold");
  await page.keyboard.press("ArrowRight");
  await expect.poll(() => lookOf(page)).toBe("airmail");
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
  expect(reach.length).toBe(6);
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

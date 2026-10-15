// The website's pages, languages, theme switcher and Reduce Motion, checked
// in a real browser. These tests read the site; they never change it.
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
});

// The Snapfly Instagram ads, 1080 × 1920 in German and timed to their voice:
// a short cut, and a long one that explains more. seek(t) draws the frame at
// t seconds; render.js steps through it at 30 frames a second. DATA is
// written into the page by build.py, with the cut to play. The voice starts
// VO seconds in; every cue below is a moment in the voice, and at() adds VO.
"use strict";

const T = DATA.text;
const VO = 0.2;
document.documentElement.lang = DATA.lang;

// MARK: Timing

const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const prog = (t, a, b) => clamp((t - a) / (b - a));
const lerp = (a, b, x) => a + (b - a) * x;
const outQuart = (x) => 1 - Math.pow(1 - x, 4);
const inOut = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
const outBack = (x) => { const c = 1.7; return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2); };
const swing = (tau, amp = 7, freq = 2.1, damp = 2.6) => (tau <= 0 ? 0 : amp * Math.exp(-damp * tau) * Math.sin(2 * Math.PI * freq * tau));
const at = (s) => s + VO;
// A steady pseudo-random number for item i, so every render is the same.
const rnd = (i, salt = 1) => { const x = Math.sin(i * 12.9898 + salt * 78.233) * 43758.5453; return x - Math.floor(x); };

// MARK: The cuts

// Each cut has its captions and, for each scene, the moments in its voice.
// A scene a cut leaves out is not built.
const CUTS = {
  short: {
    duration: 21.5,
    blocks: [
      { from: 0, to: at(2.85), lines: [[["Schon wieder", 0.05, "small"]], [["30 ", at(0.6), "grad"], ["Screenshots", at(0.95), "grad"]], [["auf dem ", at(1.65), "small"], ["Desktop?", at(2.0)]]] },
      { from: at(2.86), to: at(4.62), lines: [[["Mit Snapfly", at(2.86), "small"]], [["hängt jeder", at(3.55)]], [["Screenshot", at(3.95)]]] },
      { from: at(4.66), to: at(6.3), lines: [[["sofort an", at(4.66), "small"]], [["einer Leine,", at(5.15), "grad"]]] },
      { from: at(6.38), to: at(7.62), lines: [[["oben am", at(6.38), "small"]], [["Bildschirm.", at(6.75), "grad"]]] },
      { from: at(7.81), to: at(9.95), lines: [[["Ein Klick,", at(7.81), "grad"]], [["und er ist", at(8.6)]], [["im Chat.", at(9.05)]]] },
      { from: at(10.15), to: at(12.9), lines: [[["WhatsApp.", at(10.15)]], [["ChatGPT.", at(10.99)]], [["Egal wo.", at(12.09), "grad"]]] },
      { from: at(13.26), to: at(14.9), lines: [[["Namen und", at(13.26), "small"]], [["Kontonummern?", at(13.75), "grad"]]] },
      { from: at(15.1), to: at(16.62), lines: [[["Werden", at(15.1), "small"]], [["automatisch", at(15.35), "grad"]], [["verdeckt.", at(15.95)]]] },
    ],
    desk: { mark: 2.86, rope: 3.6, sweep: 3.85, zoom: [6.3, 7.1], out: [7.45, 7.8], push: 2.8 },
    chat: { in: 7.6, clicks: [7.81, 10.94], gptIn: 10.87, fan: 12.09, out: [12.85, 13.2] },
    doc: { in: [13.05, 13.45], name: 13.3, iban: 13.8, cover: 15.3, lock: 16.0, out: [16.45, 16.8] },
    end: { wall: 16.5, icon: 16.7, word: 16.84, tag: 17.3, free: 17.99, url: 18.9 },
  },
  long: {
    duration: 75.2,
    blocks: [
      { from: 0, to: at(2.64), lines: [[["Schon wieder", 0.05, "small"]], [["30 ", at(0.58), "grad"], ["Screenshots", at(0.95), "grad"]], [["auf dem ", at(1.64), "small"], ["Desktop?", at(1.96)]]] },
      { from: at(3.06), to: at(4.75), lines: [[["Und welcher war", at(3.06), "small"]], [["noch mal der", at(3.85), "small"]], [["richtige?", at(4.11), "grad"]]] },
      { from: at(5.32), to: at(7.0), lines: [[["Mit Snapfly", at(5.32), "small"]], [["hängt jeder", at(5.95)]], [["Screenshot", at(6.43)]]] },
      { from: at(7.05), to: at(9.0), lines: [[["sofort an", at(7.05), "small"]], [["einer Leine,", at(7.6), "grad"]]] },
      { from: at(9.26), to: at(10.3), lines: [[["oben am", at(9.26), "small"]], [["Bildschirm.", at(9.6), "grad"]]] },
      { from: at(10.81), to: at(12.55), lines: [[["Dein ", at(10.81), "small"], ["Desktop", at(11.0), "small"]], [["bleibt", at(11.54)]], [["aufgeräumt.", at(11.78), "grad"]]] },
      { from: at(12.88), to: at(14.05), lines: [[["Neuer", at(12.88), "small"]], [["Screenshot?", at(13.2), "grad"]]] },
      { from: at(14.29), to: at(16.35), lines: [[["Ein Klick", at(14.29), "grad"]], [["auf den Knopf", at(14.73)]], [["am Bildschirmrand.", at(15.4), "small"]]] },
      { from: at(16.53), to: at(17.2), lines: [[["Fertig.", at(16.53), "grad"]]] },
      { from: at(17.57), to: at(19.35), lines: [[["Ein Klick", at(17.57), "grad"]], [["auf den ", at(17.95), "small"], ["Papierflieger,", at(18.1), "small"]]] },
      { from: at(19.49), to: at(20.5), lines: [[["und er ist", at(19.49)]], [["im Chat.", at(19.98)]]] },
      { from: at(20.82), to: at(21.75), lines: [[["Noch", at(20.82), "small"]], [["schneller:", at(21.05), "grad"]]] },
      { from: at(21.94), to: at(24.95), lines: [[["Der Knopf ", at(21.94), "small"], ["über dem Chat", at(22.36), "small"]], [["schickt", at(23.11)]], [["alle Fotos", at(23.48), "grad"]], [["auf einmal.", at(24.2), "small"]]] },
      { from: at(25.18), to: at(28.0), lines: [[["WhatsApp.", at(25.18)]], [["ChatGPT.", at(26.06)]], [["Egal wo.", at(27.3), "grad"]]] },
      { from: at(28.53), to: at(29.5), lines: [[["Und per", at(28.53), "small"]], [["E-Mail?", at(28.85), "grad"]]] },
      { from: at(29.94), to: at(30.95), lines: [[["Genauso", at(29.94)]], [["einfach.", at(30.45), "grad"]]] },
      { from: at(31.41), to: at(32.9), lines: [[["Namen und", at(31.41), "small"]], [["Kontonummern?", at(32.13), "grad"]]] },
      { from: at(33.41), to: at(36.48), lines: [[["Werden", at(33.41), "small"]], [["automatisch", at(33.8), "grad"]], [["verdeckt,", at(34.45)]], [["bevor ", at(34.98), "small"], ["etwas ", at(35.5), "small"], ["rausgeht.", at(35.97), "small"]]] },
      { from: at(36.74), to: at(38.25), lines: [[["Du suchst eine ", at(36.74), "small"], ["alte", at(37.2), "small"]], [["Rechnung?", at(37.75), "grad"]]] },
      { from: at(38.65), to: at(41.85), lines: [[["Snapfly findet", at(38.65), "small"]], [["jedes Wort", at(39.7), "grad"]], [["in deinen ", at(40.5), "small"], ["Screenshots.", at(41.0), "small"]]] },
      { from: at(42.34), to: at(43.82), lines: [[["Mehrere", at(42.34), "small"]], [["Screenshots?", at(42.9), "grad"]]] },
      { from: at(44.05), to: at(45.35), lines: [[["Werden zu", at(44.05), "small"]], [["einem ", at(44.5)], ["PDF.", at(44.75), "grad"]]] },
      { from: at(45.63), to: at(46.55), lines: [[["Fremde", at(45.63), "small"]], [["Sprache?", at(46.1), "grad"]]] },
      { from: at(47.02), to: at(49.32), lines: [[["Wird", at(47.02), "small"]], [["übersetzt,", at(47.25), "grad"]], [["direkt ", at(48.11), "small"], ["auf deinem ", at(48.5), "small"], ["Mac.", at(48.85), "small"]]] },
      { from: at(49.87), to: at(52.5), lines: [[["Was gesendet ist,", at(49.87), "small"]], [["verschwindet", at(50.9), "grad"]], [["von der Leine.", at(51.55), "small"]]] },
      { from: at(52.65), to: at(54.9), lines: [[["Der Verlauf", at(52.65), "small"]], [["hebt es", at(53.42)]], [["30 Tage", at(53.69), "grad"], [" auf.", at(54.15)]]] },
      { from: at(55.38), to: at(59.45), lines: [[["Kein Konto.", at(55.38)]], [["Keine Cloud.", at(56.58)]], [["Alles bleibt ", at(57.91), "small"], ["auf deinem Mac.", at(58.6), "small"]]] },
      { from: at(59.92), to: at(61.4), lines: [[["Und das ist", at(59.92), "small"]], [["nicht alles!", at(60.48), "grad"]]] },
      { from: at(61.6), to: at(62.85), lines: [[["Bildschirm", at(61.6)]], [["aufnehmen,", at(61.95), "grad"]]] },
      { from: at(63.05), to: at(64.6), lines: [[["ganze Seiten", at(63.05)]], [["erfassen,", at(63.7), "grad"]]] },
      { from: at(64.78), to: at(65.7), lines: [[["Zeitstempel", at(64.78), "grad"]]] },
      { from: at(65.76), to: at(66.85), lines: [[["und vieles", at(65.76)]], [["mehr!", at(66.1), "grad"]]] },
    ],
    desk: { hunt: [3.15, 3.75, 4.3], mark: 5.32, rope: 6.0, sweep: 6.2, zoom: [9.26, 10.05], tidy: 10.81, clean: 11.78,
            button: { in: 12.7, click: 14.52, drag: [14.9, 15.55], flash: 15.75, hang: 16.53 }, out: [17.1, 17.45], push: 5.1 },
    chat: { in: 17.2, clicks: [18.1, 23.11], button: true, gptIn: 20.7, fan: 25.18, out: [28.0, 28.35] },
    mail: { in: 28.3, click: 29.94, out: 31.05 },
    doc: { in: [31.15, 31.55], name: 31.41, iban: 32.13, cover: 34.45, lock: 34.98, send: 35.45, out: [36.15, 36.4] },
    search: { in: 36.45, type: 37.75, find: 38.65, zoom: 39.7, out: 41.75 },
    pdf: { in: 41.95, picks: [42.45, 42.75, 43.05], merge: 44.05, badge: 44.75, out: 45.45 },
    translate: { in: 45.5, menu: 46.1, click: 46.65, swap: 47.02, out: 49.5 },
    sent: { in: 49.7, click: 50.25, close: 50.9, history: 52.6, days: 53.69, out: 54.85 },
    privacy: { account: 55.38, cloud: 56.58, mac: 57.91, out: 59.55 },
    more: { hit: 60.48, items: [61.6, 63.05, 64.78, 65.76], out: 66.85 },
    end: { wall: 66.95, icon: 67.1, word: 67.3, tag: 67.8, free: 68.59, url: 69.5, cta: 71.21, boom: 71.72 },
  },
  // About thirty seconds with what came since: the short cut's three scenes,
  // quicker, then the iPhone app that is still to come.
  neu: {
    duration: 30.5,
    blocks: [
      { from: 0, to: at(2.49), lines: [[["Schon wieder", 0.05, "small"]], [["30 ", at(0.6), "grad"], ["Screenshots", at(0.95), "grad"]], [["auf dem ", at(1.6), "small"], ["Desktop?", at(1.9)]]] },
      { from: at(2.96), to: at(4.95), lines: [[["Mit Snapfly", at(2.96), "small"]], [["hängt jeder", at(3.62)]], [["Screenshot", at(4.35)]]] },
      { from: at(5.0), to: at(6.96), lines: [[["sofort an", at(5.0), "small"]], [["einer Leine.", at(5.57), "grad"]]] },
      { from: at(7.39), to: at(9.1), lines: [[["Ein Klick,", at(7.39), "grad"]], [["und er ist", at(8.13)]], [["im Chat.", at(8.55)]]] },
      { from: at(9.72), to: at(12.25), lines: [[["WhatsApp.", at(9.72)]], [["ChatGPT.", at(10.55)]], [["Claude.", at(11.76), "grad"]]] },
      { from: at(12.71), to: at(14.07), lines: [[["Namen und", at(12.71), "small"]], [["Kontonummern?", at(13.3), "grad"]]] },
      { from: at(14.46), to: at(15.95), lines: [[["Werden", at(14.46), "small"]], [["automatisch", at(14.8), "grad"]], [["verdeckt.", at(15.35)]]] },
      { from: at(16.43), to: at(18.03), lines: [[["Und bald auch ", at(16.43), "small"], ["auf dem", at(16.85), "small"]], [["iPhone.", at(17.26), "grad"]]] },
      { from: at(18.32), to: at(19.4), lines: [[["Belege", at(18.32)]], [["scannen,", at(18.8), "grad"]]] },
      { from: at(19.63), to: at(22.5), lines: [[["Fotos und ", at(19.63), "small"], ["PDFs", at(20.28), "small"]], [["zu einem", at(20.75)]], [["Dokument", at(21.0), "grad"]], [["zusammenfügen,", at(21.7), "small"]]] },
      { from: at(22.87), to: at(24.15), lines: [[["und sicher", at(22.87)]], [["teilen.", at(23.69), "grad"]]] },
    ],
    desk: { mark: 2.96, rope: 3.6, sweep: 4.35, zoom: [5.57, 6.3], out: [6.85, 7.2], push: 2.9 },
    chat: { in: 7.0, clicks: [7.45, 10.6], gptIn: 10.4, fan: 11.76, out: [12.45, 12.8] },
    doc: { in: [12.35, 12.75], name: 12.71, iban: 13.3, cover: 14.8, lock: 15.4, out: [16.0, 16.35] },
    phone: { in: 16.2, scanTap: 18.1, camera: 18.3, frame: 18.5, shutter: 18.85, photos: [19.63, 19.9], pdf: 20.28, title: 21.0,
             lift: 21.45, drop: 22.25, saveTap: 22.87, cover: 23.23, shareTap: 23.69, out: [24.25, 24.6] },
    end: { wall: 24.3, icon: 24.45, word: 24.66, tag: 25.1, free: 25.78, soon: 26.45, url: 27.0 },
  },
};
const CUT = CUTS[DATA.cut || "short"];
const DURATION = CUT.duration;

// MARK: Building

function el(tag, cls, parent = document.body, html = "") {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (html) node.innerHTML = html;
  parent.appendChild(node);
  return node;
}
function style(node, s) { Object.assign(node.style, s); }
function show(node, o) { node.style.opacity = o; node.style.visibility = o <= 0.001 ? "hidden" : "visible"; }

const ICON_PLANE = '<svg viewBox="0 0 24 24"><path d="M4.1 11.3 19.6 4.6c.6-.3 1.1.3.9.9l-6.7 15.5c-.3.6-1.1.5-1.3-.1l-2-5.7a1 1 0 0 0-.6-.6L4.2 12.6c-.6-.2-.7-1-.1-1.3Z" fill="#fff"/></svg>';
const ICON_LOCK = '<svg viewBox="0 0 24 24"><rect x="5.5" y="10.5" width="13" height="9.5" rx="2.4" fill="#fff"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5" stroke="#fff" stroke-width="2" fill="none"/></svg>';
const POINTER = '<svg viewBox="0 0 24 24"><path d="M5 3.2v15.6l4.1-3.7 2.6 6 2.7-1.2-2.6-5.9 5.6-.3Z" fill="#000" stroke="#fff" stroke-width="1.3" stroke-linejoin="round"/></svg>';
// Snapfly's mark in the menu bar: a photo hanging from a clip on a line.
const MARK = '<svg viewBox="0 0 24 24"><path d="M.8 4.8Q12 8.3 23.2 4.8" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" fill="none"/><g transform="rotate(-7 12 8)"><rect x="11.1" y="4.9" width="1.8" height="4.6" rx=".7" fill="currentColor"/><rect x="5.3" y="8.8" width="13.4" height="11.5" rx="2.4" stroke="currentColor" stroke-width="2.1" fill="none"/><circle cx="14.9" cy="12.5" r="1.3" fill="currentColor"/><path d="m8.3 17.5 2.8-2.9 3.4 3.2" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" fill="none"/></g></svg>';
const ICON_FIND = '<svg viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6" stroke="currentColor" stroke-width="2.2" fill="none"/><path d="m15 15 5 5" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg>';
const ICON_CHECK = '<svg viewBox="0 0 24 24"><path d="m5 12.5 4.5 4.5L19 7.5" stroke="#fff" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg>';
const ICON_CLOCK = '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5" stroke="currentColor" stroke-width="2.2" fill="none"/><path d="M12 7.5V12l3 2" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" fill="none"/></svg>';
const SPARKLE = '<svg viewBox="0 0 24 24"><path d="M12 1.5c.7 5.6 4.9 9.8 10.5 10.5-5.6.7-9.8 4.9-10.5 10.5C11.3 16.9 7.1 12.7 1.5 12 7.1 11.3 11.3 7.1 12 1.5Z" fill="currentColor"/></svg>';
const line24 = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const ICON_PERSON = line24('<circle cx="12" cy="8.5" r="3.6"/><path d="M4.8 19.5c1.2-3.6 4-5.2 7.2-5.2s6 1.6 7.2 5.2"/>');
const ICON_CLOUD = line24('<path d="M7.2 18.5h10a3.8 3.8 0 0 0 .6-7.55A5.6 5.6 0 0 0 7 9.6a4.45 4.45 0 0 0 .2 8.9Z"/>');
const ICON_REC = line24('<rect x="2.5" y="4.5" width="19" height="13" rx="2"/><path d="M8.5 20.5h7"/><circle cx="12" cy="11" r="3.4" fill="#FF453A" stroke="none"/>');
const ICON_PAGE = line24('<rect x="7" y="2" width="10" height="20" rx="1.8"/><path d="M9.5 6h5M9.5 9h5M9.5 12h3M12 14.5v4.5M10 17.2l2 2 2-2"/>');
const ICON_STOPWATCH = line24('<circle cx="12" cy="13.5" r="7.5"/><path d="M12 9.5v4.2l2.8 1.7M9.5 2.8h5M12 2.8V6"/>');
const ICON_MAC = line24('<rect x="4.5" y="5.5" width="15" height="10" rx="1.6"/><path d="M2.5 18.5h19M10.8 10.2V9.4a1.2 1.2 0 0 1 2.4 0v.8"/><rect x="10" y="10.2" width="4" height="3" rx=".6" fill="currentColor" stroke="none"/>');
const ICON_VIEWFINDER = '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8V5.5A2.5 2.5 0 0 1 5.5 3H8M16 3h2.5A2.5 2.5 0 0 1 21 5.5V8M21 16v2.5a2.5 2.5 0 0 1-2.5 2.5H16M8 21H5.5A2.5 2.5 0 0 1 3 18.5V16"/><rect x="7" y="9" width="10" height="7" rx="1.5"/><circle cx="12" cy="12.5" r="1.8"/></svg>';
const ICON_CROSS = '<svg viewBox="0 0 48 48"><path d="M24 2v18M24 28v18M2 24h18M28 24h18" stroke="#fff" stroke-width="2.5" stroke-linecap="round"/></svg>';
const ICON_PLANE_LINE = '<svg viewBox="0 0 24 24"><path d="M4.1 11.3 19.6 4.6c.6-.3 1.1.3.9.9l-6.7 15.5c-.3.6-1.1.5-1.3-.1l-2-5.7a1 1 0 0 0-.6-.6L4.2 12.6c-.6-.2-.7-1-.1-1.3Z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>';
const ropePath = (w, sag) => `M0 0 Q${w / 2} ${sag * 2} ${w} 0`;
const ropeY = (frac, sag) => 4 * sag * frac * (1 - frac);

// Background: the dark stage with two slow glows, and the wallpaper for the end.
const bg = el("div", "layer"); bg.id = "bg";
const blobA = el("div", "blob", bg); blobA.id = "blobA";
const blobB = el("div", "blob", bg); blobB.id = "blobB";
const wall = el("div", "layer wallpaper");
const wallWash = el("div", "layer"); wallWash.id = "wallWash";

// MARK: Captions

// Each block is lines of chunks; a chunk appears when it is spoken.
const blocks = CUT.blocks.map((b) => {
  const node = el("div", "kin");
  const chunks = [];
  b.lines.forEach((line) => {
    const ln = el("span", "ln" + (line[0][2] === "small" ? " small" : ""), node);
    line.forEach(([text, when, kind]) => {
      const w = el("span", "w" + (kind === "grad" ? " grad" : ""), ln, text);
      chunks.push({ w, when });
    });
  });
  return { node, chunks, from: b.from, to: b.to };
});

// MARK: Scene 1, a Desktop full of screenshots, swept onto the line

const SW = 1000, SH = 660, SX = 40, SY = 650;
const screen = el("div", "screen");
style(screen, { left: `${SX}px`, top: `${SY}px`, width: `${SW}px`, height: `${SH}px` });
el("div", "layer wallpaper", screen);
const mb = el("div", "menubar", screen);
style(el("i", "", mb), { left: "26px", width: "60px" });
style(el("i", "", mb), { left: "112px", width: "110px", opacity: ".6" });
style(el("i", "", mb), { right: "26px", width: "120px", opacity: ".6" });
const markGlow = el("div", "glow", screen);
const mark = el("div", "mark", mb, MARK);
style(mark, { right: "172px" });
style(markGlow, { right: `${172 + 14 - 60}px`, top: `${20 - 60}px` });
const deskRope = el("div", "rope", screen, `<svg width="${SW}" height="100"><path d="${ropePath(SW, 26)}"/></svg>`);
style(deskRope, { left: "0", top: "56px" });
const deskRopePath = deskRope.querySelector("path");
deskRopePath.style.strokeDasharray = 1100;

const FILES = 24, SPOTS = 8;
const files = [];
for (let i = 0; i < FILES; i++) {
  const n = String(10 + ((i * 7) % 50)).padStart(2, "0");
  const f = el("div", "file", screen,
    `<div class="thumb">${DATA.art[i % DATA.art.length]}</div><div class="name">${T.file.replace("{n}", n)}</div>`);
  const col = i % 6, row = Math.floor(i / 6);
  const x = 40 + col * 152 + (rnd(i, 1) - 0.5) * 70;
  const y = 70 + row * 140 + (rnd(i, 2) - 0.5) * 60;
  files.push({ f, x, y, tilt: (rnd(i, 3) - 0.5) * 16, hangTilt: (rnd(i, 4) - 0.5) * 9, spot: i % SPOTS, layer: Math.floor(i / SPOTS) });
}

// The long cut asks "which one was it?": a pointer looks from file to file.
// Later the cleared Desktop sparkles.
const HUNT = [20, 17, 22];
const hunter = CUT.desk.hunt ? el("div", "pointer", screen, POINTER) : null;
if (hunter) HUNT.forEach((i) => style(files[i].f.querySelector(".name"), { borderRadius: "4px", padding: "0 3px" }));
const sparkles = CUT.desk.clean ? [[230, 330], [560, 430], [820, 290]].map(([x, y]) => {
  const k = el("div", "sparkle", screen, SPARKLE);
  style(k, { left: `${x}px`, top: `${y}px` });
  return k;
}) : [];

// MARK: Scene 2, one click and it is in the chat

const LINE_Y = 600, LINE_SAG = 38;
const sendRope = el("div", "rope light", document.body, `<svg width="1080" height="120"><path d="${ropePath(1080, LINE_SAG)}"/></svg>`);
style(sendRope, { left: "0", top: `${LINE_Y}px` });
const CARD_W = 180;
// What hangs on the line: the invoice goes to Lena in WhatsApp, the chart
// to ChatGPT, and the calendar waits its turn.
const SEND_KINDS = ["invoice", "chart", "calendar"];
// In the long cut the button over the chat sends the chart and the calendar
// into ChatGPT together, where the short cut sends the chart by its plane.
const BUTTON = !!CUT.chat.button;
const SEND_FRAC = [0.2, 0.5, 0.8];
const sendCards = SEND_KINDS.map((k) => {
  const c = el("div", "card", document.body, `<span class="clip"></span><div class="glass"><div class="img">${DATA.artByKind[k]}</div></div><div class="send">${ICON_PLANE}</div>`);
  style(c, { width: `${CARD_W}px` });
  return c;
});
const flyers = SEND_KINDS.slice(0, BUTTON ? 3 : 2).map((k) => {
  const g = el("div", "card", document.body, `<div class="glass"><div class="img">${DATA.artByKind[k]}</div></div>`);
  style(g, { width: `${CARD_W}px`, transformOrigin: "50% 50%" });
  return g;
});
// Three chats drawn after the apps people send to, WhatsApp, ChatGPT and
// Claude: their layout and colours, not their logos. WhatsApp is a whole
// conversation with Lena, who asks for the invoice and gets it; the others
// each have a spot where the screenshot lands and an answer that follows.
const UP = '<svg viewBox="0 0 24 24"><path d="M12 19V6M6.5 11.5 12 6l5.5 5.5" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg>';
const TICKS = '<svg viewBox="0 0 18 11"><path d="m1 6 3 3 6-7M7 8l1 1 6-7" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg>';
const MIC = '<svg viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="11" rx="3" fill="currentColor"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" fill="none"/></svg>';
const LIGHTS = '<span class="lights"><i></i><i></i><i></i></span>';
const A = T.apps, W = A.whatsapp;
const avatar = (c) => `<span class="av" style="background:${c.color}">${c.initial}</span>`;
const waHtml = `
  <div class="side">
    <div class="side-top">${LIGHTS}<b>${W.title}</b></div>
    <div class="search">${W.search}</div>
    ${W.chats.map((c, i) => `<div class="row${i === 0 ? " on" : ""}">${avatar(c)}<span class="txt"><b>${c.name}</b><small>${c.last}</small></span><span class="when">${c.time}</span></div>`).join("")}
  </div>
  <div class="main">
    <div class="head">${avatar(W.chats[0])}<span class="who"><b>${W.chats[0].name}</b><small><span class="online">${W.status}</span><span class="typing">${W.typing}</span></small></span></div>
    <div class="msgs">
      <div class="day">${W.day}</div>
      <div class="in">${W.ask}<small>09:38</small></div>
      <div class="out">${W.wait}<small>09:39 <span class="ticks read">${TICKS}</span></small></div>
      <div class="slot me-slot"><div class="out me"><div class="pic">${DATA.artByKind[SEND_KINDS[0]]}</div><small>09:41 <span class="ticks sent">${TICKS}</span></small></div></div>
      <div class="slot reply-slot"><div class="in reply">${W.reply}<small>09:41</small></div></div>
    </div>
    <div class="bar"><span class="plus">+</span><span class="field">${W.field}</span><span class="mic">${MIC}</span></div>
  </div>`;
const gptHtml = BUTTON ? `<div class="top">${LIGHTS}<span class="name">ChatGPT <span class="chev">&#8964;</span></span></div>
   <div class="thread"><div class="me"><div class="album">${SEND_KINDS.slice(1).map((k) => `<div class="pic">${DATA.art2[k]}</div>`).join("")}</div><div class="said">${A.chatgpt.askMany}</div></div>
   <div class="reply">${A.chatgpt.replyMany}</div></div>` : `<div class="top">${LIGHTS}<span class="name">ChatGPT <span class="chev">&#8964;</span></span></div>
   <div class="thread"><div class="me"><div class="pic">${DATA.artByKind[SEND_KINDS[1]]}</div><div class="said">${A.chatgpt.ask}</div></div>
   <div class="reply">${A.chatgpt.reply}</div></div>
   <div class="ask"><span>${A.chatgpt.field}</span><span class="go">${UP}</span></div>`;
const claudeHtml = `<div class="top">${LIGHTS}<span class="name">Claude</span></div>
   <div class="thread"><div class="me"><div class="pic">${DATA.artByKind[SEND_KINDS[2]]}</div><div class="said">${A.claude.ask}</div></div>
   <div class="reply">${A.claude.reply}</div></div>
   <div class="ask"><span>${A.claude.field}</span><span class="go">${UP}</span></div>`;
// Left to right as they fan out at the end: Claude, WhatsApp, ChatGPT.
// WhatsApp is the larger window. They keep clear of Instagram's buttons on
// the right, and meet in the middle when they fan out.
const APPS = [
  { key: "claude", html: claudeHtml, box: [80, 800, 860, 660] },
  { key: "wa", html: waHtml, box: [20, 800, 920, 720] },
  { key: "gpt", html: gptHtml, box: [80, 800, 860, 660] },
];
const apps = APPS.map(({ key, html, box: [x, y, w, h] }) => {
  const node = el("div", `app ${key}`, document.body, html);
  style(node, { left: `${x}px`, top: `${y}px`, width: `${w}px`, height: `${h}px` });
  return { key, w: node, width: w, pics: [...node.querySelectorAll(".pic")], toMiddle: [540 - (x + w / 2), 1064 - (y + h * 0.4)], me: node.querySelector(".me"), pic: node.querySelector(".pic"), reply: node.querySelector(".reply"),
           meSlot: node.querySelector(".me-slot"), replySlot: node.querySelector(".reply-slot"),
           sent: node.querySelector(".ticks.sent"), online: node.querySelector(".online"), typing: node.querySelector(".typing") };
});
const [claudeApp, waApp, gptApp] = apps;
// The button over the chat, just above its own send button: the newest
// photo with the one before it leaning behind, how many will go, and the
// paper plane, which turns into a check once they are sent.
const chatBtn = BUTTON ? el("div", "chatbtn", gptApp.w, `<span class="thumbs"><i>${DATA.art3.chart}</i><i>${DATA.art3.calendar}</i></span><b>2</b><span class="cb-go"><span class="plane">${ICON_PLANE}</span><span class="done">${ICON_CHECK}</span></span>`) : null;
const ripple = el("div", "ripple");
const pointer = el("div", "pointer", document.body, POINTER);

// MARK: Scene 3, names and account numbers covered

const inv = DATA.invoice;
const field = (text) => `<span class="pd"><span class="mark-hl"></span><span class="txt">${text}</span><span class="ink"></span></span>`;
const doc = el("div", "doc", document.body, `
  <div class="bar"><span class="lights"><i></i><i></i><i></i></span></div>
  <div class="body">
    <div class="top"><div><div class="title">${inv.title}</div><div class="dim">${inv.date}</div></div>
      <div style="text-align:end"><div class="title">${inv.total_v}</div><div class="dim">${inv.total}</div></div></div>
    <div class="label">${inv.bill}</div>
    <div>${field(inv.name)}</div>
    <div>${field(inv.street + " · " + inv.city)}</div>
    <div>${field(inv.email)}</div>
    <div>${field(inv.phone)}</div>
    <div class="items">${inv.items.map(([a, b]) => `<div><span>${a}</span><span>${b}</span></div>`).join("")}</div>
    <div class="dim">${inv.pay}</div>
    <div>${field(inv.iban)}</div>
  </div>`);
const fields = [...doc.querySelectorAll(".pd")];
const NAME = 0, IBAN = fields.length - 1;
const lock = el("div", "lock", doc, ICON_LOCK);
style(lock, { right: "40px", bottom: "36px" });
const docSend = CUT.doc.send ? el("div", "send doc-send", doc, ICON_PLANE) : null;

// MARK: Scene 4, the end card

const endIcon = el("img", "end-icon"); endIcon.src = DATA.icon;
const endWord = el("div", "end-word", document.body, "Snapfly");
const endTag = el("div", "end-tag", document.body, T.tagline);
const free = el("div", "free", document.body, T.free);
const url = el("div", "url", document.body, DATA.url);
const legal = el("div", "legal", document.body, T.legal);
const endCta = CUT.end.cta ? el("div", "end-cta", document.body, T.cta) : null;
const soon = CUT.end.soon ? el("div", "soon", document.body, T.soon) : null;

// MARK: The long cut's own scenes

// A pointer of the scene's own, with its ripple.
function makePointer() {
  const r = el("div", "ripple"), p = el("div", "pointer", document.body, POINTER);
  return (x, y, alpha, press = 0, rp = -1) => {
    show(p, alpha);
    style(p, { left: `${x - 12}px`, top: `${y - 8}px`, zIndex: "9", transform: `scale(${1 - 0.15 * press})` });
    show(r, alpha > 0.01 && rp >= 0 && rp < 1 ? 1 - rp : 0);
    style(r, { zIndex: "9", left: `${x - 50 * (1 + rp)}px`, top: `${y - 50 * (1 + rp)}px`, width: `${100 * (1 + rp)}px`, height: `${100 * (1 + rp)}px` });
  };
}
// A ring that swells and settles twice between a and b, to point out a
// button before it is clicked.
const ring = (t, a, b) => (t > a && t < b ? 14 * Math.abs(Math.sin(2 * Math.PI * prog(t, a, b))) : 0);
// Where a pointer is at t: it glides to each stop in turn and clicks there.
function pointerPath(t, from, stops) {
  let x = from.x, y = from.y, press = 0, rp = -1;
  for (let k = 0; k < stops.length; k++) {
    const s = stops[k];
    if (t < s.t - 0.4) break;
    const a = k === 0 ? from : stops[k - 1];
    const m = inOut(prog(t, s.t - 0.4, s.t - 0.05));
    x = lerp(a.x, s.x, m); y = lerp(a.y, s.y, m);
    press = Math.sin(Math.PI * prog(t, s.t - 0.05, s.t + 0.15));
    rp = t >= s.t - 0.05 ? prog(t, s.t, s.t + 0.5) : -1;
  }
  return { x, y, press, rp };
}
// A line across the stage with screenshots on clips.
function makeLine(svgs, w, send = false) {
  const rope = el("div", "rope light", document.body, `<svg width="1080" height="120"><path d="${ropePath(1080, LINE_SAG)}"/></svg>`);
  style(rope, { left: "0", top: `${LINE_Y}px` });
  const cards = svgs.map((svg) => {
    const c = el("div", "card", document.body, `<span class="clip"></span><div class="glass"><div class="img">${svg}</div></div>${send ? `<div class="send">${ICON_PLANE}</div>` : ""}`);
    style(c, { width: `${w}px` });
    return c;
  });
  return { rope, cards };
}
// Where a card hangs at frac along the line; it drops in from above at `drop`.
function hangAt(w, frac, t, drop, tilt) {
  const d = outQuart(prog(t, drop, drop + 0.4));
  return { d, x: 1080 * frac - w / 2, y: LINE_Y + ropeY(frac, LINE_SAG) - 6 - lerp(70, 0, d), r: tilt + swing(t - drop - 0.4, 6, 0.9, 1.2) };
}
function hang(c, w, frac, t, drop, tilt) {
  const h = hangAt(w, frac, t, drop, tilt);
  style(c, { left: `${h.x}px`, top: `${h.y}px`, transform: `rotate(${h.r}deg)` });
  return h.d;
}

// "Du suchst eine alte Rechnung?": the word is typed, the screenshots that
// say it stay bright and show where, the others fade, and one comes close.
function searchScene(S) {
  const W = 170, FR = [0.1, 0.3, 0.5, 0.7, 0.9], TILT = [-4, 3, -2, 4, -3], HITS = [1, 3];
  const { rope, cards } = makeLine([DATA.art2.map, DATA.art2.invoice, DATA.art2.sunset, DATA.art3.invoice, DATA.art2.chart], W);
  const mark = (img) => { img.style.position = "relative"; return el("span", "hit", img); };
  const hits = HITS.map((i) => mark(cards[i].querySelector(".img")));
  const field = el("div", "find", document.body, `${ICON_FIND}<span class="q"></span><span class="caret"></span>`);
  const q = field.querySelector(".q"), caret = field.querySelector(".caret");
  const big = el("div", "card big", document.body, `<div class="glass"><div class="img">${DATA.artByKind.invoice}</div></div>`);
  const bigHit = mark(big.querySelector(".img"));
  const BW = 720;
  return (t) => {
    const a = at(S.in), out = prog(t, at(S.out), at(S.out) + 0.35);
    show(rope, outQuart(prog(t, a, a + 0.4)) * (1 - out));
    const find = outQuart(prog(t, at(S.find), at(S.find) + 0.4));
    cards.forEach((c, i) => {
      const d = hang(c, W, FR[i], t, a + i * 0.06, TILT[i]);
      const hit = HITS.includes(i);
      show(c, d * (1 - out) * (hit ? 1 : lerp(1, 0.25, find)));
      if (hit) c.querySelector(".glass").style.boxShadow = `0 0 0 ${4 * find}px rgba(255,196,92,${0.95 * find}), 0 10px 22px rgba(0,0,0,.35)`;
    });
    hits.forEach((h) => { show(h, find); h.style.transform = `scaleX(${find})`; });
    // The search field under the line: the hint, then the word as typed.
    const fIn = outQuart(prog(t, a + 0.3, a + 0.7));
    show(field, fIn * (1 - out));
    style(field, { transform: `translateX(-50%) translateY(${lerp(30, 0, fIn)}px)` });
    const n = Math.round(T.search.length * prog(t, at(S.type), at(S.type) + 0.55));
    q.textContent = n ? T.search.slice(0, n) : T.searchHint;
    q.style.opacity = n ? 1 : 0.55;
    const typing = t > at(S.type) - 0.2 && t < at(S.type) + 0.8;
    show(caret, typing || Math.floor(t * 2.4) % 2 === 0 ? 1 : 0);
    // One of them comes close, the word marked where it says it.
    const z = inOut(prog(t, at(S.zoom), at(S.zoom) + 0.6));
    show(big, z > 0 ? 1 - out : 0);
    const src = cards[HITS[0]].getBoundingClientRect();
    style(big, { width: `${BW}px`, zIndex: "7", transformOrigin: "0 0", left: `${lerp(src.left, 180, z)}px`,
                 top: `${lerp(src.top, 980, z) - 40 * inOut(out)}px`, transform: `scale(${lerp(src.width / BW, 1, z)})` });
    const bh = outQuart(prog(t, at(S.zoom) + 0.45, at(S.zoom) + 0.8));
    show(bigHit, bh); bigHit.style.transform = `scaleX(${bh})`;
  };
}

// "Mehrere Screenshots? Werden zu einem PDF.": three are picked, then come
// together as the pages of one PDF.
function pdfScene(P) {
  const W = 210, FR = [0.2, 0.5, 0.8], TILT = [-3, 2, -4];
  const { rope, cards } = makeLine([DATA.art3.invoice, DATA.art3.chart, DATA.art3.calendar], W);
  const picks = cards.map((c) => el("span", "pick", c, ICON_CHECK));
  const key = el("div", "key", document.body, "⌘");
  const pointer = makePointer();
  const tag = el("div", "pdf-tag", document.body, `<b>PDF</b><span>${T.pages}</span>`);
  // How the pages lie in the stack, the first one on top.
  const STACK = [{ x: -10, y: 18, r: -2 }, { x: 14, y: 0, r: 3 }, { x: -4, y: -18, r: -5 }];
  return (t) => {
    const a = at(P.in), out = prog(t, at(P.out), at(P.out) + 0.35);
    show(rope, outQuart(prog(t, a, a + 0.4)) * (1 - out));
    const stops = cards.map((c, k) => {
      const h = hangAt(W, FR[k], t, a + k * 0.06, TILT[k]);
      return { x: h.x + W * 0.55, y: h.y + 80, t: at(P.picks[k]) };
    });
    cards.forEach((c, k) => {
      const h = hangAt(W, FR[k], t, a + k * 0.06, TILT[k]);
      const m = inOut(prog(t, at(P.merge) + k * 0.06, at(P.merge) + 0.6 + k * 0.06));
      const s = STACK[k];
      show(c, h.d * (1 - out));
      style(c, { zIndex: String(6 - k), transformOrigin: "50% 50%",
        left: `${lerp(h.x, 540 - W / 2 + s.x, m)}px`, top: `${lerp(h.y, 1000 + s.y, m) - 50 * inOut(out)}px`,
        transform: `rotate(${lerp(h.r, s.r, m)}deg) scale(${lerp(1, 1.75, m)})` });
      c.querySelector(".clip").style.opacity = 1 - m;
      const pk = prog(t, at(P.picks[k]), at(P.picks[k]) + 0.25);
      show(picks[k], outQuart(pk) * (1 - m));
      picks[k].style.transform = `scale(${lerp(0.3, 1, outBack(pk))})`;
    });
    const p = pointerPath(t, { x: 930, y: 1500 }, stops);
    const pa = prog(t, a + 0.2, a + 0.45) * (1 - prog(t, at(P.picks[2]) + 0.3, at(P.picks[2]) + 0.5));
    pointer(p.x, p.y, pa, p.press, p.rp);
    show(key, pa);
    style(key, { left: `${p.x + 40}px`, top: `${p.y + 60}px`, zIndex: "9" });
    const b = prog(t, at(P.badge), at(P.badge) + 0.35);
    show(tag, outQuart(b) * (1 - out));
    style(tag, { top: "1250px", transform: `translateX(-50%) scale(${lerp(0.6, 1, outBack(b))})` });
  };
}

// "Fremde Sprache? Wird übersetzt": the photo's menu, Translate Text, and
// the words turn German where they stand.
function translateScene(R) {
  const KEYS = ["title", "body", "button"];
  const win = el("div", "doc tr", document.body, `<div class="bar">${LIGHTS}</div><div class="body">${KEYS.map((k) =>
    `<div class="swap l-${k}"><span><span>${T.source[k]}</span></span><span><span>${T.translated[k]}</span></span></div>`).join("")}</div>`);
  const lines = [...win.querySelectorAll(".swap")];
  const chip = el("div", "lang-chip", document.body, T.langs);
  const menu = el("div", "menu", document.body, T.menu.map((m) => `<div>${m}</div>`).join(""));
  const item = menu.children[1];
  const pointer = makePointer();
  return (t) => {
    const a = at(R.in), out = prog(t, at(R.out), at(R.out) + 0.35);
    const wIn = outQuart(prog(t, a, a + 0.4));
    show(win, wIn * (1 - out));
    style(win, { left: "110px", top: "700px", transform: `translateY(${lerp(70, 0, wIn) - 50 * inOut(out)}px) scale(${lerp(0.94, 1, wIn)})` });
    lines.forEach((ln, i) => {
      const s = inOut(prog(t, at(R.swap) + i * 0.14, at(R.swap) + 0.45 + i * 0.14));
      const [en, de] = ln.children;
      style(en, { opacity: 1 - s, transform: `translateY(${-18 * s}px)`, filter: `blur(${6 * s}px)` });
      style(de, { opacity: s, transform: `translateY(${18 * (1 - s)}px)`, filter: `blur(${6 * (1 - s)}px)` });
    });
    const mIn = outQuart(prog(t, at(R.menu), at(R.menu) + 0.2)) * (1 - prog(t, at(R.click) + 0.2, at(R.click) + 0.4));
    show(menu, mIn);
    style(menu, { left: "500px", top: "1030px", zIndex: "8", transform: `scale(${lerp(0.9, 1, mIn)})` });
    item.classList.toggle("lit", t >= at(R.click) - 0.3);
    const r = item.getBoundingClientRect();
    const p = pointerPath(t, { x: 930, y: 1520 }, [{ x: 575, y: 1040, t: at(R.menu) - 0.05 }, { x: r.left + 120, y: r.top + r.height / 2, t: at(R.click) }]);
    pointer(p.x, p.y, prog(t, a + 0.15, a + 0.4) * (1 - prog(t, at(R.click) + 0.35, at(R.click) + 0.6)), p.press, p.rp);
    const c = prog(t, at(R.swap) + 0.3, at(R.swap) + 0.65);
    show(chip, outQuart(c) * (1 - out));
    style(chip, { transform: `translateX(-50%) scale(${lerp(0.7, 1, outBack(c))})` });
  };
}

// "Was gesendet ist, verschwindet von der Leine. Der Verlauf hebt es dreißig
// Tage auf.": one is sent and leaves, the others close up, and the history
// still holds it.
function sentScene(H) {
  const W = 200, FR0 = [0.22, 0.5, 0.78], FR1 = [0.36, 0.5, 0.64], TILT = [-3, 2, -4];
  const { rope, cards } = makeLine([DATA.art3.map, DATA.art3.sunset, DATA.art2.calendar], W, true);
  const pointer = makePointer();
  const th = (svg, ring) => `<div class="th${ring ? " ring" : ""}">${svg}</div>`;
  const hist = el("div", "hist", document.body, `
    <div class="bar">${LIGHTS}<b>${T.history}</b></div>
    <div class="hsearch">${ICON_FIND}<span>${T.searchHint}</span></div>
    <div class="day">${T.today}</div>
    <div class="row">${th(DATA.art[4], true)}${th(DATA.art[0])}${th(DATA.art[2])}</div>
    <div class="day">${T.yesterday}</div>
    <div class="row">${th(DATA.art[1])}${th(DATA.art[3])}${th(DATA.art2.chart)}</div>`);
  const ring = hist.querySelector(".ring");
  const days = el("div", "days", document.body, `${ICON_CLOCK}<span>${T.days}</span>`);
  return (t) => {
    const a = at(H.in), out = prog(t, at(H.out), at(H.out) + 0.35);
    show(rope, outQuart(prog(t, a, a + 0.4)) * (1 - out));
    const close = inOut(prog(t, at(H.close), at(H.close) + 0.6));
    const f = inOut(prog(t, at(H.click) + 0.1, at(H.click) + 0.85));
    let button = { x: 0, y: 0 };
    cards.forEach((c, k) => {
      const h = hangAt(W, lerp(FR0[k], FR1[k], k === 1 ? 0 : close), t, a + k * 0.06, TILT[k]);
      if (k === 1) {
        button = { x: h.x + W - 13, y: h.y + c.offsetHeight - 13 };
        // Sent: off it flies, toward the chat.
        show(c, h.d * (f < 1 ? 1 - 0.6 * prog(f, 0.6, 1) : 0));
        style(c, { left: `${lerp(h.x, 1180, f)}px`, top: `${lerp(h.y, 60, f) - Math.sin(Math.PI * f) * 140}px`,
                   transform: `rotate(${lerp(h.r, 24, f)}deg) scale(${lerp(1, 0.45, f)})` });
      } else {
        show(c, h.d * (1 - out));
        style(c, { left: `${h.x}px`, top: `${h.y}px`, transform: `rotate(${h.r}deg)` });
      }
    });
    const p = pointerPath(t, { x: 930, y: 1500 }, [{ ...button, t: at(H.click) }]);
    pointer(p.x, p.y, prog(t, a + 0.1, a + 0.3) * (1 - prog(t, at(H.click) + 0.3, at(H.click) + 0.5)), p.press, p.rp);
    const hIn = outQuart(prog(t, at(H.history), at(H.history) + 0.45));
    show(hist, hIn * (1 - out));
    style(hist, { left: "90px", top: "800px", transform: `translateY(${lerp(80, 0, hIn) - 50 * inOut(out)}px) scale(${lerp(0.94, 1, hIn)})` });
    const rg = prog(t, at(H.history) + 0.5, at(H.history) + 0.8);
    ring.style.boxShadow = `0 0 0 ${5 * outQuart(rg)}px #FF7A59`;
    const d = prog(t, at(H.days), at(H.days) + 0.4);
    show(days, outQuart(d) * (1 - out));
    style(days, { left: "650px", top: "760px", zIndex: "8", transform: `scale(${lerp(0.5, 1, outBack(d))}) rotate(${lerp(-10, 3, outQuart(d))}deg)` });
  };
}

// "Kein Konto. Keine Cloud. Alles bleibt auf deinem Mac."
function privacyScene(V) {
  const tiles = [ICON_PERSON, ICON_CLOUD, ICON_MAC].map((svg, i) =>
    el("div", "tile" + (i === 2 ? " mac" : ""), document.body, svg + (i < 2 ? '<svg class="strike" viewBox="0 0 100 100"><path d="M20 20 80 80"/></svg>' : "")));
  const CUES = [V.account, V.cloud, V.mac];
  return (t) => {
    const out = prog(t, at(V.out), at(V.out) + 0.35);
    tiles.forEach((tile, i) => {
      const p = prog(t, at(CUES[i]), at(CUES[i]) + 0.45);
      show(tile, outQuart(p) * (1 - out));
      const grow = i === 2 ? lerp(1, 1.1, inOut(prog(t, at(CUES[2]) + 0.4, at(V.out)))) : 1;
      style(tile, { left: `${[100, 410, 720][i]}px`, top: "880px",
                    transform: `translateY(${lerp(50, 0, outQuart(p)) - 40 * inOut(out)}px) scale(${lerp(0.6, 1, outBack(p)) * grow})` });
      const st = tile.querySelector(".strike path");
      if (st) st.style.strokeDashoffset = 100 * (1 - outQuart(prog(t, at(CUES[i]) + 0.25, at(CUES[i]) + 0.55)));
    });
  };
}

// "Neuer Screenshot? Ein Klick auf den Knopf am Bildschirmrand. Fertig.":
// the screenshot button at the screen's edge, a drag over the order, a
// flash, and the screenshot hangs on the line, ahead of the others.
function deskShotScene(B) {
  const win = el("div", "deskwin", screen, `<div class="bar">${LIGHTS}</div><div class="img">${DATA.art2.invoice}</div>`);
  const btn = el("div", "shotbtn", screen, ICON_VIEWFINDER);
  const dim = el("div", "layer", screen);
  style(dim, { background: "rgba(0,0,0,.32)", zIndex: "7" });
  const sel = el("div", "shotsel", screen);
  const cross = el("div", "cross", screen, ICON_CROSS);
  const flash = el("div", "layer", screen);
  style(flash, { background: "#fff", zIndex: "10" });
  const shot = el("div", "file shot", screen, `<div class="thumb">${DATA.art3.invoice}</div>`);
  const ptr = el("div", "pointer", screen, POINTER);
  const S0 = { x: 236, y: 188 }, S1 = { x: 664, y: 498 }, BTN = { x: 944, y: 396 }, SHOT_W = 150;
  return (t) => {
    const a = at(B.in), click = at(B.click), d0 = at(B.drag[0]), d1 = at(B.drag[1]), fl = at(B.flash);
    const wi = outQuart(prog(t, a, a + 0.4));
    show(win, wi);
    style(win, { left: "250px", top: "200px", width: "400px", zIndex: "4", transform: `translateY(${lerp(30, 0, wi)}px) scale(${lerp(0.94, 1, wi)})` });
    const bi = prog(t, a + 0.2, a + 0.55);
    show(btn, outQuart(bi));
    style(btn, { transform: `scale(${lerp(0.3, 1, outBack(bi)) * (1 - 0.12 * Math.sin(Math.PI * prog(t, click - 0.05, click + 0.15)))})`,
                 boxShadow: `0 6px 16px rgba(0,0,0,.35), 0 0 0 ${ring(t, a + 0.6, click - 0.3)}px rgba(10,132,255,.35)` });
    // The pointer goes to the button and clicks; then a crosshair drags
    // over the order.
    const p = pointerPath(t, { x: 640, y: 600 }, [{ ...BTN, t: click }]);
    show(ptr, prog(t, a + 0.3, a + 0.5) * (t < click + 0.2 ? 1 : 0));
    style(ptr, { left: `${p.x - 12}px`, top: `${p.y - 8}px`, zIndex: "9", transform: `scale(${1 - 0.15 * p.press})` });
    show(dim, prog(t, click + 0.15, click + 0.3) * (1 - prog(t, fl, fl + 0.1)));
    const toStart = inOut(prog(t, click + 0.2, d0)), drag = inOut(prog(t, d0, d1));
    const cx = t < d0 ? lerp(BTN.x, S0.x, toStart) : lerp(S0.x, S1.x, drag);
    const cy = t < d0 ? lerp(BTN.y, S0.y, toStart) : lerp(S0.y, S1.y, drag);
    show(cross, t >= click + 0.2 && t < fl ? 1 : 0);
    style(cross, { left: `${cx - 24}px`, top: `${cy - 24}px` });
    show(sel, t >= d0 && t < fl + 0.05 ? 1 : 0);
    style(sel, { left: `${S0.x}px`, top: `${S0.y}px`, width: `${Math.max(0, cx - S0.x)}px`, height: `${Math.max(0, cy - S0.y)}px` });
    const f = prog(t, fl, fl + 0.3);
    show(flash, f > 0 && f < 1 ? 0.85 * (1 - f) : 0);
    // The screenshot flies up onto the line and hangs there.
    const f0 = fl + 0.1, f1 = at(B.hang), fly = inOut(prog(t, f0, f1));
    show(shot, t >= f0 ? 1 : 0);
    const fromW = S1.x - S0.x;
    style(shot, { width: `${SHOT_W}px`, zIndex: "9",
      left: `${lerp(S0.x + (fromW - SHOT_W) / 2, 500 - SHOT_W / 2, fly)}px`, top: `${lerp(S0.y, 56 + ropeY(0.5, 26) - 6, fly) - Math.sin(Math.PI * fly) * 60}px`,
      transform: `scale(${lerp(fromW / SHOT_W, 1, fly)}) rotate(${lerp(0, -3, fly) + swing(t - f1, 9)}deg)` });
    shot.querySelector(".thumb").style.boxShadow = `0 0 0 ${8 * Math.sin(Math.PI * prog(t, f1, f1 + 0.6))}px rgba(255,196,92,.9), 0 3px 8px rgba(0,0,0,.35)`;
  };
}

// "Und per E-Mail? Genauso einfach.": one click on the plane, and the
// screenshot lands in the new e-mail to Lena.
function mailScene(M) {
  const W = 200;
  const { rope, cards } = makeLine([DATA.art3.invoice], W, true);
  const m = T.mail;
  const win = el("div", "mail", document.body, `
    <div class="bar">${LIGHTS}<span class="send-i">${ICON_PLANE_LINE}</span><b>${m.title}</b></div>
    <div class="f"><span>${m.to}</span><em>${m.toName}</em></div>
    <div class="f"><span>${m.subject}</span>${m.subjectText}</div>
    <div class="mbody"><p>${m.hello}</p><p>${m.text}</p><div class="slot"><div class="pic">${DATA.art3.invoice}</div></div><p>${m.bye}</p></div>`);
  const slot = win.querySelector(".slot"), pic = slot.querySelector(".pic");
  const flyer = el("div", "card", document.body, `<div class="glass"><div class="img">${DATA.art3.invoice}</div></div>`);
  style(flyer, { width: `${W}px`, transformOrigin: "50% 50%" });
  const pointer = makePointer();
  return (t) => {
    const a = at(M.in), out = prog(t, at(M.out), at(M.out) + 0.35);
    show(rope, outQuart(prog(t, a, a + 0.4)) * (1 - out));
    const h = hangAt(W, 0.5, t, a, -3);
    const start = at(M.click) + 0.12, f = prog(t, start, start + 0.6);
    show(cards[0], h.d * (t < start ? 1 : 0));
    style(cards[0], { left: `${h.x}px`, top: `${h.y}px`, transform: `rotate(${h.r}deg)` });
    const wIn = outQuart(prog(t, a + 0.1, a + 0.5));
    show(win, wIn * (1 - out));
    style(win, { left: "70px", top: "790px", transform: `translateY(${lerp(80, 0, wIn) - 50 * inOut(out)}px) scale(${lerp(0.94, 1, wIn)})` });
    slot.style.maxHeight = `${lerp(0, slot.scrollHeight, outQuart(prog(t, start, start + 0.35)))}px`;
    show(pic, f >= 1 ? 1 : 0);
    show(flyer, f > 0 && f < 1 ? 1 : 0);
    if (f > 0 && f < 1) {
      const r = pic.getBoundingClientRect(), fh = flyer.offsetHeight, e = inOut(f);
      const x = lerp(h.x, r.left + r.width / 2 - W / 2, e) + Math.sin(Math.PI * e) * 70;
      const y = lerp(h.y, r.top + r.height / 2 - fh / 2, e) - Math.sin(Math.PI * e) * 150;
      style(flyer, { left: `${x}px`, top: `${y}px`, zIndex: "8", transform: `rotate(${-9 * Math.sin(Math.PI * e)}deg) scale(${lerp(1, r.width / W, e)})` });
      flyer.querySelector(".glass").style.padding = `${lerp(6, 0, e)}px`;
    }
    const button = { x: h.x + W - 13, y: h.y + cards[0].offsetHeight - 13 };
    const p = pointerPath(t, { x: 930, y: 1500 }, [{ ...button, t: at(M.click) }]);
    pointer(p.x, p.y, prog(t, a + 0.2, a + 0.4) * (1 - prog(t, at(M.click) + 0.3, at(M.click) + 0.5)), p.press, p.rp);
  };
}

// "Und das ist nicht alles!": what else it does, a tile at each word.
function moreScene(V) {
  const glow = el("div", "layer boost");
  const ICONS = [ICON_REC, ICON_PAGE, ICON_STOPWATCH, SPARKLE];
  const POS = [[100, 700], [530, 700], [100, 1050], [530, 1050]];
  const tiles = T.more.map((label, i) => el("div", "mtile" + (i === 3 ? " hot" : ""), document.body, `${ICONS[i]}<span>${label}</span>`));
  return (t) => {
    const out = prog(t, at(V.out), at(V.out) + 0.35);
    let pulse = t >= at(V.hit) ? Math.exp(-(t - at(V.hit)) * 4) : 0;
    tiles.forEach((tile, i) => {
      const c = at(V.items[i]), p = prog(t, c, c + 0.45);
      show(tile, outQuart(p) * (1 - out));
      const tilt = i % 2 ? 1 : -1;
      style(tile, { left: `${POS[i][0]}px`, top: `${POS[i][1]}px`,
        transform: `translateY(${-40 * inOut(out)}px) scale(${lerp(0.3, 1, outBack(p))}) rotate(${lerp(10 * tilt, 2 * tilt, outQuart(p))}deg)` });
      if (t >= c) pulse = Math.max(pulse, Math.exp(-(t - c) * 5));
    });
    show(glow, 0.55 * pulse * (1 - out));
  };
}

// The long cut's last words: "Entdecke viel mehr!" takes the tagline's
// place, and confetti bursts as it is said.
function ctaScene(E) {
  const COLORS = ["#FFC45C", "#FF7A59", "#FF5E62", "#D25BF0", "#FFFFFF", "#0A84FF"];
  const bits = Array.from({ length: 80 }, (_, i) => {
    const b = el("div", "conf");
    style(b, { background: COLORS[i % COLORS.length], width: `${10 + rnd(i, 5) * 12}px`, height: `${14 + rnd(i, 6) * 16}px` });
    return { b, ang: -Math.PI / 2 + (rnd(i, 7) - 0.5) * 2.6, v: 900 + rnd(i, 8) * 1200, spin: (rnd(i, 9) - 0.5) * 1440, delay: rnd(i, 10) * 0.15 };
  });
  return (t) => {
    const c = prog(t, at(E.cta), at(E.cta) + 0.45);
    show(endCta, outQuart(c));
    style(endCta, { top: "1000px", transform: `scale(${lerp(0.5, 1, outBack(c)) * (1 + 0.035 * Math.sin(Math.max(0, t - at(E.boom)) * 7))})` });
    bits.forEach((d) => {
      const tau = t - at(E.boom) - d.delay;
      if (tau <= 0 || tau > 3.2) { show(d.b, 0); return; }
      show(d.b, 1 - prog(tau, 2.4, 3.2));
      style(d.b, { left: `${540 + Math.cos(d.ang) * d.v * tau * 0.85}px`, top: `${1060 + Math.sin(d.ang) * d.v * tau + 1100 * tau * tau}px`,
                   transform: `rotate(${d.spin * tau}deg)` });
    });
  };
}

// "Und bald auch auf dem iPhone: Belege scannen, Fotos und PDFs zu einem
// Dokument zusammenfügen, und sicher teilen.": the Scan tab, a receipt
// scanned, photos and a PDF flying in as pages, one page moved to the front,
// the covers, and Save and Share. The phone is drawn in iPhone points
// (390 × 844 for its screen) and scaled up as a whole.
const G_PHOTO = line24('<rect x="3" y="5" width="18" height="14" rx="2.5"/><circle cx="9" cy="10" r="1.6"/><path d="m4 17 5-4.5 4 3.5 3-2.5 4 3.5"/>');
const G_SHIELD = line24('<path d="M12 3 5 6v5.5c0 4.4 3 7.7 7 9.5 4-1.8 7-5.1 7-9.5V6Z"/>');
const G_SCAN = line24('<path d="M3 8V5.5A2.5 2.5 0 0 1 5.5 3H8M16 3h2.5A2.5 2.5 0 0 1 21 5.5V8M21 16v2.5a2.5 2.5 0 0 1-2.5 2.5H16M8 21H5.5A2.5 2.5 0 0 1 3 18.5V16M7 12h10"/>');
const G_MORE = line24('<circle cx="12" cy="12" r="9"/><path d="M8 12h.01M12 12h.01M16 12h.01" stroke-width="2.6"/>');
const G_DOC = line24('<path d="M7 3h7l5 5v13H7Z"/><path d="M14 3v5h5M10 13h6M10 17h6"/>');
const G_STACK = line24('<rect x="4" y="7" width="12" height="14" rx="2"/><path d="M8 4h10a2 2 0 0 1 2 2v12"/>');
const G_SHARE = line24('<path d="M12 15V3M7.5 7.5 12 3l4.5 4.5M5 11v8a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-8"/>');
const G_CAMERA = line24('<path d="M4 8h3l2-3h6l2 3h3v11H4Z"/><circle cx="12" cy="13" r="3.5"/>');
const G_PLUS = line24('<path d="M12 5v14M5 12h14"/>');
function phoneScene(P) {
  const X = 333, Y = 748, S = 1.25;
  const ph = T.phone, R = T.receipt, Lt = T.letter;
  const count = (n) => (n === 1 ? ph.page : ph.pages.replace("%d", n));
  const phone = el("div", "phone", document.body, `
    <div class="ph-bezel"></div>
    <div class="ph-screen">
      <div class="ph-layer ph-home">
        <div class="ph-h1" style="top:58px">${ph.Scan}</div>
        <div class="ph-btn" style="top:116px">${G_CAMERA}${ph["Scan Document"]}</div>
        <div class="ph-card" style="top:190px">
          <div class="hd"><span class="ph-tile">${G_DOC}</span><span><b>${ph["Create and Edit PDFs"]}</b><small>${ph["Photos, scans and PDFs into one file"]}</small></span></div>
          <div class="ph-two"><span class="fill">${G_STACK}${ph.Merge}</span><span>${G_DOC}${ph["Open PDF"]}</span></div>
        </div>
        <div class="ph-sec" style="top:360px">${ph["Recently Edited"]}</div>
        <div class="ph-card ph-list" style="top:398px">${T.recent.map(([n, k]) => `<div class="ph-row"><i></i><span><b>${n}</b><small>${count(k)}</small></span></div>`).join("")}</div>
        <div class="ph-tabs">${[[G_PHOTO, ph.Photos], [G_SHIELD, ph.Protected], [G_SCAN, ph.Scan], [G_MORE, ph.More]]
          .map(([g, l], i) => `<div class="ph-tab${i === 2 ? " on" : ""}">${g}<span>${l}</span></div>`).join("")}</div>
      </div>
      <div class="ph-layer ph-ov">
        <div class="ph-nav"><span class="back">‹</span><span class="done">${ph.Done}</span></div>
        <div class="ph-h1" style="top:96px">${Lt.project}</div>
        <div class="ph-sub"></div>
        <div class="ph-bar"><span class="ph-add">${G_PLUS}${ph.Add}</span><span class="ph-save">${G_SHARE}${ph["Save and Share"]}</span></div>
      </div>
      <div class="ph-layer ph-cam"><div class="ph-chip">${ph["Scan Document"]}</div><div class="ph-shutter"><i></i></div></div>
      <div class="ph-layer ph-flash"></div>
      <div class="ph-status"><b>9:41</b><i class="ph-island"></i></div>
      <i class="ph-home-ind"></i>
    </div>
    <div class="ph-over"></div>`);
  const $ = (s) => phone.querySelector(s);
  const home = $(".ph-home"), ov = $(".ph-ov"), cam = $(".ph-cam"), flash = $(".ph-flash"), status = $(".ph-status");
  const sub = $(".ph-sub"), save = $(".ph-save"), shutter = $(".ph-shutter"), over = $(".ph-over");
  // The pages: the scanned receipt, two photos and the PDF's page, each in
  // its own shape, a paper drawn at 200 points wide and scaled to fit.
  const ink = '<i class="ink"></i>';
  const receipt = `<div class="rc"><b>${R.shop}</b><small>${R.place}</small><hr>${R.lines.map(([a, b]) => `<p><span>${a}</span><span>${b}</span></p>`).join("")}
    <hr><p class="tot"><span>${R.total}</span><span>${R.total_v}</span></p><p><span>${R.card}</span><span class="pv">${R.card_v}${ink}</span></p></div>`;
  const letter = `<div class="lt"><b>${Lt.title}</b><small>${Lt.no}</small><p><span class="pv">${Lt.to}${ink}</span></p><p><span class="pv">${Lt.street}${ink}</span></p>
    <div class="lines"><i style="width:90%"></i><i style="width:70%"></i><i style="width:82%"></i><i style="width:55%"></i></div><p><span class="pv">${Lt.iban}${ink}</span></p></div>`;
  const PAGES = [
    { w: 100, h: 140, html: `<div class="ph-in" style="transform:scale(.5)">${receipt}</div>`, label: ph.Receipt },
    { w: 110, h: 73, html: DATA.art3.sunset, label: T.photo },
    { w: 110, h: 73, html: DATA.art3.chart, label: T.photo },
    { w: 99, h: 140, html: `<div class="ph-in" style="transform:scale(.495)">${letter}</div><span class="ph-badge">PDF</span>`, label: ph.Invoice },
  ];
  const pages = PAGES.map((p) => {
    const n = el("div", "ph-page", over, `<div class="ph-paper">${p.html}</div><span class="ph-lab"></span>`);
    style(n, { width: `${p.w}px`, height: `${p.h}px` });
    n.querySelector(".ph-lab").style.top = `${p.h + 8 + (140 - p.h) / 2}px`;
    return { ...p, n, lab: n.querySelector(".ph-lab"), inks: [...n.querySelectorAll(".ink")] };
  });
  const quad = el("i", "ph-quad", pages[0].n);
  const toast = el("div", "ph-toast", over, `${ph["Page moved"]}<span>${ph.Undo}</span>`);
  const sclip = el("div", "ph-sclip", over, `<div class="ph-dim"></div><div class="ph-sheet"><i class="grab"></i><div class="st">${ph["Save and Share"]}</div>
    <div class="sf"><span>${ph.Name}</span>${Lt.project}</div><div class="seg"><span class="on">${ph["With Covers"]}</span><span>${ph["Without Covers"]}</span></div>
    <div class="note">${G_SHIELD}${ph["Private details stay covered"]}</div>
    <div class="sh"><span class="lbl">${G_SHARE}${ph.Share}</span><span class="ok">${ICON_CHECK}</span></div>
    <div class="two2"><span>${ph.Copy}</span><span>${ph.Save}</span></div></div>`);
  const dim = sclip.querySelector(".ph-dim"), sheet = sclip.querySelector(".ph-sheet"), shareBtn = sclip.querySelector(".sh");
  const file = el("div", "ph-file", over, `<b>PDF</b><span>${Lt.project}.pdf<small>${count(4)}</small></span><i>${ICON_CHECK}</i>`);
  const touch = el("i", "ph-touch", over);
  // Where a node's middle is, in the phone's own points.
  const middle = (node) => { const o = over.getBoundingClientRect(), r = node.getBoundingClientRect();
    return { x: (r.left + r.width / 2 - o.left) / S, y: (r.top + r.height / 2 - o.top) / S }; };
  // Three to a row, as the overview shows pages.
  const slot = (s) => ({ x: 16 + (s % 3) * 124 + 55, y: 176 + Math.floor(s / 3) * 176 + 70 });
  // Where each page flies in from, and when.
  const FROM = [null, { x: -330, y: 140, r: -24, t: P.photos[0] }, { x: -300, y: 560, r: 18, t: P.photos[1] }, { x: 600, y: 260, r: 22, t: P.pdf }];
  const ORDER0 = [0, 1, 2, 3], ORDER1 = [3, 0, 1, 2];
  return (t) => {
    const a = at(P.in), out = prog(t, at(P.out[0]), at(P.out[1]));
    const rise = outQuart(prog(t, a, a + 0.6));
    show(phone, prog(t, a, a + 0.15) * (1 - out));
    style(phone, { left: `${X}px`, top: `${Y}px`, transform: `translateY(${lerp(1250, 0, rise) - 70 * inOut(out)}px) rotate(${lerp(9, 0, rise)}deg) scale(${S * lerp(1, 0.96, out)})` });
    // The Scan tab, then the camera over it, then the pages' overview.
    const camIn = outQuart(prog(t, at(P.camera) - 0.12, at(P.camera) + 0.2));
    const ovAt = at(P.shutter) + 0.35, ovIn = prog(t, ovAt, ovAt + 0.25);
    show(home, 1 - ovIn); show(ov, ovIn);
    show(cam, camIn * (1 - ovIn));
    cam.style.transform = `translateY(${lerp(120, 0, camIn)}px)`;
    status.style.color = camIn > 0.5 && ovIn < 0.5 ? "#fff" : "#111318";
    const fl = prog(t, at(P.shutter), at(P.shutter) + 0.3);
    show(flash, fl > 0 && fl < 1 ? 0.9 * (1 - fl) : 0);
    shutter.style.transform = `scale(${1 - 0.12 * Math.sin(Math.PI * prog(t, at(P.shutter) - 0.05, at(P.shutter) + 0.15))})`;
    // The pages land one by one; the count follows them.
    const landed = (i) => (i === 0 ? ovAt + 0.4 : at(FROM[i].t) + 0.5);
    sub.textContent = count(pages.filter((p, i) => t >= landed(i)).length);
    const title = outBack(prog(t, at(P.title), at(P.title) + 0.35));
    ov.querySelector(".ph-h1").style.transform = `scale(${t >= at(P.title) ? lerp(1.12, 1, title) : 1})`;
    // One page is held, lifted and taken to the front; the others make room.
    const lift = outQuart(prog(t, at(P.lift), at(P.lift) + 0.2)) * (1 - outQuart(prog(t, at(P.drop), at(P.drop) + 0.2)));
    const move = inOut(prog(t, at(P.lift) + 0.2, at(P.drop)));
    const shift = inOut(prog(t, at(P.drop) - 0.5, at(P.drop) - 0.05));
    pages.forEach((p, i) => {
      const s0 = slot(ORDER0.indexOf(i)), s1 = slot(ORDER1.indexOf(i));
      let x = lerp(s0.x, s1.x, i === 3 ? move : shift), y = lerp(s0.y, s1.y, i === 3 ? move : shift), r = 0, sc = 1 + 0.12 * (i === 3 ? lift : 0), o = 1, lean = 0;
      if (i === 0) {
        // The receipt on the table, crooked, then straight and into place.
        const flat = outQuart(prog(t, at(P.shutter) + 0.1, at(P.shutter) + 0.35)), go = inOut(prog(t, ovAt, ovAt + 0.4));
        x = lerp(195, x, go); y = lerp(390, y, go); r = lerp(-9, 0, flat); sc = lerp(2, 1, go);
        o = camIn; lean = lerp(14, 0, flat);
      } else {
        const f = FROM[i], fly = inOut(prog(t, at(f.t), at(f.t) + 0.5));
        o = t >= at(f.t) ? 1 : 0;
        x = lerp(f.x, x, fly); y = lerp(f.y, y, fly) - Math.sin(Math.PI * fly) * 80; r = lerp(f.r, 0, fly) - (i === 3 ? 3 * lift : 0);
        sc *= lerp(1.6, 1, fly);
      }
      show(p.n, o);
      style(p.n, { left: `${x - p.w / 2}px`, top: `${y - p.h / 2}px`, zIndex: i === 3 ? "3" : "2",
                   transform: `perspective(900px) rotateX(${lean}deg) rotate(${r}deg) scale(${sc})`,
                   filter: i === 3 && lift > 0 ? `drop-shadow(0 ${14 * lift}px ${18 * lift}px rgba(0,0,0,.28))` : "" });
      const pos = (t >= at(P.drop) ? ORDER1 : ORDER0).indexOf(i) + 1;
      p.lab.innerHTML = `<b>${pos}</b> · ${p.label}`;
      show(p.lab, i === 0 ? ovIn : prog(t, at(FROM[i].t) + 0.4, at(FROM[i].t) + 0.6));
      p.inks.forEach((k, j) => { k.style.transform = `scaleX(${outQuart(prog(t, at(P.cover) + j * 0.1, at(P.cover) + 0.3 + j * 0.1))})`; });
    });
    show(quad, prog(t, at(P.frame), at(P.frame) + 0.15) * (1 - prog(t, at(P.shutter), at(P.shutter) + 0.2)));
    quad.style.transform = `scale(${lerp(1.25, 1, outQuart(prog(t, at(P.frame), at(P.frame) + 0.3)))})`;
    // "Page moved", with its Undo.
    const tn = outQuart(prog(t, at(P.drop) + 0.1, at(P.drop) + 0.35)) * (1 - prog(t, at(P.saveTap), at(P.saveTap) + 0.2));
    show(toast, tn);
    toast.style.transform = `translateX(-50%) translateY(${lerp(20, 0, tn)}px)`;
    // Save and Share: the sheet, with covers on, and Share.
    const sh = outQuart(prog(t, at(P.saveTap) + 0.1, at(P.saveTap) + 0.45));
    show(sclip, sh > 0 ? 1 : 0); show(dim, sh);
    sheet.style.transform = `translateY(${lerp(480, 0, sh)}px)`;
    save.style.transform = `scale(${1 - 0.08 * Math.sin(Math.PI * prog(t, at(P.saveTap) - 0.05, at(P.saveTap) + 0.15))})`;
    const done = t >= at(P.shareTap) + 0.1;
    show(shareBtn.querySelector(".lbl"), done ? 0 : 1); show(shareBtn.querySelector(".ok"), done ? 1 : 0);
    shareBtn.style.transform = `scale(${1 - 0.06 * Math.sin(Math.PI * prog(t, at(P.shareTap) - 0.05, at(P.shareTap) + 0.15))})`;
    const ff = prog(t, at(P.shareTap) + 0.2, at(P.shareTap) + 0.8);
    show(file, ff > 0 ? 1 - prog(ff, 0.75, 1) : 0);
    style(file, { left: `${lerp(195, 330, inOut(ff))}px`, top: `${lerp(640, -150, inOut(ff))}px`, transform: `translate(-50%, -50%) scale(${lerp(0.6, 1.25, outBack(Math.min(1, ff * 1.6)))}) rotate(${lerp(0, 8, ff)}deg)` });
    // A finger: the scan button, the shutter, the page held and moved,
    // Save and Share, Share.
    const btn = middle(home.querySelector(".ph-btn")), sv = middle(save), sb = middle(shareBtn), pdf = pages[3];
    const TAPS = [[P.scanTap, btn], [P.shutter, { x: 195, y: 740 }], [P.saveTap, sv], [P.shareTap, sb]];
    let tx = 0, ty = 0, ta = 0, press = 0;
    TAPS.forEach(([c, p]) => {
      const w = prog(t, at(c) - 0.3, at(c) - 0.1) * (1 - prog(t, at(c) + 0.15, at(c) + 0.3));
      if (w > ta) { ta = w; tx = p.x; ty = p.y; press = Math.sin(Math.PI * prog(t, at(c) - 0.05, at(c) + 0.15)); }
    });
    const hold = prog(t, at(P.lift) - 0.25, at(P.lift) - 0.05) * (1 - prog(t, at(P.drop) + 0.05, at(P.drop) + 0.2));
    if (hold > ta) { const m = middle(pdf.n); ta = hold; tx = m.x; ty = m.y + 10; press = lift; }
    show(touch, ta * 0.95);
    style(touch, { left: `${tx}px`, top: `${ty}px`, transform: `scale(${1 - 0.18 * press})` });
  };
}

const extras = [];
if (CUT.phone) extras.push(phoneScene(CUT.phone));
if (CUT.desk.button) extras.push(deskShotScene(CUT.desk.button));
if (CUT.mail) extras.push(mailScene(CUT.mail));
if (CUT.search) extras.push(searchScene(CUT.search));
if (CUT.pdf) extras.push(pdfScene(CUT.pdf));
if (CUT.translate) extras.push(translateScene(CUT.translate));
if (CUT.sent) extras.push(sentScene(CUT.sent));
if (CUT.privacy) extras.push(privacyScene(CUT.privacy));
if (CUT.more) extras.push(moreScene(CUT.more));
if (CUT.end.cta) extras.push(ctaScene(CUT.end));

// MARK: The timeline

let TIME = 0;

function drawCaptions(t) {
  blocks.forEach((b) => {
    const live = t >= b.from - 0.01 && t < b.to + 0.25;
    show(b.node, live ? 1 - outQuart(prog(t, b.to, b.to + 0.22)) : 0);
    if (!live) return;
    b.node.style.transform = `translateY(${-24 * outQuart(prog(t, b.to, b.to + 0.22))}px)`;
    b.chunks.forEach(({ w, when }) => {
      const p = prog(t, when, when + 0.32);
      w.style.opacity = outQuart(p);
      w.style.transform = `translateY(${lerp(38, 0, outQuart(p))}px) scale(${lerp(0.9, 1, outBack(p))})`;
    });
  });
}

// Where the pointer goes and when it clicks: the invoice's paper plane as
// the voice says "Ein Klick", the chart's as it says "ChatGPT". The first
// flight takes its time; the second is quick.
const CLICKS = CUT.chat.clicks.map(at);
const FLY = [0.75, 0.42];
const LANDS = CLICKS.map((c, i) => c + 0.12 + (BUTTON && i > 0 ? 0.5 : FLY[i]));
// When each flight leaves the line; the button sends its two a beat apart.
const flightStart = (i) => (BUTTON && i > 0 ? CLICKS[1] + 0.12 + (i - 1) * 0.12 : CLICKS[i] + 0.12);
const flightLen = (i) => (BUTTON && i > 0 ? 0.5 : FLY[i]);
// Lena reads it, types, and answers, while WhatsApp is still in front.
const READ = LANDS[0] + 0.45, TYPING = LANDS[0] + 0.55, ANSWER = LANDS[0] + 1.1;
// When each chat comes to the front, and when all three fan out.
const WA_IN = at(CUT.chat.in), GPT_IN = at(CUT.chat.gptIn), FAN = at(CUT.chat.fan);
const centre = (node) => { const r = node.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; };
function sendButton(i, t) {
  const c = sendCards[i];
  const frac = SEND_FRAC[i];
  const left = 1080 * frac - CARD_W / 2;
  const top = LINE_Y + ropeY(frac, LINE_SAG) - 6;
  return { x: left + CARD_W - 13, y: top + c.offsetHeight - 13 };
}

function seek(t) {
  TIME = t;

  // The glows drift; the wallpaper takes over for the end card.
  style(blobA, { transform: `translate(${Math.sin(t * 0.35) * 60}px, ${Math.cos(t * 0.3) * 40}px)` });
  style(blobB, { transform: `translate(${Math.cos(t * 0.3) * 70}px, ${Math.sin(t * 0.25) * 50}px)` });
  const E = CUT.end;
  const wallIn = outQuart(prog(t, at(E.wall), at(E.wall) + 0.4));
  show(blobA, 1 - wallIn); show(blobB, 1 - wallIn);
  show(wall, wallIn); show(wallWash, wallIn);

  drawCaptions(t);

  // 1. The Desktop fills, Snapfly arrives in the menu bar, and every file
  // flies up onto the line; then a close look at the top of the screen.
  const D = CUT.desk;
  const scrIn = outQuart(prog(t, 0, 0.25));
  const scrOut = prog(t, at(D.out[0]), at(D.out[1]));
  // In the long cut the view pulls back out to show the Desktop left clear.
  const zoom = inOut(prog(t, at(D.zoom[0]), at(D.zoom[1]))) * (D.tidy ? 1 - inOut(prog(t, at(D.tidy), at(D.tidy) + 0.8)) : 1);
  show(screen, scrIn * (1 - scrOut));
  style(screen, { transform: `translateY(${lerp(40, 0, scrIn) - 120 * inOut(scrOut)}px) scale(${lerp(0.96, 1.0, scrIn) * lerp(1, 1.04, prog(t, 0.3, at(D.push))) * lerp(1, 1.62, zoom)})` });
  const mk = prog(t, at(D.mark), at(D.mark) + 0.39);
  show(mark, outQuart(mk));
  mark.style.transform = `scale(${lerp(0.2, 1, outBack(mk))})`;
  const gl = prog(t, at(D.mark) + 0.04, at(D.mark) + 0.84);
  show(markGlow, Math.sin(Math.PI * gl) * 0.9);
  markGlow.style.transform = `scale(${lerp(0.4, 1.6, gl)})`;
  deskRopePath.style.strokeDashoffset = 1100 * (1 - outQuart(prog(t, at(D.rope), at(D.rope) + 0.5)));
  files.forEach((d, i) => {
    const pop = prog(t, 0.05 + i * 0.07, 0.05 + i * 0.07 + 0.3);
    const frac = (d.spot + 0.6) / (SPOTS + 0.2);
    const hx = SW * frac - 52 + d.layer * 9;
    const hy = 56 + ropeY(frac, 26) - 4 + d.layer * 5;
    const start = at(D.sweep) + i * 0.035;
    const fly = inOut(prog(t, start, start + 0.7));
    const x = lerp(d.x, hx, fly), y = lerp(d.y, hy, fly) - Math.sin(Math.PI * fly) * 80;
    const rot = lerp(d.tilt, d.hangTilt, fly) + swing(t - start - 0.7, 8);
    show(d.f, outQuart(pop));
    style(d.f, { left: `${x}px`, top: `${y}px`, zIndex: String(d.layer + 1),
                 transform: `scale(${lerp(0.3, 1, outBack(pop)) * lerp(1, 0.86, fly)}) rotate(${rot}deg)` });
    d.f.querySelector(".name").style.opacity = 1 - fly;
    d.f.querySelector(".thumb").style.borderRadius = `${lerp(6, 11, fly)}px`;
  });

  if (hunter) {
    const stops = HUNT.map((i, k) => ({ x: files[i].x + 52, y: files[i].y + 40, t: at(D.hunt[k]) }));
    const p = pointerPath(t, { x: 700, y: 620 }, stops);
    show(hunter, prog(t, at(D.hunt[0]) - 0.6, at(D.hunt[0]) - 0.4) * (1 - prog(t, at(D.mark) - 0.3, at(D.mark))));
    style(hunter, { left: `${p.x - 12}px`, top: `${p.y - 8}px`, zIndex: "9", transform: `scale(${1 - 0.15 * p.press})` });
    HUNT.forEach((i, k) => {
      const on = t >= at(D.hunt[k]) && t < (k < HUNT.length - 1 ? at(D.hunt[k + 1]) : at(D.mark));
      style(files[i].f.querySelector(".name"), { background: on ? "#0A63D8" : "", textShadow: on ? "none" : "" });
      files[i].f.querySelector(".thumb").style.boxShadow = on ? "0 0 0 5px rgba(255,255,255,.6), 0 3px 8px rgba(0,0,0,.35)" : "";
    });
  }
  sparkles.forEach((k, i) => {
    const from = at(D.clean) + i * 0.14, p = prog(t, from, from + 0.9);
    show(k, Math.sin(Math.PI * p));
    k.style.transform = `scale(${lerp(0.2, 1.1, outBack(prog(t, from, from + 0.45)))}) rotate(${90 * p}deg)`;
  });

  // 2. Lena asks for the invoice in WhatsApp; one click on its paper plane
  // and it lands in the chat, she reads it and thanks. Then the chart into
  // ChatGPT, and the three chats fan out: any chat.
  const sIn = outQuart(prog(t, WA_IN, WA_IN + 0.4));
  const sOut = prog(t, at(CUT.chat.out[0]), at(CUT.chat.out[1]));
  show(sendRope, sIn * (1 - sOut));
  const fan = inOut(prog(t, FAN, FAN + 0.5));
  apps.forEach((a, k) => {
    let solo = 0, dx = 0, dy = 0;
    if (a === waApp) {
      const into = outQuart(prog(t, WA_IN, WA_IN + 0.32)), away = inOut(prog(t, GPT_IN, GPT_IN + 0.28));
      solo = into * (1 - away); dx = -90 * away; dy = lerp(90, 0, into);
    } else if (a === gptApp) {
      const into = outQuart(prog(t, GPT_IN, GPT_IN + 0.28));
      solo = into; dx = lerp(90, 0, into);
    }
    const shown = (t >= FAN ? lerp(solo, 1, fan) : solo) * (1 - sOut);
    show(a.w, shown);
    // Fanned out side by side at one width, each showing what it got.
    const fs = 330 / a.width, fr = [-4, 0, 4][k];
    const fx = [-358, 0, 358][k] + a.toMiddle[0], fy = [-20, 20, -20][k] + a.toMiddle[1];
    style(a.w, { zIndex: String(2 + k),
      transform: `translate(${lerp(dx, fx, fan)}px, ${lerp(dy, fy, fan) + 60 * inOut(sOut)}px) rotate(${lerp(0, fr, fan)}deg) scale(${lerp(1, fs, fan)})` });
  });
  // WhatsApp: room opens for the picture as it flies, the older messages
  // move up; it lands with grey ticks that turn blue, Lena types, answers.
  const open = outQuart(prog(t, CLICKS[0] + 0.12, CLICKS[0] + 0.4));
  waApp.meSlot.style.maxHeight = `${lerp(0, waApp.meSlot.scrollHeight, open)}px`;
  const land0 = prog(t, LANDS[0], LANDS[0] + 0.22);
  show(waApp.me, land0 > 0 ? 1 : 0);
  waApp.me.style.transform = `scale(${lerp(0.94, 1, outBack(land0))})`;
  waApp.sent.style.color = t >= READ ? "#53BDEB" : "#8696A0";
  const typing = t >= TYPING && t < ANSWER;
  show(waApp.online, typing ? 0 : 1); show(waApp.typing, typing ? 1 : 0);
  const ans = outQuart(prog(t, ANSWER, ANSWER + 0.25));
  waApp.replySlot.style.maxHeight = `${lerp(0, waApp.replySlot.scrollHeight, ans)}px`;
  show(waApp.reply, ans);
  // ChatGPT: the chart lands, the answer follows. Claude shows its own
  // finished exchange when the three fan out.
  const land1 = prog(t, LANDS[1], LANDS[1] + 0.22);
  show(gptApp.me, land1 > 0 ? 1 : 0);
  gptApp.me.style.transform = `scale(${lerp(0.92, 1, outBack(land1))})`;
  const said = outQuart(prog(t, LANDS[1] + 0.3, LANDS[1] + 0.55));
  show(gptApp.reply, said);
  gptApp.reply.style.transform = `translateY(${lerp(14, 0, said)}px)`;
  show(claudeApp.me, 1); show(claudeApp.reply, 1);
  if (chatBtn) {
    gptApp.pics.forEach((p, k) => show(p, t >= flightStart(k + 1) + 0.5 ? 1 : 0));
    const sent = t >= CLICKS[1] + 0.1;
    show(chatBtn.querySelector(".plane"), sent ? 0 : 1); show(chatBtn.querySelector(".done"), sent ? 1 : 0);
    show(chatBtn, 1 - prog(t, CLICKS[1] + 0.8, CLICKS[1] + 1.1));
    chatBtn.style.transform = `scale(${1 - 0.06 * Math.sin(Math.PI * prog(t, CLICKS[1] - 0.05, CLICKS[1] + 0.15))})`;
    chatBtn.style.boxShadow = `0 10px 28px rgba(0,0,0,.22), 0 0 0 ${ring(t, GPT_IN + 0.5, CLICKS[1] - 0.3)}px rgba(10,132,255,.3)`;
  }
  sendCards.forEach((c, i) => {
    const frac = SEND_FRAC[i];
    const cx = 1080 * frac;
    const drop = prog(t, WA_IN + i * 0.08, WA_IN + 0.4 + i * 0.08);
    const gone = BUTTON ? t >= flightStart(i) : i < CLICKS.length && t >= CLICKS[i] + 0.12;
    show(c, outQuart(drop) * (1 - sOut) * (gone ? 0 : 1));
    style(c, { left: `${cx - CARD_W / 2}px`, top: `${LINE_Y + ropeY(frac, LINE_SAG) - 6 - lerp(70, 0, outQuart(drop))}px`,
               transform: `rotate(${[-4, 3, -3][i] + swing(t - WA_IN - 0.4 - i * 0.08, 6, 0.9, 1.2)}deg)` });
  });
  // The flights: up off the line, a tilt toward the reading end, and down
  // into the chat exactly where the picture lands.
  const targets = BUTTON ? [waApp.pic, ...gptApp.pics] : [waApp.pic, gptApp.pic];
  flyers.forEach((g, i) => {
    const start = flightStart(i);
    const f = prog(t, start, start + flightLen(i));
    show(g, f > 0 && f < 1 ? 1 : 0);
    if (f <= 0 || f >= 1) return;
    const frac = SEND_FRAC[i];
    const fromX = 1080 * frac - CARD_W / 2, fromY = LINE_Y + ropeY(frac, LINE_SAG) - 6;
    const r = targets[i].getBoundingClientRect();
    const h = g.offsetHeight;
    const scale = r.width / CARD_W;
    const toX = r.left + r.width / 2 - CARD_W / 2, toY = r.top + r.height / 2 - h / 2;
    const e = inOut(f);
    const x = lerp(fromX, toX, e) + Math.sin(Math.PI * e) * 70;
    const y = lerp(fromY, toY, e) - Math.sin(Math.PI * e) * (i === 0 ? 170 : 110);
    style(g, { left: `${x}px`, top: `${y}px`, zIndex: "8", transform: `rotate(${-9 * Math.sin(Math.PI * e)}deg) scale(${lerp(1, scale, e)})` });
    g.querySelector(".glass").style.padding = `${lerp(6, 0, e)}px`;
  });
  // The pointer: to each paper plane in turn, a press, a ripple.
  const ptrIn = prog(t, WA_IN - 0.05, WA_IN + 0.15) * (1 - prog(t, CLICKS[1] + 0.3, CLICKS[1] + 0.55));
  let px = 900, py = 1500, press = 0, rp = -1;
  for (let k = 0; k < CLICKS.length; k++) {
    const target = BUTTON && k === 1 ? centre(chatBtn.querySelector(".cb-go")) : sendButton(k, t);
    const from = k === 0 ? { x: 920, y: 1560 } : sendButton(k - 1, t);
    const move = inOut(prog(t, CLICKS[k] - 0.4, CLICKS[k] - 0.05));
    if (t >= CLICKS[k] - 0.4 || k === 0) {
      px = lerp(from.x, target.x, move); py = lerp(from.y, target.y, move);
      press = Math.sin(Math.PI * prog(t, CLICKS[k] - 0.05, CLICKS[k] + 0.15));
      if (t >= CLICKS[k] - 0.05) rp = prog(t, CLICKS[k], CLICKS[k] + 0.5);
    }
  }
  show(pointer, ptrIn);
  style(pointer, { left: `${px - 12}px`, top: `${py - 8}px`, zIndex: "6", transform: `scale(${1 - 0.15 * press})` });
  show(ripple, rp >= 0 && rp < 1 ? 1 - rp : 0);
  style(ripple, { left: `${px - 50 * (1 + rp)}px`, top: `${py - 50 * (1 + rp)}px`, width: `${100 * (1 + rp)}px`, height: `${100 * (1 + rp)}px` });

  // 3. The invoice: the name and the account number light up as they are
  // said, then everything private is covered.
  const K = CUT.doc;
  const dIn = outQuart(prog(t, at(K.in[0]), at(K.in[1])));
  const dOut = prog(t, at(K.out[0]), at(K.out[1]));
  show(doc, dIn * (1 - dOut));
  const dScale = lerp(0.94, 1, dIn) * lerp(1, 1.03, prog(t, at(K.in[0]) + 0.35, at(K.out[0]) - 0.05));
  if (K.send) {
    // The long cut sends it: a press on its paper plane, and off it flies.
    const fly = inOut(prog(t, at(K.send) + 0.15, at(K.send) + 0.9));
    style(doc, { left: "110px", top: "640px", transform: `translate(${1050 * fly}px, ${lerp(70, 0, dIn) - 40 * fly - Math.sin(Math.PI * fly) * 40}px) rotate(${-10 * fly}deg) scale(${dScale * lerp(1, 0.45, fly)})` });
    const sb = prog(t, at(K.send) - 0.3, at(K.send));
    show(docSend, outQuart(sb));
    docSend.style.transform = `scale(${lerp(0.3, 1, outBack(sb)) * (1 - 0.15 * Math.sin(Math.PI * prog(t, at(K.send) - 0.05, at(K.send) + 0.15)))})`;
  } else {
    style(doc, { left: "110px", top: "640px", transform: `translateY(${lerp(70, 0, dIn) - 50 * inOut(dOut)}px) scale(${dScale})` });
  }
  fields.forEach((fd, i) => {
    const lit = i === NAME ? prog(t, at(K.name), at(K.name) + 0.25) : i === IBAN ? prog(t, at(K.iban), at(K.iban) + 0.25) : 0;
    const coverAt = at(K.cover) + i * 0.15;
    const cover = outQuart(prog(t, coverAt, coverAt + 0.3));
    show(fd.querySelector(".mark-hl"), outQuart(lit) * (1 - cover));
    fd.querySelector(".ink").style.transform = `scaleX(${cover})`;
  });
  const lk = prog(t, at(K.lock), at(K.lock) + 0.3);
  show(lock, outQuart(lk));
  lock.style.transform = `scale(${lerp(0.3, 1, outBack(lk))})`;

  // The long cut's own scenes.
  extras.forEach((draw) => draw(t));

  // 4. The end card: the icon lands as the name is said, then the offer.
  const ei = prog(t, at(E.icon), at(E.icon) + 0.55);
  show(endIcon, outQuart(ei));
  style(endIcon, { left: "390px", top: `${430 - 140 * (1 - outBack(ei))}px`,
    transform: `scale(${lerp(0.55, 1, outBack(ei))}) rotate(${lerp(-16, 0, outQuart(ei))}deg)`,
    filter: `drop-shadow(0 30px 50px rgba(40,0,50,${0.45 * outQuart(ei)}))` });
  const ew = prog(t, at(E.word), at(E.word) + 0.46);
  show(endWord, outQuart(ew));
  style(endWord, { top: "780px", transform: `translateY(${lerp(44, 0, outQuart(ew))}px)`, letterSpacing: `${lerp(0.12, -0.04, outQuart(ew))}em` });
  const et = prog(t, at(E.tag), at(E.tag) + 0.5);
  show(endTag, outQuart(et) * (E.cta ? 1 - prog(t, at(E.cta) - 0.2, at(E.cta)) : 1));
  style(endTag, { top: "1000px", transform: `translateY(${lerp(30, 0, outQuart(et))}px)` });
  const fr = prog(t, at(E.free), at(E.free) + 0.41);
  show(free, outQuart(fr));
  style(free, { left: "540px", top: "1205px", transform: `translateX(-50%) scale(${lerp(0.7, 1, outBack(fr))})` });
  const ur = prog(t, at(E.url), at(E.url) + 0.5);
  show(url, outQuart(ur));
  style(url, { top: soon ? "1398px" : "1385px" });
  if (soon) {
    const so = prog(t, at(E.soon), at(E.soon) + 0.45);
    show(soon, outQuart(so));
    style(soon, { top: "1335px", transform: `translateY(${lerp(24, 0, outQuart(so))}px)` });
  }
  show(legal, outQuart(ur) * 0.8);
  style(legal, { top: "1450px" });
  const push = 1 + 0.03 * prog(t, at(E.icon) + 0.3, DURATION);
  [endIcon, endWord, endTag].forEach((n) => { n.style.scale = String(push); });
}

window.seek = seek;
window.DURATION = DURATION;
document.fonts.ready.then(() => { seek(0); window.READY = true; });

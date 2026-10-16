// The Snapfly Instagram ad: a 21.5-second, 1080 × 1920 timeline in German,
// timed to its voice. seek(t) draws the frame at t seconds; render.js steps
// through it at 30 frames a second. DATA is written into the page by
// build.py. The voice starts VO seconds in; every cue below is a moment in
// the voice plus VO.
"use strict";

const T = DATA.text;
const DURATION = 21.5;
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
const BLOCKS = [
  { from: 0, to: at(2.85), lines: [[["Schon wieder", 0.05, "small"]], [["30 ", at(0.6), "grad"], ["Screenshots", at(0.95), "grad"]], [["auf dem ", at(1.65), "small"], ["Desktop?", at(2.0)]]] },
  { from: at(2.86), to: at(4.62), lines: [[["Mit Snapfly", at(2.86), "small"]], [["hängt jeder", at(3.55)]], [["Screenshot", at(3.95)]]] },
  { from: at(4.66), to: at(6.3), lines: [[["sofort an", at(4.66), "small"]], [["einer Leine,", at(5.15), "grad"]]] },
  { from: at(6.38), to: at(7.62), lines: [[["oben am", at(6.38), "small"]], [["Bildschirm.", at(6.75), "grad"]]] },
  { from: at(7.81), to: at(9.95), lines: [[["Ein Klick,", at(7.81), "grad"]], [["und er ist", at(8.6)]], [["im Chat.", at(9.05)]]] },
  { from: at(10.15), to: at(12.9), lines: [[["WhatsApp.", at(10.15)]], [["ChatGPT.", at(10.99)]], [["Egal wo.", at(12.09), "grad"]]] },
  { from: at(13.26), to: at(14.9), lines: [[["Namen und", at(13.26), "small"]], [["Kontonummern?", at(13.75), "grad"]]] },
  { from: at(15.1), to: at(16.62), lines: [[["Werden", at(15.1), "small"]], [["automatisch", at(15.35), "grad"]], [["verdeckt.", at(15.95)]]] },
];
const blocks = BLOCKS.map((b) => {
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

// MARK: Scene 2, one click and it is in the chat

const LINE_Y = 600, LINE_SAG = 38;
const sendRope = el("div", "rope light", document.body, `<svg width="1080" height="120"><path d="${ropePath(1080, LINE_SAG)}"/></svg>`);
style(sendRope, { left: "0", top: `${LINE_Y}px` });
const CARD_W = 180;
const SEND_KINDS = ["invoice", "chart", "sunset"];
const SEND_FRAC = [0.2, 0.5, 0.8];
const sendCards = SEND_KINDS.map((k) => {
  const c = el("div", "card", document.body, `<span class="clip"></span><div class="glass"><div class="img">${DATA.artByKind[k]}</div></div><div class="send">${ICON_PLANE}</div>`);
  style(c, { width: `${CARD_W}px` });
  return c;
});
const flyers = SEND_KINDS.map((k) => {
  const g = el("div", "card", document.body, `<div class="glass"><div class="img">${DATA.artByKind[k]}</div></div>`);
  style(g, { width: `${CARD_W}px`, transformOrigin: "50% 50%" });
  return g;
});
const CHAT_X = 110, CHAT_W = 860, CHAT_Y = 820, CHAT_H = 640;
const chat = el("div", "chat", document.body, `<div class="titlebar"><span class="lights"><i></i><i></i><i></i></span></div>`);
style(chat, { left: `${CHAT_X}px`, top: `${CHAT_Y}px`, width: `${CHAT_W}px`, height: `${CHAT_H}px` });
const titlebar = chat.querySelector(".titlebar");
const APPS = ["WhatsApp", "ChatGPT", "Telegram", "Claude", "Slack", "Messages", "Telegram"];
const titles = APPS.map((name) => el("span", "name", titlebar, name));
const asks = T.asks.map((text) => {
  const b = el("div", "bubble in", chat, text);
  style(b, { top: "112px", left: "32px" });
  return b;
});
const IMG_W = 300, IMG_X = CHAT_W - 32 - IMG_W, IMG_Y = 232;
const landed = SEND_KINDS.map((k) => {
  const b = el("div", "bubble-img", chat, DATA.artByKind[k]);
  style(b, { left: `${IMG_X}px`, top: `${IMG_Y}px`, width: `${IMG_W}px` });
  return b;
});
const composer = el("div", "composer", chat, `<div class="field">${T.message}</div><div class="go">${ICON_PLANE}</div>`);
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

// MARK: Scene 4, the end card

const endIcon = el("img", "end-icon"); endIcon.src = DATA.icon;
const endWord = el("div", "end-word", document.body, "Snapfly");
const endTag = el("div", "end-tag", document.body, T.tagline);
const free = el("div", "free", document.body, T.free);
const url = el("div", "url", document.body, DATA.url);

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

// Where the pointer goes and when it clicks: each card's paper plane, as the
// voice names the chat.
const CLICKS = [at(7.81), at(10.99), at(12.09)];
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
  const wallIn = outQuart(prog(t, at(16.5), at(16.9)));
  show(blobA, 1 - wallIn); show(blobB, 1 - wallIn);
  show(wall, wallIn); show(wallWash, wallIn);

  drawCaptions(t);

  // 1. The Desktop fills, Snapfly arrives in the menu bar, and every file
  // flies up onto the line; then a close look at the top of the screen.
  const scrIn = outQuart(prog(t, 0, 0.25));
  const scrOut = prog(t, at(7.45), at(7.8));
  const zoom = inOut(prog(t, at(6.3), at(7.1)));
  show(screen, scrIn * (1 - scrOut));
  style(screen, { transform: `translateY(${lerp(40, 0, scrIn) - 120 * inOut(scrOut)}px) scale(${lerp(0.96, 1.0, scrIn) * lerp(1, 1.04, prog(t, 0.3, at(2.8))) * lerp(1, 1.62, zoom)})` });
  const mk = prog(t, at(2.86), at(3.25));
  show(mark, outQuart(mk));
  mark.style.transform = `scale(${lerp(0.2, 1, outBack(mk))})`;
  const gl = prog(t, at(2.9), at(3.7));
  show(markGlow, Math.sin(Math.PI * gl) * 0.9);
  markGlow.style.transform = `scale(${lerp(0.4, 1.6, gl)})`;
  deskRopePath.style.strokeDashoffset = 1100 * (1 - outQuart(prog(t, at(3.6), at(4.1))));
  files.forEach((d, i) => {
    const pop = prog(t, 0.05 + i * 0.07, 0.05 + i * 0.07 + 0.3);
    const frac = (d.spot + 0.6) / (SPOTS + 0.2);
    const hx = SW * frac - 52 + d.layer * 9;
    const hy = 56 + ropeY(frac, 26) - 4 + d.layer * 5;
    const start = at(3.85) + i * 0.035;
    const fly = inOut(prog(t, start, start + 0.7));
    const x = lerp(d.x, hx, fly), y = lerp(d.y, hy, fly) - Math.sin(Math.PI * fly) * 80;
    const rot = lerp(d.tilt, d.hangTilt, fly) + swing(t - start - 0.7, 8);
    show(d.f, outQuart(pop));
    style(d.f, { left: `${x}px`, top: `${y}px`, zIndex: String(d.layer + 1),
                 transform: `scale(${lerp(0.3, 1, outBack(pop)) * lerp(1, 0.86, fly)}) rotate(${rot}deg)` });
    d.f.querySelector(".name").style.opacity = 1 - fly;
    d.f.querySelector(".thumb").style.borderRadius = `${lerp(6, 11, fly)}px`;
  });

  // 2. One click on a card's paper plane, and it flies into the chat. Then
  // the same in ChatGPT, and in any chat.
  const sIn = outQuart(prog(t, at(7.6), at(8.0)));
  const sOut = prog(t, at(12.85), at(13.2));
  show(sendRope, sIn * (1 - sOut));
  show(chat, sIn * (1 - sOut));
  style(chat, { transform: `translateY(${lerp(90, 0, sIn) + 60 * inOut(sOut)}px)` });
  // Which chat is in front: WhatsApp, then ChatGPT, then a quick run of others.
  let app = t < CLICKS[1] - 0.05 ? 0 : t < CLICKS[2] ? 1 : 2 + Math.min(4, Math.floor((t - CLICKS[2]) / 0.16));
  titles.forEach((n, k) => show(n, k === app ? 1 : 0));
  const thread = t < CLICKS[1] - 0.05 ? 0 : t < CLICKS[2] - 0.05 ? 1 : 2;
  asks.forEach((b, k) => {
    const into = prog(t, k === 0 ? at(7.9) : CLICKS[k] - 0.3, (k === 0 ? at(7.9) : CLICKS[k] - 0.3) + 0.25);
    show(b, k === thread ? outQuart(into) : 0);
    b.style.transform = `scale(${lerp(0.88, 1, outBack(into))})`;
  });
  sendCards.forEach((c, i) => {
    const frac = SEND_FRAC[i];
    const cx = 1080 * frac;
    const drop = prog(t, at(7.6) + i * 0.08, at(8.0) + i * 0.08);
    const gone = t >= CLICKS[i] + 0.12;
    show(c, outQuart(drop) * (1 - sOut) * (gone ? 0 : 1));
    style(c, { left: `${cx - CARD_W / 2}px`, top: `${LINE_Y + ropeY(frac, LINE_SAG) - 6 - lerp(70, 0, outQuart(drop))}px`,
               transform: `rotate(${[-4, 3, -3][i] + swing(t - at(8.0) - i * 0.08, 6, 0.9, 1.2)}deg)` });
  });
  // The flights: up off the line, a tilt toward the reading end, and down
  // into the chat as a picture.
  flyers.forEach((g, i) => {
    const start = CLICKS[i] + 0.12;
    const f = prog(t, start, start + 0.78);
    const frac = SEND_FRAC[i];
    const fromX = 1080 * frac - CARD_W / 2, fromY = LINE_Y + ropeY(frac, LINE_SAG) - 6;
    const chatY = CHAT_Y + lerp(90, 0, sIn);
    const scale = IMG_W / CARD_W;
    const toX = CHAT_X + IMG_X + (IMG_W - CARD_W) / 2, toY = chatY + IMG_Y + (sendCards[i].offsetHeight * scale - sendCards[i].offsetHeight) / 2;
    const e = inOut(f);
    const x = lerp(fromX, toX, e) + Math.sin(Math.PI * e) * 70;
    const y = lerp(fromY, toY, e) - Math.sin(Math.PI * e) * 170;
    show(g, f > 0 && f < 1 ? 1 : 0);
    style(g, { left: `${x}px`, top: `${y}px`, zIndex: "5", transform: `rotate(${-9 * Math.sin(Math.PI * e)}deg) scale(${lerp(1, scale, e)})` });
    g.querySelector(".glass").style.padding = `${lerp(6, 0, e)}px`;
  });
  landed.forEach((b, i) => {
    const land = prog(t, CLICKS[i] + 0.9, CLICKS[i] + 1.15);
    show(b, i === thread && land > 0 ? 1 : 0);
    b.style.transform = `scale(${lerp(0.94, 1, outBack(land))})`;
  });
  // The pointer: to each paper plane in turn, a press, a ripple.
  const ptrIn = prog(t, at(7.55), at(7.75)) * (1 - prog(t, at(12.6), at(12.85)));
  let px = 900, py = 1500, press = 0, rp = -1;
  for (let k = 0; k < 3; k++) {
    const target = sendButton(k, t);
    const from = k === 0 ? { x: 920, y: 1560 } : sendButton(k - 1, t);
    const move = inOut(prog(t, CLICKS[k] - (k === 0 ? 0.4 : 0.45), CLICKS[k] - 0.05));
    if (t >= CLICKS[k] - (k === 0 ? 0.4 : 0.45) || k === 0) {
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
  const dIn = outQuart(prog(t, at(13.05), at(13.45)));
  const dOut = prog(t, at(16.45), at(16.8));
  show(doc, dIn * (1 - dOut));
  style(doc, { left: "110px", top: "640px", transform: `translateY(${lerp(70, 0, dIn) - 50 * inOut(dOut)}px) scale(${lerp(0.94, 1, dIn) * lerp(1, 1.03, prog(t, at(13.4), at(16.4)))})` });
  fields.forEach((fd, i) => {
    const lit = i === NAME ? prog(t, at(13.3), at(13.55)) : i === IBAN ? prog(t, at(13.8), at(14.05)) : 0;
    const coverAt = at(15.3) + i * 0.15;
    const cover = outQuart(prog(t, coverAt, coverAt + 0.3));
    show(fd.querySelector(".mark-hl"), outQuart(lit) * (1 - cover));
    fd.querySelector(".ink").style.transform = `scaleX(${cover})`;
  });
  const lk = prog(t, at(16.0), at(16.3));
  show(lock, outQuart(lk));
  lock.style.transform = `scale(${lerp(0.3, 1, outBack(lk))})`;

  // 4. The end card: the icon lands as the name is said, then the offer.
  const ei = prog(t, at(16.7), at(17.25));
  show(endIcon, outQuart(ei));
  style(endIcon, { left: "390px", top: `${430 - 140 * (1 - outBack(ei))}px`,
    transform: `scale(${lerp(0.55, 1, outBack(ei))}) rotate(${lerp(-16, 0, outQuart(ei))}deg)`,
    filter: `drop-shadow(0 30px 50px rgba(40,0,50,${0.45 * outQuart(ei)}))` });
  const ew = prog(t, at(16.84), at(17.3));
  show(endWord, outQuart(ew));
  style(endWord, { top: "780px", transform: `translateY(${lerp(44, 0, outQuart(ew))}px)`, letterSpacing: `${lerp(0.12, -0.04, outQuart(ew))}em` });
  const et = prog(t, at(17.3), at(17.8));
  show(endTag, outQuart(et));
  style(endTag, { top: "1000px", transform: `translateY(${lerp(30, 0, outQuart(et))}px)` });
  const fr = prog(t, at(17.99), at(18.4));
  show(free, outQuart(fr));
  style(free, { left: "540px", top: "1205px", transform: `translateX(-50%) scale(${lerp(0.7, 1, outBack(fr))})` });
  const ur = prog(t, at(18.9), at(19.4));
  show(url, outQuart(ur));
  style(url, { top: "1385px" });
  const push = 1 + 0.03 * prog(t, at(17), DURATION);
  [endIcon, endWord, endTag].forEach((n) => { n.style.scale = String(push); });
}

window.seek = seek;
window.DURATION = DURATION;
document.fonts.ready.then(() => { seek(0); window.READY = true; });

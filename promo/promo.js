// The Snapfly motion graphic: a 21-second, 1080 × 1920 timeline. seek(t)
// draws the frame at t seconds; render.js steps through it at 30 frames a
// second and hands each frame to ffmpeg. DATA (words and pictures in one
// language) is written into the page by build.py.
"use strict";

const T = DATA.text;
const RTL = DATA.dir === "rtl";
const DURATION = 21;
document.body.classList.toggle("rtl", RTL);
document.documentElement.lang = DATA.lang;

// MARK: Timing

const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const prog = (t, a, b) => clamp((t - a) / (b - a));
const lerp = (a, b, x) => a + (b - a) * x;
const outQuart = (x) => 1 - Math.pow(1 - x, 4);
const outExpo = (x) => (x >= 1 ? 1 : 1 - Math.pow(2, -10 * x));
const inOut = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
const outBack = (x) => { const c = 1.6; return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2); };
// In and out: 0 before a, rising to 1 by a + fade, falling to 0 from b - fade to b.
const inOutWindow = (t, a, b, fade = 0.35) => Math.min(outQuart(prog(t, a, a + fade)), 1 - prog(t, b - fade, b));
// A swing that settles, for photos landing on a clip.
const swing = (tau, amp = 7, freq = 2.1, damp = 2.6) => (tau <= 0 ? 0 : amp * Math.exp(-damp * tau) * Math.sin(2 * Math.PI * freq * tau));
// Mirror x for right-to-left: positions are authored for left to right.
const X = (x, w = 0) => (RTL ? 1080 - x - w : x);

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

const ICON_PLANE = '<svg viewBox="0 0 24 24"><path d="M4.1 11.3 19.6 4.6c.6-.3 1.1.3.9.9l-6.7 15.5c-.3.6-1.1.5-1.3-.1l-2-5.7a1 1 0 0 0-.6-.6L4.2 12.6c-.6-.2-.7-1-.1-1.3Z" fill="#fff"/><path d="m10.4 13.6 9.4-8.8" stroke="rgba(0,113,227,.55)" stroke-width="1.4" stroke-linecap="round" fill="none"/></svg>';
const ICON_LOCK = '<svg viewBox="0 0 24 24"><rect x="5.5" y="10.5" width="13" height="9.5" rx="2.4" fill="#fff"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5" stroke="#fff" stroke-width="2" fill="none"/></svg>';
const POINTER = '<svg viewBox="0 0 24 24"><path d="M5 3.2v15.6l4.1-3.7 2.6 6 2.7-1.2-2.6-5.9 5.6-.3Z" fill="#000" stroke="#fff" stroke-width="1.3" stroke-linejoin="round"/></svg>';
const ropePath = (w, sag) => `M0 0 Q${w / 2} ${sag * 2} ${w} 0`;

// Background
const bg = el("div", "layer", document.body); bg.id = "bg";
const blobA = el("div", "blob", bg); blobA.id = "blobA";
const blobB = el("div", "blob", bg); blobB.id = "blobB";
const wall = el("div", "layer"); wall.id = "wall";
const wallWash = el("div", "layer"); wallWash.id = "wallWash";

// Captions, one per scene
const caps = {};
for (const key of ["problem", "line", "private", "send", "menu"]) {
  caps[key] = el("div", "cap", document.body, T["cap_" + key]);
}

// MARK: Scene 1, the icon takes off

const streak = el("div", "streak");
const streak2 = el("div", "streak");
const burst = el("div", "burst");
const icon = el("img"); icon.id = "icon"; icon.src = DATA.icon;
const word = el("div", "word", document.body, "Snapfly");
style(word, { top: "1150px", fontSize: "140px", fontFamily: "Inter, sans-serif" });

// MARK: Scenes 2 and 3, a cluttered Desktop swept onto a line

const screen = el("div", "screen");
style(screen, { left: "60px", top: "640px", width: "960px", height: "640px" });
el("div", "wall layer", screen).style.background = "radial-gradient(95% 60% at 0% 0%, rgba(255,196,92,.95), rgba(255,196,92,0) 62%), radial-gradient(80% 55% at 100% 100%, rgba(178,52,214,.95), rgba(178,52,214,0) 72%), linear-gradient(160deg, #FF8A5C 0%, #FF5E62 40%, #D9449A 72%, #B234D6 100%)";
const mb = el("div", "menubar", screen);
style(el("i", "", mb), { left: RTL ? "auto" : "22px", right: RTL ? "22px" : "auto", width: "70px" });
style(el("i", "", mb), { left: RTL ? "auto" : "110px", right: RTL ? "110px" : "auto", width: "120px", opacity: ".6" });
const deskRope = el("div", "rope", screen, `<svg width="960" height="120"><path d="${ropePath(960, 34)}"/></svg>`);
style(deskRope, { left: "0", top: "70px" });
const deskRopePath = deskRope.querySelector("path");
const ROPE_LEN = 1000;
deskRopePath.style.strokeDasharray = ROPE_LEN;

const FILES = 8;
const files = [];
for (let i = 0; i < FILES; i++) {
  const f = el("div", "file", screen,
    `<div class="thumb">${DATA.art[i % DATA.art.length]}</div><div class="name">${T.file.replace("{n}", String(41 + i))}</div>`);
  files.push(f);
}
// Where each file lies on the Desktop, and where it hangs on the rope.
const deskSpots = [[760, 90], [600, 110], [780, 300], [620, 320], [440, 190], [800, 470], [610, 500], [430, 400]];
const deskTilts = [-6, 4, 3, -5, 7, -3, 5, -7];
const hangTilts = [-4, 3, -2, 4, -3, 2, -4, 3];

// MARK: Scene 4, private details covered

const sw = el("div", "switch", document.body, `<div class="track"><div class="knob"></div></div><span>${T.hide}</span>`);
const swTrack = sw.querySelector(".track"), swKnob = sw.querySelector(".knob");
const inv = DATA.invoice;
const field = (text, ltr) => `<span class="pd${ltr ? " ltr" : ""}"><span class="txt">${text}</span><span class="ink"></span></span>`;
const doc = el("div", "doc", document.body, `
  <div class="bar"><span class="lights"><i></i><i></i><i></i></span></div>
  <div class="body">
    <div class="top"><div><div class="title">${inv.title}</div><div class="dim">${inv.date}</div></div>
      <div style="text-align:end"><div class="title">${inv.total_v}</div><div class="dim">${inv.total}</div></div></div>
    <div class="label">${inv.bill}</div>
    <div>${field(inv.name)}</div>
    <div>${field(inv.street + " · " + inv.city)}</div>
    <div>${field(inv.email, true)}</div>
    <div>${field(inv.phone, true)}</div>
    <div class="items">${inv.items.map(([a, b]) => `<div><span>${a}</span><span class="ltr">${b}</span></div>`).join("")}</div>
    <div class="dim">${inv.pay}</div>
    <div>${field(inv.iban, true)}</div>
  </div>`);
const inks = [...doc.querySelectorAll(".ink")];
const lock = el("div", "lock", doc, ICON_LOCK);
style(lock, { left: RTL ? "40px" : "auto", right: RTL ? "auto" : "40px", bottom: "36px" });

// MARK: Scene 5, everything into the chat with one click

const lineRope = el("div", "rope light", document.body, `<svg width="1080" height="160"><path d="${ropePath(1080, 46)}"/></svg>`);
style(lineRope, { left: "0", top: "520px" });
const SEND = 4;
const sendCards = [];
for (let i = 0; i < SEND; i++) {
  const c = el("div", "card", document.body, `<span class="clip"></span><div class="glass"><div class="img">${DATA.art[i]}</div></div>`);
  style(c, { width: "176px" });
  sendCards.push(c);
}
const tag = el("div", "tag", document.body, ICON_PLANE);
const tagPill = el("div", "pill", document.body, T.send_all);
const ripple = el("div", "ripple");
// The chat sits high enough that the reply stays above the captions TikTok
// and Instagram draw over the bottom of the video.
const CHAT_LEFT = 110, CHAT_WIDTH = 860, CHAT_TOP = 820, ALBUM_TOP = 270;
const chat = el("div", "chat", document.body,
  `<div class="titlebar"><span class="lights"><i></i><i></i><i></i></span>${T.chat_title}</div>`);
style(chat, { left: `${X(CHAT_LEFT, CHAT_WIDTH)}px`, top: `${CHAT_TOP}px`, width: `${CHAT_WIDTH}px`, height: "730px" });
const ask = el("div", "bubble in", chat, T.chat_in);
style(ask, { top: "110px", [RTL ? "right" : "left"]: "32px" });
const album = el("div", "album", chat, DATA.art.slice(0, SEND).map((a) => `<div class="cell">${a}</div>`).join(""));
style(album, { top: `${ALBUM_TOP}px`, [RTL ? "left" : "right"]: "32px", width: "460px" });
const cells = [...album.children];
const typing = el("div", "bubble in typing", chat, "<i></i><i></i><i></i>");
const answer = el("div", "bubble in", chat, T.chat_reply);
style(typing, { top: "610px", [RTL ? "right" : "left"]: "32px" });
style(answer, { top: "610px", [RTL ? "right" : "left"]: "32px" });
const ghosts = sendCards.map(() => {
  const g = el("div", "card", document.body, `<div class="glass"><div class="img"></div></div>`);
  return g;
});
ghosts.forEach((g, i) => { g.querySelector(".img").innerHTML = DATA.art[i]; style(g, { width: "176px", transformOrigin: "0 0" }); });
// Where each card hangs on the send line, as a fraction of the width: spread
// from the left edge to just before the tag.
const sendFrac = (i) => (105 + i * ((1080 - 365 - 105) / (SEND - 1))) / 1080;

// MARK: Scene 6, hold for the menu

const menuRope = el("div", "rope light", document.body, `<svg width="1080" height="160"><path d="${ropePath(1080, 40)}"/></svg>`);
style(menuRope, { left: "0", top: "540px" });
const menuCards = ["map", "calendar", "sunset"].map((k, i) => {
  const c = el("div", "card", document.body, `<span class="clip"></span><div class="glass"><div class="img">${DATA.artByKind[k]}</div></div>`);
  style(c, { width: "250px" });
  return c;
});
const menu = el("div", "menu", document.body, "");
const hl = el("div", "hl", menu);
const items = [];
T.menu.forEach((label, i) => {
  if (label === "-") { el("div", "sep", menu); return; }
  const it = el("div", "item", menu, label);
  items.push(it);
});
const pdf = el("div", "pdf", document.body, `<div class="fold"></div><div class="lines" style="padding-top:70px"><i></i><i style="width:60%"></i><i></i><i style="width:75%"></i><i></i></div><div class="badge">PDF</div>`);
const pointer = el("div", "pointer", document.body, POINTER);
const ring = el("div", "ring", document.body, `<svg viewBox="0 0 120 120"><circle cx="60" cy="60" r="50" transform="rotate(-90 60 60)"/></svg>`);
const ringCircle = ring.querySelector("circle");
const RING_LEN = 2 * Math.PI * 50;
ringCircle.style.strokeDasharray = RING_LEN;

// MARK: Scene 7, the end card

const endIcon = el("img"); endIcon.src = DATA.icon; style(endIcon, { position: "absolute", width: "300px", height: "300px" });
const endWord = el("div", "word end-word", document.body, "Snapfly"); style(endWord, { top: "780px", fontFamily: "Inter, sans-serif" });
const endTag = el("div", "word end-tag", document.body, T.tagline); style(endTag, { top: "980px" });
const free = el("div", "free", document.body, T.free);
const url = el("div", "word url", document.body, "mgrd281.github.io/Screenshots"); style(url, { top: "1400px" });

// MARK: The timeline

function caption(node, a, b) {
  const o = inOutWindow(TIME, a, b, 0.4);
  show(node, o);
  node.style.transform = `translateY(${lerp(26, 0, outQuart(prog(TIME, a, a + 0.5)))}px)`;
}

let TIME = 0;
function seek(t) {
  TIME = t;

  // Background glow drifts all the way through.
  style(blobA, { transform: `translate(${Math.sin(t * 0.35) * 60}px, ${Math.cos(t * 0.3) * 40}px)` });
  style(blobB, { transform: `translate(${Math.cos(t * 0.3) * 70}px, ${Math.sin(t * 0.25) * 50}px)` });
  show(blobA, lerp(0.35, 1, outQuart(prog(t, 0.2, 1.4))) * (1 - prog(t, 17.2, 17.9)));
  show(blobB, lerp(0.2, 1, outQuart(prog(t, 0.6, 1.8))) * (1 - prog(t, 17.2, 17.9)));
  const wallIn = outQuart(prog(t, 17.3, 18.0));
  show(wall, wallIn); show(wallWash, wallIn);

  // 1. Streaks of light, a burst, and the icon taking off.
  const s1 = prog(t, 0.05, 0.95);
  show(streak, Math.sin(Math.PI * s1));
  style(streak, { left: `${lerp(-1100, 1300, inOut(s1))}px`, top: "860px", transform: "rotate(-18deg)" });
  const s2 = prog(t, 0.3, 1.15);
  show(streak2, 0.7 * Math.sin(Math.PI * s2));
  style(streak2, { left: `${lerp(1300, -1100, inOut(s2))}px`, top: "960px", transform: "rotate(-18deg) scaleX(.7)" });
  const b = prog(t, 0.55, 1.6);
  show(burst, (b <= 0 ? 0 : Math.sin(Math.PI * Math.min(1, b * 1.1)) * 0.9) * (1 - prog(t, 2.2, 2.6)));
  style(burst, { left: "90px", top: "380px", transform: `scale(${lerp(0.2, 1.35, outExpo(b))})` });
  const ic = prog(t, 0.6, 1.3);
  const icOut = prog(t, 2.15, 2.6);
  show(icon, outQuart(ic) * (1 - icOut));
  style(icon, {
    left: "350px", top: `${lerp(700, 640, outQuart(ic)) - 200 * inOut(icOut)}px`,
    transform: `scale(${lerp(0.55, 1, outBack(ic)) * lerp(1, 0.7, icOut)}) rotate(${lerp(-10, 0, outQuart(ic)) + 12 * icOut}deg) translateX(${260 * inOut(icOut)}px)`,
    filter: `blur(${lerp(18, 0, outQuart(ic))}px) drop-shadow(0 30px 60px rgba(255,120,80,${0.5 * outQuart(ic)}))`,
  });
  const w = prog(t, 1.0, 1.6);
  show(word, outQuart(w) * (1 - prog(t, 2.1, 2.45)));
  style(word, { transform: `translateY(${lerp(40, 0, outQuart(w))}px)`, letterSpacing: `${lerp(0.25, -0.02, outQuart(w))}em` });

  // 2. A Desktop fills with screenshot files.
  caption(caps.problem, 2.55, 5.15);
  const scrIn = outQuart(prog(t, 2.5, 3.0));
  const scrOut = prog(t, 7.25, 7.75);
  show(screen, scrIn * (1 - scrOut));
  style(screen, { transform: `scale(${lerp(0.92, 1, scrIn) * lerp(1, 1.25, inOut(scrOut))})` });

  // 3. Snapfly sweeps them onto a line.
  caption(caps.line, 5.1, 7.7);
  deskRopePath.style.strokeDashoffset = ROPE_LEN * (1 - outQuart(prog(t, 5.05, 5.55)));
  files.forEach((f, i) => {
    const pop = prog(t, 3.0 + i * 0.16, 3.0 + i * 0.16 + 0.45);
    const [dx, dy] = deskSpots[i];
    const frac = (i + 0.7) / (FILES + 0.4);
    const hx = 960 * frac - 75;
    const hy = 70 + 4 * 34 * frac * (1 - frac) - 6;
    const start = 5.35 + i * 0.08;
    const fly = inOut(prog(t, start, start + 0.75));
    const x = lerp(dx, hx, fly), y = lerp(dy, hy, fly) - Math.sin(Math.PI * fly) * 90;
    const hang = t - (start + 0.75);
    const rot = lerp(deskTilts[i], hangTilts[i], fly) + (hang > 0 ? swing(hang, 9) : 0);
    show(f, outQuart(pop));
    style(f, {
      left: `${RTL ? 960 - x - 150 : x}px`, top: `${y}px`,
      transform: `scale(${lerp(0.3, 1, outBack(pop)) * lerp(1, 0.82, fly)}) rotate(${rot}deg)`,
    });
    f.querySelector(".name").style.opacity = 1 - fly;
    f.querySelector(".thumb").style.borderRadius = `${lerp(6, 12, fly)}px`;
  });

  // 4. Private details, covered.
  caption(caps.private, 7.7, 10.55);
  const docIn = outQuart(prog(t, 7.65, 8.2));
  const docOut = prog(t, 10.25, 10.65);
  show(doc, docIn * (1 - docOut));
  style(doc, { left: "110px", top: "700px", transform: `translateY(${lerp(60, 0, docIn) - 40 * inOut(docOut)}px) scale(${lerp(0.94, 1, docIn) * lerp(1, 0.92, docOut)})` });
  show(sw, docIn * (1 - docOut));
  style(sw, { left: RTL ? "auto" : "110px", right: RTL ? "110px" : "auto", top: "520px", transform: `translateY(${lerp(30, 0, docIn)}px)` });
  const on = outQuart(prog(t, 8.3, 8.6));
  swTrack.style.background = `rgba(${Math.round(lerp(255, 0, on))}, ${Math.round(lerp(255, 113, on))}, ${Math.round(lerp(255, 227, on))}, ${lerp(0.25, 1, on)})`;
  swKnob.style.transform = `translateX(${(RTL ? -1 : 1) * 38 * on}px)`;
  inks.forEach((ink, i) => {
    const c = outQuart(prog(t, 8.65 + i * 0.17, 8.65 + i * 0.17 + 0.32));
    ink.style.transform = `scaleX(${c})`;
  });
  const lk = prog(t, 9.75, 10.1);
  show(lock, outQuart(lk));
  lock.style.transform = `scale(${lerp(0.3, 1, outBack(lk))})`;

  // 5. One click, and every screenshot lands in the chat.
  caption(caps.send, 10.6, 14.75);
  const sIn = outQuart(prog(t, 10.55, 11.0));
  const sOut = prog(t, 14.45, 14.85);
  show(lineRope, sIn * (1 - sOut));
  sendCards.forEach((c, i) => {
    const frac = sendFrac(i);
    const cx = 1080 * frac;
    const cy = 520 + 4 * 46 * frac * (1 - frac) - 10;
    const arrive = prog(t, 10.55 + i * 0.07, 10.95 + i * 0.07);
    const leave = 12.15 + i * 0.1;
    const gone = t >= leave;
    show(c, outQuart(arrive) * (gone ? 0 : 1));
    style(c, { left: `${X(cx - 88, 176)}px`, top: `${cy - lerp(60, 0, outQuart(arrive))}px`,
               transform: `rotate(${[-4, 3, -2, 4][i] + swing(t - 10.95 - i * 0.07, 6, 0.9, 1.2)}deg)` });
  });
  // In from the right edge, clear of the buttons the apps draw there.
  const tagFrac = (1080 - 230 + 62) / 1080;
  const tagX = X(1080 - 230, 124), tagY = 520 + 4 * 46 * tagFrac * (1 - tagFrac) + 18;
  show(tag, sIn * (1 - sOut)); show(tagPill, sIn * (1 - sOut));
  const press = prog(t, 12.0, 12.25);
  style(tag, { left: `${tagX}px`, top: `${tagY}px`, transform: `scale(${1 - 0.14 * Math.sin(Math.PI * press)})` });
  style(tagPill, { left: `${tagX + 62}px`, top: `${tagY + 150}px`, transform: "translateX(-50%)" });
  const rp = prog(t, 12.05, 12.65);
  show(ripple, (1 - rp) * (rp > 0 ? 1 : 0));
  style(ripple, { left: `${tagX + 62 - 90 * (1 + rp)}px`, top: `${tagY + 62 - 90 * (1 + rp)}px`, width: `${180 * (1 + rp)}px`, height: `${180 * (1 + rp)}px` });
  show(chat, sIn * (1 - sOut));
  style(chat, { transform: `translateY(${lerp(80, 0, sIn)}px)` });
  const askIn = prog(t, 10.95, 11.25);
  show(ask, outQuart(askIn)); ask.style.transform = `scale(${lerp(0.85, 1, outBack(askIn))})`;
  // The flights: from each card on the line to its cell in the album.
  const chatTop = CHAT_TOP + lerp(80, 0, sIn);
  const albumLeft = RTL ? X(CHAT_LEFT, CHAT_WIDTH) + 32 : CHAT_LEFT + CHAT_WIDTH - 32 - 460;
  ghosts.forEach((g, i) => {
    const start = 12.15 + i * 0.1;
    const f = prog(t, start, start + 0.85);
    const frac = sendFrac(i);
    const fromX = X(1080 * frac - 88, 176);
    const fromY = 520 + 4 * 46 * frac * (1 - frac) - 10;
    const toX = albumLeft + (i % 2) * 233, toY = chatTop + ALBUM_TOP + Math.floor(i / 2) * 156;
    const e = inOut(f);
    const x = lerp(fromX, toX, e) + Math.sin(Math.PI * e) * (RTL ? -60 : 60);
    const y = lerp(fromY, toY, e) - Math.sin(Math.PI * e) * 140;
    const sc = lerp(1, 227 / 176, e);
    show(g, f > 0 && f < 1 ? 1 : 0);
    style(g, { left: `${x}px`, top: `${y}px`, transform: `rotate(${Math.sin(Math.PI * e) * (RTL ? 10 : -10)}deg) scale(${sc})` });
    g.querySelector(".glass").style.padding = `${lerp(6, 0, e)}px`;
  });
  cells.forEach((c, i) => show(c, t >= 12.15 + i * 0.1 + 0.85 ? 1 : 0));
  show(album, t >= 12.95 ? 1 : 0.999);
  const ty = prog(t, 13.3, 13.5) * (1 - prog(t, 14.0, 14.05));
  show(typing, ty);
  [...typing.children].forEach((d, k) => { d.style.transform = `translateY(${-6 * Math.max(0, Math.sin(t * 9 - k * 0.9))}px)`; });
  const an = prog(t, 14.0, 14.25);
  show(answer, outQuart(an)); answer.style.transform = `scale(${lerp(0.85, 1, outBack(an))})`;

  // 6. Hold a screenshot: the menu, and a PDF.
  caption(caps.menu, 14.85, 17.45);
  const mIn = outQuart(prog(t, 14.8, 15.2));
  const mOut = prog(t, 17.15, 17.5);
  show(menuRope, mIn * (1 - mOut));
  menuCards.forEach((c, i) => {
    const frac = [0.17, 0.45, 0.78][i];
    const cx = 1080 * frac, cy = 540 + 4 * 40 * frac * (1 - frac) - 10;
    const held = i === 1 ? outQuart(prog(t, 15.55, 15.75)) : 0;
    show(c, mIn * (1 - mOut) * (i === 1 ? 1 : lerp(1, 0.5, outQuart(prog(t, 15.7, 16.0)))));
    style(c, { left: `${X(cx - 125, 0) - (RTL ? 250 : 0)}px`, top: `${cy - lerp(50, 0, mIn)}px`,
               transform: `rotate(${[-3, 2, -2][i] * (1 - held) + swing(t - 15.2, 4, 0.8, 1)}deg) scale(${1 + 0.05 * held})` });
  });
  // The pointer: into place, hold, and later a click.
  const pIn = inOut(prog(t, 14.95, 15.45));
  const pX = lerp(820, 420, pIn), pY = lerp(1500, 760, pIn);
  const p5Out = prog(t, 17.1, 17.4);
  const ptrA = prog(t, 14.95, 15.15) * (1 - p5Out);
  const pt = prog(t, 11.05, 11.9);
  const p5 = inOut(pt);
  const inSend = t > 10.9 && t < 14.6;
  const sendX = lerp(620, tagX + 70, p5), sendY = lerp(1550, tagY + 70, p5);
  const ptrSend = prog(t, 11.0, 11.2) * (1 - prog(t, 12.6, 12.9));
  if (inSend) { show(pointer, ptrSend); style(pointer, { left: `${sendX}px`, top: `${sendY}px`, transform: `scale(${1 - 0.15 * Math.sin(Math.PI * press)})` }); }
  else { show(pointer, ptrA); style(pointer, { left: `${X(pX, 0)}px`, top: `${pY}px`, transform: "scale(1)" }); }
  const hold = prog(t, 15.5, 15.95);
  show(ring, hold > 0 && t < 16.05 ? 1 : 0);
  style(ring, { left: `${X(pX, 0) - 30}px`, top: `${pY - 40}px` });
  ringCircle.style.strokeDashoffset = RING_LEN * (1 - hold);
  const mp = prog(t, 15.95, 16.25);
  show(menu, outQuart(mp) * (1 - mOut));
  style(menu, { left: `${RTL ? X(pX, 0) - 600 + 10 : pX + 10}px`, top: `${pY + 30}px`, transform: `scale(${lerp(0.88, 1, outQuart(mp))})` });
  const pdfIndex = T.menuPdfIndex;
  const step = Math.floor(lerp(0, pdfIndex + 0.999, inOut(prog(t, 16.25, 16.75))));
  const target = items[Math.min(step, items.length - 1)];
  show(hl, mp > 0.5 ? 1 : 0);
  if (target) style(hl, { top: `${target.offsetTop}px` });
  items.forEach((it, i) => { it.style.color = i === Math.min(step, items.length - 1) && mp > 0.5 ? "#fff" : "#1D1D1F"; });
  const flash = prog(t, 16.85, 17.0);
  hl.style.opacity = flash > 0 && flash < 1 ? 0.6 : 1;
  const pd = prog(t, 16.95, 17.35);
  show(pdf, outQuart(pd) * (1 - prog(t, 17.25, 17.5)));
  style(pdf, { left: `${X(90, 230)}px`, top: `${1210 - 60 * outQuart(pd)}px`, transform: `rotate(${lerp(-12, 6, outBack(pd))}deg) scale(${lerp(0.5, 1, outBack(pd))})` });

  // 7. The end card on the wallpaper, above the captions the apps draw at the bottom.
  const ei = prog(t, 17.7, 18.3);
  show(endIcon, outQuart(ei));
  style(endIcon, { left: "390px", top: `${410 - 120 * (1 - outBack(ei))}px`,
    transform: `scale(${lerp(0.6, 1, outBack(ei))}) rotate(${lerp(-14, 0, outQuart(ei))}deg)`,
    filter: `drop-shadow(0 30px 50px rgba(40,0,50,${0.45 * outQuart(ei)}))` });
  const ew = prog(t, 18.0, 18.55);
  show(endWord, outQuart(ew)); style(endWord, { transform: `translateY(${lerp(40, 0, outQuart(ew))}px)` });
  const et = prog(t, 18.3, 18.85);
  show(endTag, outQuart(et)); style(endTag, { transform: `translateY(${lerp(30, 0, outQuart(et))}px)` });
  const fr = prog(t, 18.6, 19.05);
  show(free, outQuart(fr));
  style(free, { left: "540px", top: "1225px", transform: `translateX(-50%) scale(${lerp(0.8, 1, outBack(fr))})` });
  const ur = prog(t, 18.85, 19.3);
  show(url, outQuart(ur));
  // A slow push in on the end card.
  const push = 1 + 0.025 * prog(t, 18, 21);
  [endIcon, endWord, endTag, url].forEach((n) => { n.style.scale = String(push); });
}

window.seek = seek;
window.DURATION = DURATION;
document.fonts.ready.then(() => { seek(0); window.READY = true; });

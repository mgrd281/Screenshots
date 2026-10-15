// The Snapfly website's few moving parts: the line in the first view, which
// copies and sends like the app, and the demos further down. Everything on
// the page reads without it.
(() => {
  "use strict";

  const reduced = matchMedia("(prefers-reduced-motion: reduce)");
  const rtl = document.documentElement.dir === "rtl";
  const wait = (ms) => new Promise((done) => setTimeout(done, ms));

  // MARK: Language

  // The visitor's choice wins over the browser's language from now on.
  document.querySelectorAll("a[data-lang]").forEach((link) => {
    link.addEventListener("click", () => {
      try { localStorage.setItem("snapfly-lang", link.dataset.lang); } catch (e) { /* private window */ }
    });
  });

  const langMenu = document.querySelector(".lang-menu");
  if (langMenu) {
    document.addEventListener("click", (event) => {
      if (langMenu.open && !langMenu.contains(event.target)) langMenu.open = false;
    });
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && langMenu.open) {
        langMenu.open = false;
        langMenu.querySelector("summary").focus();
      }
    });
  }

  // MARK: Menu bar clock

  const clock = document.querySelector(".clock");
  if (clock && window.Intl) {
    const format = new Intl.DateTimeFormat(document.documentElement.lang, {
      weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit",
    });
    const tick = () => { clock.textContent = format.format(new Date()); };
    tick();
    setInterval(tick, 15000);
  }

  // MARK: The line

  const line = document.querySelector("[data-line]");
  if (line) setUpLine(line);

  function setUpLine(line) {
    const list = line.querySelector(".pegs");
    const status = line.querySelector("[data-status]");
    const originals = [...list.children].map((peg) => peg.cloneNode(true));
    const chat = document.querySelector("[data-chat]");
    const thread = chat && chat.querySelector("[data-thread]");
    const reply = chat && chat.querySelector("template[data-reply]");
    const replyAll = chat && chat.querySelector("template[data-reply-all]");
    const tag = line.querySelector("[data-send-all]");
    const chatButton = chat && chat.querySelector("[data-chat-btn]");
    const captionBar = chat && chat.querySelector("[data-caption]");
    const captionField = captionBar && captionBar.querySelector("input");
    const chatMenu = chat && chat.querySelector(".chat-menu");
    const replyCaption = chat && chat.querySelector("template[data-reply-caption]");
    let replied = false;
    let refilling = false;
    let dragged = null;
    let thumbsShown = "";

    const hanging = () => [...list.children].filter((peg) =>
      !peg.classList.contains("leaving") && !peg.classList.contains("sending") &&
      getComputedStyle(peg).display !== "none");

    // Photos spread evenly along the rope, never closer to the edge than
    // their own corner buttons, and close the gap when one goes.
    function layout() {
      const pegs = hanging();
      if (!pegs.length) { updateButton(); return; }
      const width = line.clientWidth;
      const tagRoom = tag ? tag.closest(".line-tag").offsetWidth + 28 : 0;
      const half = pegs[0].offsetWidth / 2 + 18;
      const span = width - tagRoom;
      pegs.forEach((peg, i) => {
        const x = pegs.length === 1 ? span / 2 : half + (i * (span - 2 * half)) / (pegs.length - 1);
        peg.dataset.slot = (x / width).toFixed(4);
        // The photo being dragged stays under the pointer.
        if (peg !== dragged) peg.style.setProperty("--t", peg.dataset.slot);
      });
      updateButton();
    }
    layout();
    addEventListener("resize", layout);

    function announce(text) {
      status.textContent = "";
      requestAnimationFrame(() => { status.textContent = text; });
    }

    let afterDrag = false;
    list.addEventListener("click", (event) => {
      if (afterDrag) { afterDrag = false; return; }
      const peg = event.target.closest(".peg");
      if (!peg || peg.classList.contains("leaving") || peg.classList.contains("sending")) return;
      if (event.target.closest(".corner-send")) send(peg);
      else if (event.target.closest(".corner-x")) discard(peg);
      else if (event.target.closest(".photo-hit")) copy(peg);
    });

    function copy(peg) {
      peg.classList.remove("is-copied");
      void peg.offsetWidth;
      peg.classList.add("is-copied");
      clearTimeout(peg.copiedTimer);
      peg.copiedTimer = setTimeout(() => peg.classList.remove("is-copied"), 1500);
      announce(peg.querySelector(".copied").textContent);
      copyImage(peg.querySelector(".photo-img svg"));
    }

    function discard(peg) {
      peg.classList.add("leaving");
      setTimeout(() => { peg.remove(); layout(); refillIfEmpty(); }, 380);
      layoutSoon();
    }

    function layoutSoon() { requestAnimationFrame(layout); }

    // Gets the chat ready for what lands: the hint goes, and on a small
    // screen, where the chat sits below the line, it comes into view.
    async function readyChat() {
      const hint = thread.querySelector(".note");
      if (hint) hint.remove();
      const box = chat.getBoundingClientRect();
      if (box.top > innerHeight - 160 || box.bottom < 160) {
        chat.scrollIntoView({ behavior: reduced.matches ? "auto" : "smooth", block: "center" });
        await wait(reduced.matches ? 0 : 520);
      }
    }

    const fly = (photo, to, delay = 0) => flyPhoto(photo, photo.getBoundingClientRect(), to, delay);

    function landed(bubble, pegs, answerWith) {
      bubble.style.visibility = "";
      bubble.classList.add("landed");
      pegs.forEach((peg) => peg.remove());
      layout();
      announce(status.dataset.sent);
      trimThread();
      if (answerWith) setTimeout(() => answer(answerWith), 700);
      refillIfEmpty();
    }

    async function send(peg) {
      if (!thread) return discard(peg);
      const bubble = document.createElement("li");
      bubble.className = "msg out image";
      const frame = document.createElement("span");
      frame.className = "photo-img";
      frame.appendChild(peg.querySelector(".photo-img svg").cloneNode(true));
      bubble.appendChild(frame);
      bubble.style.visibility = "hidden";
      await readyChat();
      thread.appendChild(bubble);
      thread.scrollTop = thread.scrollHeight;
      const photo = peg.querySelector(".photo");
      const to = frame.getBoundingClientRect();
      peg.classList.add("sending");
      layout();
      await fly(photo, to);
      const first = !replied;
      replied = true;
      landed(bubble, [peg], first ? reply : null);
    }

    // The tag's send button, and the button over the chat: every photo on
    // the line, at once, into the chat, where they land together, with the
    // message after them when there is one.
    async function sendAll(caption = "") {
      const pegs = hanging();
      if (!pegs.length || !thread) return;
      const bubble = document.createElement("li");
      bubble.className = "msg out album";
      const grid = document.createElement("span");
      grid.className = "album-grid";
      const cells = pegs.map((peg) => {
        const cell = document.createElement("span");
        cell.className = "photo-img";
        cell.appendChild(peg.querySelector(".photo-img svg").cloneNode(true));
        grid.appendChild(cell);
        return cell;
      });
      bubble.appendChild(grid);
      bubble.style.visibility = "hidden";
      await readyChat();
      thread.appendChild(bubble);
      thread.scrollTop = thread.scrollHeight;
      const targets = cells.map((cell) => cell.getBoundingClientRect());
      const photos = pegs.map((peg) => peg.querySelector(".photo"));
      const flights = photos.map((photo, i) => fly(photo, targets[i], i * 90));
      pegs.forEach((peg) => peg.classList.add("sending"));
      await Promise.all(flights);
      replied = true;
      if (chatButton) {
        chatButton.classList.add("sent");
        setTimeout(() => { chatButton.classList.remove("sent"); updateButton(); }, 1100);
      }
      landed(bubble, pegs, caption ? null : replyAll || reply);
      if (caption) {
        const words = document.createElement("li");
        words.className = "msg out caption pop";
        const text = document.createElement("p");
        text.textContent = caption;
        words.appendChild(text);
        thread.appendChild(words);
        thread.scrollTop = thread.scrollHeight;
        trimThread();
        setTimeout(() => answer(replyCaption || replyAll || reply), 700);
      }
    }

    if (tag) tag.addEventListener("click", () => sendAll());

    // MARK: Order, by dragging along the line

    // Dragged sideways, a photo follows the pointer and its slot moves past
    // each neighbour's middle, as on the app's line; let go, it stays there.
    let press = null;
    list.addEventListener("pointerdown", (event) => {
      const hit = event.target.closest(".photo-hit");
      if (!hit || event.button !== 0 || !event.isPrimary) return;
      const peg = hit.closest(".peg");
      if (peg.classList.contains("leaving") || peg.classList.contains("sending")) return;
      press = { peg, hit, x: event.clientX, y: event.clientY, id: event.pointerId };
    });
    addEventListener("pointermove", (event) => {
      if (!press || event.pointerId !== press.id) return;
      const dx = event.clientX - press.x;
      const dy = event.clientY - press.y;
      if (!dragged) {
        if (Math.abs(dy) > 12 && Math.abs(dy) > Math.abs(dx)) { press = null; return; }
        if (Math.abs(dx) < 7 || hanging().length < 2) return;
        dragged = press.peg;
        dragged.classList.add("dragging");
        try { press.hit.setPointerCapture(event.pointerId); } catch (e) { /* already gone */ }
      }
      follow(event.clientX);
    });
    const letGo = (event) => {
      if (!press || event.pointerId !== press.id) return;
      press = null;
      if (!dragged) return;
      dragged.classList.remove("dragging");
      dragged = null;
      layout();
      // The click that ends a drag copies nothing.
      afterDrag = true;
      setTimeout(() => { afterDrag = false; }, 0);
    };
    addEventListener("pointerup", letGo);
    addEventListener("pointercancel", letGo);

    function follow(clientX) {
      const box = line.getBoundingClientRect();
      const x = Math.min(Math.max(clientX - box.left, 0), box.width);
      const t = rtl ? 1 - x / box.width : x / box.width;
      dragged.style.setProperty("--t", t.toFixed(4));
      const pegs = hanging();
      const others = pegs.filter((peg) => peg !== dragged);
      const slot = others.filter((peg) => parseFloat(peg.dataset.slot) < t).length;
      if (!others.length || slot === pegs.indexOf(dragged)) return;
      list.insertBefore(dragged, others[slot] || others[others.length - 1].nextSibling);
      layout();
    }

    // Option and an arrow move the photo in focus, for the keyboard.
    list.addEventListener("keydown", (event) => {
      const hit = event.target.closest(".photo-hit");
      if (!hit || !event.altKey || (event.key !== "ArrowLeft" && event.key !== "ArrowRight")) return;
      event.preventDefault();
      const peg = hit.closest(".peg");
      const pegs = hanging();
      const at = pegs.indexOf(peg);
      const later = (event.key === "ArrowRight") !== rtl;
      const to = at + (later ? 1 : -1);
      if (at < 0 || to < 0 || to >= pegs.length) return;
      list.insertBefore(peg, later ? pegs[to].nextSibling : pegs[to]);
      layout();
      hit.focus();
      announce(later ? line.dataset.later : line.dataset.earlier);
    });

    // MARK: The send button over the chat

    function updateButton() {
      if (!chatButton) return;
      const pegs = hanging();
      // Once sent, it shows its checkmark a moment before it goes.
      if (!pegs.length && chatButton.classList.contains("sent")) return;
      chatButton.hidden = !pegs.length;
      chatButton.inert = !pegs.length;
      if (!pegs.length) { closeCaption(); return; }
      chatButton.querySelector(".cb-count").textContent = pegs.length;
      const newest = pegs.slice(-2);
      const key = newest.map((peg) => peg.dataset.kind).join() + pegs.length;
      if (key !== thumbsShown) {
        thumbsShown = key;
        const thumbs = chatButton.querySelectorAll(".cb-thumb");
        thumbs.forEach((thumb) => thumb.replaceChildren());
        newest.forEach((peg, i) => {
          const svg = peg.querySelector(".photo-img svg").cloneNode(true);
          svg.setAttribute("preserveAspectRatio", "xMidYMid slice");
          thumbs[newest.length === 1 ? 1 : i].appendChild(svg);
        });
        thumbs[0].hidden = newest.length < 2;
      }
      if (captionBar && !captionBar.hidden) countCaption();
    }

    if (chatButton) {
      // A click sends; a press and hold of 0.45 s opens the message bar.
      let hold = null;
      let held = false;
      const stopHold = () => {
        if (hold) clearTimeout(hold.timer);
        hold = null;
        chatButton.classList.remove("holding");
      };
      chatButton.addEventListener("pointerdown", (event) => {
        if (event.button !== 0) return;
        held = false;
        chatButton.classList.add("holding");
        hold = {
          x: event.clientX, y: event.clientY,
          timer: setTimeout(() => { stopHold(); held = true; openCaption(); }, 450),
        };
      });
      chatButton.addEventListener("pointermove", (event) => {
        if (hold && Math.hypot(event.clientX - hold.x, event.clientY - hold.y) > 6) stopHold();
      });
      ["pointerup", "pointerleave", "pointercancel"].forEach((type) => chatButton.addEventListener(type, stopHold));
      chatButton.addEventListener("click", () => {
        if (held) { held = false; return; }
        closeCaption();
        sendAll();
      });
      chatButton.addEventListener("contextmenu", (event) => {
        event.preventDefault();
        stopHold();
        if (held) return;
        openChatMenu(event);
      });
      chatMenu.addEventListener("click", (event) => {
        if (event.target.closest("[data-act='caption']")) openCaption();
      });
      chatMenu.addEventListener("keydown", (event) => {
        if (event.key === "Escape") { event.preventDefault(); closeChatMenu(); chatButton.focus(); }
      });
      captionBar.addEventListener("submit", (event) => {
        event.preventDefault();
        const words = captionField.value.trim();
        closeCaption();
        sendAll(words);
      });
      captionBar.addEventListener("keydown", (event) => {
        if (event.key === "Escape") { event.preventDefault(); closeCaption(); chatButton.focus(); }
      });
      document.addEventListener("pointerdown", (event) => {
        if (!captionBar.hidden && !captionBar.contains(event.target) && !chatButton.contains(event.target)) closeCaption();
        if (!chatMenu.hidden && !chatMenu.contains(event.target)) closeChatMenu();
      });
    }

    function openChatMenu(event) {
      const box = chat.getBoundingClientRect();
      const button = chatButton.getBoundingClientRect();
      const keyboard = !event.clientX && !event.clientY;
      chatMenu.hidden = false;
      const x = keyboard ? button.left + button.width / 2 : event.clientX;
      const y = keyboard ? button.top : event.clientY;
      const left = Math.min(Math.max(x - box.left - (rtl ? chatMenu.offsetWidth : 0), 8), box.width - chatMenu.offsetWidth - 8);
      chatMenu.style.left = left + "px";
      chatMenu.style.top = Math.max(y - box.top - chatMenu.offsetHeight - 4, 50) + "px";
      chatMenu.querySelector(".ctx-item").focus({ preventScroll: true });
    }

    function closeChatMenu() { if (chatMenu) chatMenu.hidden = true; }

    function openCaption() {
      if (!captionBar || !hanging().length) return;
      closeChatMenu();
      captionBar.hidden = false;
      captionField.value = "";
      countCaption();
      captionField.focus({ preventScroll: true });
    }

    function closeCaption() { if (captionBar) captionBar.hidden = true; }

    function countCaption() {
      const chip = captionBar.querySelector(".caption-count");
      chip.textContent = chip.dataset.format.replace("%d", hanging().length);
    }

    async function answer(template) {
      const typing = document.createElement("li");
      typing.className = "msg in typing pop";
      typing.innerHTML = "<p aria-hidden=\"true\"><i></i><i></i><i></i></p>";
      thread.appendChild(typing);
      thread.scrollTop = thread.scrollHeight;
      await wait(reduced.matches ? 200 : 1100);
      const message = template.content.firstElementChild.cloneNode(true);
      message.classList.add("pop");
      typing.replaceWith(message);
      thread.scrollTop = thread.scrollHeight;
    }

    function trimThread() {
      const messages = thread.querySelectorAll(".msg");
      for (let i = 0; i < messages.length - 7; i++) messages[i].remove();
    }

    // An empty line fills again, as if new screenshots had been taken.
    function refillIfEmpty() {
      if (hanging().length || refilling) return;
      refilling = true;
      setTimeout(() => {
        originals.forEach((original, i) => {
          const peg = original.cloneNode(true);
          peg.classList.add("arriving");
          peg.style.setProperty("--d", `${i * 90}ms`);
          list.appendChild(peg);
        });
        layout();
        requestAnimationFrame(() => requestAnimationFrame(() => {
          list.querySelectorAll(".arriving").forEach((peg) => peg.classList.remove("arriving"));
        }));
        refilling = false;
      }, 1300);
    }
  }

  // A photo takes off up and away, as on the icon, then lands where it goes.
  async function flyPhoto(photo, from, to, delay = 0) {
    if (reduced.matches) return;
    const ghost = photo.cloneNode(true);
    ghost.classList.add("ghost");
    ghost.querySelectorAll("button, .badge-lock, .badge-video").forEach((el) => {
      if (el.matches(".photo-hit")) el.replaceWith(el.firstElementChild);
      else el.remove();
    });
    Object.assign(ghost.style, { left: from.left + "px", top: from.top + "px", width: from.width + "px" });
    document.body.appendChild(ghost);
    const dx = to.left - from.left;
    const dy = to.top - from.top;
    const scale = to.width / from.width;
    const lift = Math.min(-70, dy * -0.15);
    const away = (rtl ? -1 : 1) * 40;
    const flight = ghost.animate([
      { transform: "translate(0, 0) rotate(0deg) scale(1)" },
      { transform: `translate(${dx * 0.35 + away}px, ${lift}px) rotate(${rtl ? 9 : -9}deg) scale(${(1 + scale) / 2})`, offset: 0.38 },
      { transform: `translate(${dx}px, ${dy}px) rotate(0deg) scale(${scale})` },
    ], { duration: 820, delay, easing: "cubic-bezier(.45,.05,.25,1)", fill: "backwards" });
    await flight.finished.catch(() => {});
    ghost.remove();
  }

  // A real copy of the picture, so ⌘V after a click pastes it.
  function copyImage(svg, ratio = 1.5) {
    if (!svg || !navigator.clipboard || !window.ClipboardItem) return;
    const width = 1200;
    const height = Math.round(width / ratio);
    const copy = svg.cloneNode(true);
    copy.setAttribute("width", String(width));
    copy.setAttribute("height", String(height));
    const source = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(new XMLSerializer().serializeToString(copy));
    const png = new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => {
        const canvas = document.createElement("canvas");
        canvas.width = width;
        canvas.height = height;
        canvas.getContext("2d").drawImage(image, 0, 0, width, height);
        canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("no image"))), "image/png");
      };
      image.onerror = reject;
      image.src = source;
    });
    try {
      navigator.clipboard.write([new ClipboardItem({ "image/png": png })]).catch(() => {});
    } catch (e) { /* the browser keeps the clipboard to itself */ }
  }

  // MARK: Played once when seen

  function whenSeen(element, run, threshold = 0.45) {
    if (!element) return;
    if (!("IntersectionObserver" in window)) { run(); return; }
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        observer.disconnect();
        run();
      }
    }, { threshold });
    observer.observe(element);
  }

  whenSeen(document.querySelector(".keys"), () => document.querySelector(".keys").classList.add("play"), 0.6);

  // MARK: The Desktop, swept onto the line

  const desk = document.querySelector("[data-desk]");
  if (desk) {
    const tilts = [-4, 3, -2, 4, -3, 2, -1, 3, -2];

    // Each file flies to its place on the rope at the top of the section.
    // Places come from the layout, not from where a file is drawn, so a
    // sweep in the middle of another still lands right.
    const sweep = () => {
      const files = [...desk.querySelectorAll(".file")].filter((f) => getComputedStyle(f).display !== "none");
      const box = desk.querySelector(".desk-files").getBoundingClientRect();
      const rope = desk.querySelector(".desk-rope").getBoundingClientRect();
      const margin = 0.05;
      files.forEach((file, i) => {
        const left = box.left + file.offsetLeft + (rtl ? file.offsetWidth : 0);
        const top = box.top + file.offsetTop;
        const t = margin + ((1 - 2 * margin) * (i + 0.5)) / files.length;
        const x = rope.left + (rtl ? 1 - t : t) * rope.width;
        const y = rope.top + rope.height * (0.14 + 1.44 * t * (1 - t)) - 3;
        file.style.setProperty("--dx", `${x - left}px`);
        file.style.setProperty("--dy", `${y - top}px`);
        file.style.setProperty("--tilt", `${tilts[i % tilts.length]}deg`);
      });
      desk.classList.add("swept");
    };

    whenSeen(desk, () => setTimeout(sweep, reduced.matches ? 0 : 450), 0.55);
    const replay = document.querySelector("[data-replay]");
    if (replay) {
      replay.addEventListener("click", () => {
        desk.classList.remove("swept");
        setTimeout(sweep, reduced.matches ? 150 : 1000);
      });
    }
    addEventListener("resize", () => { if (desk.classList.contains("swept")) sweep(); });
  }

  // MARK: Private details

  const cover = document.querySelector("[data-cover]");
  const invoice = document.querySelector("[data-invoice]");
  if (cover && invoice) {
    const apply = () => {
      const chosen = new Set([...cover.querySelectorAll("[data-kind]:checked")].map((box) => box.value));
      let any = false;
      invoice.querySelectorAll("[data-pd]").forEach((field) => {
        const covered = chosen.has(field.dataset.pd);
        field.classList.toggle("covered", covered);
        any = any || covered;
      });
      invoice.classList.toggle("has-cover", any);
    };
    cover.addEventListener("change", apply);
    apply();
  }

  // MARK: The photo's menu

  const menu = document.querySelector("[data-menu]");
  const about = document.querySelector("[data-menu-desc]");
  if (menu && about) {
    const items = [...menu.querySelectorAll(".ctx-item")];
    const pick = (item) => {
      items.forEach((other) => other.setAttribute("aria-pressed", String(other === item)));
      about.children[0].textContent = item.dataset.title;
      about.children[1].textContent = item.dataset.desc;
    };
    menu.addEventListener("pointerover", (event) => {
      const item = event.target.closest(".ctx-item");
      if (item) pick(item);
    });
    menu.addEventListener("focusin", (event) => {
      const item = event.target.closest(".ctx-item");
      if (item) pick(item);
    });
    menu.addEventListener("click", (event) => {
      const item = event.target.closest(".ctx-item");
      if (item) pick(item);
    });
    menu.addEventListener("keydown", (event) => {
      const at = items.indexOf(document.activeElement);
      if (at < 0) return;
      let next = null;
      if (event.key === "ArrowDown") next = items[(at + 1) % items.length];
      if (event.key === "ArrowUp") next = items[(at - 1 + items.length) % items.length];
      if (event.key === "Home") next = items[0];
      if (event.key === "End") next = items[items.length - 1];
      if (next) { event.preventDefault(); next.focus(); }
    });
  }

  // MARK: Line styles

  const styles = document.querySelector("[data-styles]");
  const screen = document.querySelector("[data-style-stage]");
  const caption = document.querySelector("[data-style-caption]");
  if (styles && screen) {
    styles.addEventListener("change", (event) => {
      screen.dataset.style = event.target.value;
      if (caption) caption.textContent = event.target.dataset.caption;
    });
  }

  // MARK: A Mac screen, to take screenshots on

  const screenBox = document.querySelector("[data-screen]");
  if (screenBox) setUpScreen(screenBox);

  function setUpScreen(screen) {
    const W = 1000;
    const H = 625;
    const svg = screen.querySelector(".scene svg");
    const windows = JSON.parse(screen.dataset.windows);
    const [sortX, sortY, itemX, itemY] = screen.dataset.sort.split(",").map(Number);
    const overlay = screen.querySelector(".cap-overlay");
    const tint = overlay.querySelector(".cap-win");
    const area = overlay.querySelector(".cap-area");
    const size = overlay.querySelector(".cap-size");
    const hint = overlay.querySelector("[data-hint]");
    const button = screen.querySelector(".shot-btn");
    const capsule = screen.querySelector(".capsule");
    const edge = screen.querySelector(".rec-edge");
    const flash = screen.querySelector(".cap-flash");
    const pointer = screen.querySelector(".sim-pointer");
    const list = screen.querySelector("[data-screen-line] .pegs");
    const status = screen.querySelector("[data-screen-status]");
    const template = screen.querySelector("template[data-peg]");
    const statusButton = screen.querySelector(".sf-status");
    const menu = screen.querySelector(".sf-menu");
    const shotMenu = screen.querySelector(".shot-menu");
    const sub = menu.querySelector(".has-sub");
    const subButton = sub.querySelector(":scope > .ctx-item");
    const sortMenu = svg.querySelector(".sort-menu");
    const shirt = svg.querySelector(".sf-icon");
    const stopGlyph = svg.querySelector(".sf-stop");
    const tilts = ["-3deg", "2.2deg", "-1.6deg", "2.8deg", "-2.4deg"];
    const whole = { x: 0, y: 0, w: W, h: H };
    const started = performance.now();
    let choosing = null;
    let pick = null;
    let countdown = null;
    let recording = null;
    let taken = 0;
    let seen = false;
    let playing = false;

    const clock = () => (performance.now() - started) / 1000;
    const time = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
    const announce = (text) => {
      status.textContent = "";
      requestAnimationFrame(() => { status.textContent = text; });
    };

    // Where the pointer is, in the screen's own points.
    const at = (event) => {
      const box = screen.getBoundingClientRect();
      return {
        x: Math.min(Math.max(((event.clientX - box.left) / box.width) * W, 0), W),
        y: Math.min(Math.max(((event.clientY - box.top) / box.height) * H, 0), H),
      };
    };
    const place = (el, r) => Object.assign(el.style, {
      left: (r.x / W) * 100 + "%", top: (r.y / H) * 100 + "%",
      width: (r.w / W) * 100 + "%", height: (r.h / H) * 100 + "%",
    });
    const windowAt = (p) => windows.find((w) => p.x >= w.x && p.x <= w.x + w.w && p.y >= w.y && p.y <= w.y + w.h);

    // MARK: The music, for something to record

    // Draws the player at a moment, on the screen or in a recording of it.
    function music(root, t) {
      const total = 223;
      const now = (72 + t) % total;
      root.querySelectorAll(".m-eq").forEach((bar, k) => {
        const h = 5 + 17 * Math.abs(Math.sin(t * (2.3 + k * 0.61) + k * 1.9));
        bar.setAttribute("y", (parseFloat(bar.dataset.base) - h).toFixed(1));
        bar.setAttribute("height", h.toFixed(1));
      });
      const bar = root.querySelector(".m-prog");
      const full = parseFloat(bar.dataset.w);
      const x0 = parseFloat(bar.dataset.x0);
      const w = (full * now) / total;
      bar.setAttribute("width", w.toFixed(1));
      bar.setAttribute("x", (bar.dataset.rtl === "1" ? x0 + full - w : x0).toFixed(1));
      root.querySelector(".m-t1").textContent = time(now);
      root.querySelector(".m-t2").textContent = "-" + time(total - now);
    }

    const play = () => {
      if (!playing) return;
      music(svg, clock());
      requestAnimationFrame(play);
    };
    if ("IntersectionObserver" in window) {
      new IntersectionObserver((entries) => {
        seen = entries.some((entry) => entry.isIntersecting);
        const go = seen && !reduced.matches;
        if (go && !playing) { playing = true; requestAnimationFrame(play); }
        if (!go) playing = false;
      }, { threshold: 0.15 }).observe(screen);
    }

    // MARK: Choosing what to take

    function choose(kind, n = 0) {
      if (recording) { stop(); return; }
      cancelCountdown();
      closeMenus();
      button.classList.remove("hint");
      choosing = { kind, n };
      hint.textContent = overlay.dataset["hint" + kind[0].toUpperCase() + kind.slice(1)];
      overlay.hidden = false;
      overlay.classList.remove("dragging");
      tint.hidden = true;
      area.hidden = true;
      const box = screen.getBoundingClientRect();
      if (box.top < 0 || box.bottom > innerHeight) {
        screen.scrollIntoView({ behavior: reduced.matches ? "auto" : "smooth", block: "center" });
      }
      overlay.focus({ preventScroll: true });
      did("choose");
    }

    function closeOverlay(refocus) {
      overlay.hidden = true;
      pick = null;
      choosing = null;
      if (refocus) button.focus({ preventScroll: true });
    }

    overlay.addEventListener("pointermove", (event) => {
      const p = at(event);
      if (pick) {
        const r = { x: Math.min(pick.from.x, p.x), y: Math.min(pick.from.y, p.y),
                    w: Math.abs(p.x - pick.from.x), h: Math.abs(p.y - pick.from.y) };
        if (!pick.moved && Math.hypot(r.w, r.h) < 6) return;
        pick.moved = true;
        pick.r = r;
        overlay.classList.add("dragging");
        area.hidden = false;
        place(area, r);
        // In the points of a 1440 × 900 screen.
        size.textContent = `${Math.round(r.w * 1.44)} × ${Math.round(r.h * 1.44)}`;
        return;
      }
      const w = windowAt(p);
      tint.hidden = !w;
      if (w) place(tint, w);
    });
    overlay.addEventListener("pointerdown", (event) => {
      if (event.button !== 0 || event.target.closest(".cap-cancel")) return;
      event.preventDefault();
      try { overlay.setPointerCapture(event.pointerId); } catch (e) { /* gone */ }
      pick = { from: at(event), moved: false };
    });
    overlay.addEventListener("pointerup", () => {
      if (!pick) return;
      const p = pick;
      pick = null;
      take(p.moved && p.r.w >= 10 && p.r.h >= 10 ? p.r : windowAt(p.from) || whole);
    });
    overlay.addEventListener("pointercancel", () => {
      pick = null;
      overlay.classList.remove("dragging");
      area.hidden = true;
    });
    overlay.addEventListener("contextmenu", (event) => { event.preventDefault(); closeOverlay(true); });
    overlay.addEventListener("keydown", (event) => {
      if (event.key === "Escape") { event.preventDefault(); closeOverlay(true); }
      else if (event.key === "Enter") { event.preventDefault(); take(whole); }
    });
    overlay.querySelector(".cap-cancel").addEventListener("click", () => closeOverlay(true));

    function take(region) {
      const { kind, n } = choosing;
      closeOverlay();
      if (kind === "timer") startCountdown(region, n);
      else if (kind === "record") startRecording(region);
      else snap(region);
    }

    // MARK: Taking it

    function crop(region) {
      const image = svg.cloneNode(true);
      image.setAttribute("viewBox", [region.x, region.y, region.w, region.h].map((v) => v.toFixed(1)).join(" "));
      image.setAttribute("preserveAspectRatio", "xMidYMid slice");
      image.setAttribute("aria-hidden", "true");
      return image;
    }

    function snap(region) {
      button.classList.remove("hint");
      place(flash, region);
      flash.classList.remove("go");
      void flash.offsetWidth;
      flash.classList.add("go");
      hang(crop(region), region);
    }

    const hanging = () => [...list.children].filter((peg) => !peg.classList.contains("leaving"));

    // Up to four, spread from the middle of the line.
    function layout() {
      const pegs = hanging();
      pegs.forEach((peg, i) => peg.style.setProperty("--t", (0.5 + (i - (pegs.length - 1) / 2) * 0.2).toFixed(4)));
      placeCoach();
    }

    function letGo(peg) {
      peg.classList.add("leaving");
      setTimeout(() => { peg.remove(); layout(); updateMenu(); }, 380);
      layout();
      updateMenu();
    }

    async function hang(image, region, video) {
      taken += 1;
      const peg = template.content.firstElementChild.cloneNode(true);
      const name = (video ? screen.dataset.recName : screen.dataset.shotName).replace("{n}", taken);
      const ratio = Math.min(Math.max(region.w / region.h, 0.8), 2.4);
      peg.querySelector(".photo-hit").setAttribute("aria-label", `${screen.dataset.copy}: ${name}`);
      peg.querySelector(".corner-x").setAttribute("aria-label", `${screen.dataset.discard}: ${name}`);
      const frame = peg.querySelector(".photo-img");
      frame.style.aspectRatio = String(ratio);
      frame.appendChild(image);
      peg.dataset.ratio = ratio;
      peg.style.setProperty("--tilt", tilts[taken % tilts.length]);
      peg.style.setProperty("--i", taken);
      if (video) playable(peg, image, video);
      else peg.querySelector(".badge-video").remove();
      // A full line lets the oldest go.
      const pegs = hanging();
      if (pegs.length >= 4) letGo(pegs[0]);
      list.appendChild(peg);
      layout();
      updateMenu();
      const box = screen.getBoundingClientRect();
      const from = {
        left: box.left + (region.x / W) * box.width,
        top: box.top + (region.y / H) * box.height,
        width: (region.w / W) * box.width,
      };
      await wait(reduced.matches ? 0 : 120);
      const photo = peg.querySelector(".photo");
      await flyPhoto(photo, from, photo.getBoundingClientRect());
      peg.classList.remove("landing");
      announce(screen.dataset.hung);
      did("hang");
    }

    // A recording plays again while the pointer rests on it.
    function playable(peg, image, video) {
      peg.querySelector(".badge-video span").textContent = time(Math.max(video.seconds, 1));
      const length = Math.max(video.t1 - video.t0, 0.5);
      let frame = 0;
      const start = () => {
        if (frame || reduced.matches) return;
        const from = performance.now();
        const step = () => {
          music(image, video.t0 + (((performance.now() - from) / 1000) % length));
          frame = requestAnimationFrame(step);
        };
        frame = requestAnimationFrame(step);
      };
      const end = () => {
        cancelAnimationFrame(frame);
        frame = 0;
        music(image, video.t0);
      };
      peg.addEventListener("pointerenter", start);
      peg.addEventListener("pointerleave", end);
      peg.addEventListener("focusin", start);
      peg.addEventListener("focusout", end);
      music(image, video.t0);
    }

    list.addEventListener("click", (event) => {
      const peg = event.target.closest(".peg");
      if (!peg || peg.classList.contains("leaving")) return;
      if (event.target.closest(".corner-x")) { letGo(peg); return; }
      if (!event.target.closest(".photo-hit")) return;
      peg.classList.remove("is-copied");
      void peg.offsetWidth;
      peg.classList.add("is-copied");
      clearTimeout(peg.copiedTimer);
      peg.copiedTimer = setTimeout(() => peg.classList.remove("is-copied"), 1500);
      announce(screen.dataset.copied);
      copyImage(peg.querySelector(".photo-img svg"), parseFloat(peg.dataset.ratio));
      did("copy");
    });

    // MARK: The timer

    const setPointer = (x, y) => Object.assign(pointer.style, { left: x * 100 + "%", top: y * 100 + "%" });

    function showCapsule(kind) {
      capsule.dataset.kind = kind;
      capsule.hidden = false;
      const label = kind === "countdown" ? screen.dataset.cancelTimer : screen.dataset.stop;
      capsule.setAttribute("aria-label", label);
      capsule.title = label;
    }

    function setCount(n) {
      const count = capsule.querySelector(".cap-count");
      count.textContent = n;
      count.classList.remove("tick");
      void count.offsetWidth;
      count.classList.add("tick");
    }

    function startCountdown(region, n) {
      let left = n;
      countdown = { timers: [] };
      const later = (ms, run) => countdown.timers.push(setTimeout(run, ms));
      showCapsule("countdown");
      setCount(left);
      // Meanwhile someone opens a menu, which is what the timer is for.
      const open = Math.max(0.3, n - 2.2) * 1000;
      later(open, () => {
        pointer.style.transition = "none";
        setPointer(rtl ? 0.62 : 0.38, 0.82);
        pointer.hidden = false;
        void pointer.offsetWidth;
        pointer.style.transition = "";
        requestAnimationFrame(() => setPointer(sortX, sortY));
      });
      later(open + 950, () => {
        pointer.classList.add("press");
        setTimeout(() => pointer.classList.remove("press"), 140);
        sortMenu.setAttribute("display", "inline");
      });
      later(open + 1250, () => setPointer(itemX, itemY));
      const tick = () => {
        left -= 1;
        if (left > 0) { setCount(left); later(1000, tick); return; }
        countdown = null;
        capsule.hidden = true;
        snap(region);
        setTimeout(closeSortMenu, 1500);
      };
      later(1000, tick);
    }

    function closeSortMenu() {
      if (countdown) return;
      sortMenu.setAttribute("display", "none");
      pointer.hidden = true;
    }

    function cancelCountdown() {
      if (!countdown) return;
      countdown.timers.forEach(clearTimeout);
      countdown = null;
      capsule.hidden = true;
      closeSortMenu();
    }

    // MARK: Recording

    function startRecording(region) {
      recording = { region, t0: clock(), from: performance.now() };
      place(edge, region);
      edge.hidden = false;
      showCapsule("recording");
      capsule.querySelector(".cap-time").textContent = "0:00";
      button.classList.add("recording");
      button.setAttribute("aria-label", screen.dataset.stop);
      button.title = screen.dataset.stop;
      shirt.setAttribute("display", "none");
      stopGlyph.setAttribute("display", "inline");
      updateMenu();
      recording.timer = setInterval(() => {
        const s = (performance.now() - recording.from) / 1000;
        capsule.querySelector(".cap-time").textContent = time(s);
        if (s >= 60) stop();
      }, 250);
    }

    function stop() {
      const r = recording;
      if (!r) return;
      recording = null;
      clearInterval(r.timer);
      edge.hidden = true;
      capsule.hidden = true;
      button.classList.remove("recording");
      button.setAttribute("aria-label", screen.dataset.take);
      button.title = screen.dataset.take;
      shirt.setAttribute("display", "inline");
      stopGlyph.setAttribute("display", "none");
      updateMenu();
      hang(crop(r.region), r.region, { t0: r.t0, t1: clock(), seconds: (performance.now() - r.from) / 1000 });
    }

    capsule.addEventListener("click", () => {
      if (countdown) cancelCountdown();
      else if (recording) stop();
    });

    // MARK: The button and the menus

    button.addEventListener("click", () => (recording ? stop() : choose("shot")));
    button.addEventListener("contextmenu", (event) => {
      event.preventDefault();
      if (!recording) openMenu(shotMenu, button, event);
    });
    statusButton.addEventListener("click", () => (menu.hidden ? openMenu(menu, statusButton) : closeMenus()));

    function openMenu(which, anchor, event) {
      closeMenus();
      which.hidden = false;
      const box = screen.getBoundingClientRect();
      const a = anchor.getBoundingClientRect();
      const w = which.offsetWidth;
      let left;
      let top;
      if (which === menu) {
        // Under the menu bar, from the status item's leading edge.
        left = rtl ? a.right - box.left - w : a.left - box.left;
        top = a.bottom - box.top;
      } else {
        // Beside the button, toward the middle of the screen.
        const pointed = event && (event.clientX || event.clientY);
        const x = pointed ? event.clientX - box.left : rtl ? a.right - box.left : a.left - box.left;
        left = rtl ? x : x - w;
        top = pointed ? event.clientY - box.top : a.top - box.top;
      }
      // Kept on the page where the screen is narrow.
      const page = document.documentElement.clientWidth;
      left = Math.min(Math.max(left, 8 - box.left), page - box.left - w - 8);
      Object.assign(which.style, { left: left + "px", top: top + "px" });
      if (which === menu) statusButton.setAttribute("aria-expanded", "true");
      button.classList.remove("hint");
      if (which === menu) did("menu");
      const first = which.querySelector(".ctx-item:not(:disabled)");
      if (first) first.focus({ preventScroll: true });
    }

    function closeMenus() {
      menu.hidden = true;
      shotMenu.hidden = true;
      closeSub();
      statusButton.setAttribute("aria-expanded", "false");
    }

    // Beside its item on the trailing side, else the leading side, else
    // under it where the page is too narrow for either.
    function openSub(focus) {
      const list = sub.querySelector(".sub");
      const page = document.documentElement.clientWidth;
      const fits = () => {
        const box = list.getBoundingClientRect();
        return box.left >= 4 && box.right <= page - 4;
      };
      sub.classList.remove("flip", "below");
      sub.classList.add("open");
      subButton.setAttribute("aria-expanded", "true");
      if (!fits()) {
        sub.classList.add("flip");
        if (!fits()) sub.classList.replace("flip", "below");
      }
      if (focus) list.querySelector(".ctx-item").focus();
    }

    function closeSub() {
      sub.classList.remove("open", "flip", "below");
      subButton.setAttribute("aria-expanded", "false");
    }

    sub.addEventListener("pointerenter", () => openSub(false));
    sub.addEventListener("pointerleave", (event) => { if (event.pointerType === "mouse") closeSub(); });

    function updateMenu() {
      const record = menu.querySelector("[data-act='record']");
      record.querySelector("span").textContent = recording ? record.dataset.stop : record.dataset.record;
      menu.querySelector("[data-act='clear']").disabled = !hanging().length;
    }

    [menu, shotMenu].forEach((which) => {
      which.addEventListener("click", (event) => {
        const item = event.target.closest(".ctx-item");
        if (!item || item.disabled) return;
        const act = item.dataset.act;
        if (act === "sub") { openSub(true); return; }
        closeMenus();
        // Once the menu has gone, so it is not in the picture.
        if (act === "shot") setTimeout(() => choose("shot"), 150);
        else if (act === "timer") setTimeout(() => choose("timer", Number(item.dataset.n)), 150);
        else if (act === "record") (recording ? stop() : setTimeout(() => choose("record"), 150));
        else if (act === "whole") setTimeout(() => snap(whole), 150);
        else if (act === "button") {
          button.hidden = !button.hidden;
          item.setAttribute("aria-checked", String(!button.hidden));
          statusButton.focus({ preventScroll: true });
        } else if (act === "clear") hanging().forEach(letGo);
      });
      which.addEventListener("keydown", (event) => {
        const current = event.target.closest(".ctx-menu");
        const items = [...current.querySelectorAll(":scope > li > .ctx-item:not(:disabled)")];
        const i = items.indexOf(document.activeElement);
        const inward = rtl ? "ArrowLeft" : "ArrowRight";
        const outward = rtl ? "ArrowRight" : "ArrowLeft";
        if (event.key === "ArrowDown" || event.key === "ArrowUp") {
          event.preventDefault();
          const step = event.key === "ArrowDown" ? 1 : -1;
          items[(i + step + items.length) % items.length].focus();
        } else if (event.key === inward && document.activeElement === subButton) {
          event.preventDefault();
          openSub(true);
        } else if ((event.key === outward || event.key === "Escape") && current.classList.contains("sub")) {
          event.preventDefault();
          closeSub();
          subButton.focus();
        } else if (event.key === "Escape") {
          event.preventDefault();
          closeMenus();
          (which === menu ? statusButton : button).focus({ preventScroll: true });
        } else if (event.key === "Tab") {
          closeMenus();
        }
      });
    });

    document.addEventListener("pointerdown", (event) => {
      if (menu.hidden && shotMenu.hidden) return;
      if (menu.contains(event.target) || shotMenu.contains(event.target) || statusButton.contains(event.target)) return;
      closeMenus();
    });

    // ⌃⌥S and ⌃⌥R, while the screen is in view.
    document.addEventListener("keydown", (event) => {
      if (!seen || !event.ctrlKey || !event.altKey || event.metaKey) return;
      if (event.target.closest && event.target.closest("input, textarea, [contenteditable]")) return;
      if (event.code === "KeyS" && !recording) { event.preventDefault(); choose("shot"); }
      else if (event.code === "KeyR") { event.preventDefault(); if (recording) stop(); else choose("record"); }
    });

    addEventListener("resize", closeMenus);

    // MARK: The guide for a first visit

    // One step at a time: a card beside the thing to try, a ring round it,
    // and Show me, which does it with the pointer. Doing it moves on.
    const stage = screen.closest("[data-stage]");
    const coach = stage.querySelector("[data-coach]");
    const ring = stage.querySelector(".coach-ring");
    const words = JSON.parse(stage.querySelector("[data-coach-steps]").textContent);
    const showButton = coach.querySelector("[data-coach-show]");
    const skipButton = coach.querySelector("[data-coach-skip]");
    const getLink = coach.querySelector(".coach-get");
    const flights = windows.find((w) => w.name === "flights");
    const newest = () => hanging().pop();
    const guide = [
      { target: () => button, side: "start", round: true, until: "choose", show: () => press(button, () => choose("shot")) },
      { target: () => flights, side: "end", until: "hang", show: drag },
      { target: () => newest() && newest().querySelector(".photo"), side: "below", until: "copy",
        show: () => { const hit = newest().querySelector(".photo-hit"); press(hit, () => hit.click()); } },
      { target: () => statusButton, side: "below", round: true, until: "menu", show: () => press(statusButton, () => openMenu(menu, statusButton)) },
      { target: () => null, side: "none" },
    ];
    let step = -1;
    let guided = false;
    let showing = false;

    function did(event) {
      if (step < 0 || guide[step].until !== event) return;
      setTimeout(() => go(step + 1), event === "choose" ? 250 : 600);
    }

    function go(n) {
      step = n;
      showing = false;
      const g = guide[n];
      coach.querySelector("[data-coach-n]").textContent = coach.dataset.of.replace("{n}", n + 1).replace("{total}", guide.length);
      coach.querySelector("[data-coach-title]").textContent = words[n].title;
      coach.querySelector("[data-coach-text]").textContent = words[n].text;
      const last = n === guide.length - 1;
      showButton.hidden = last;
      showButton.disabled = false;
      getLink.hidden = !last;
      skipButton.textContent = last ? coach.dataset.done : coach.dataset.skip;
      coach.hidden = false;
      coach.classList.remove("fresh");
      void coach.offsetWidth;
      coach.classList.add("fresh");
      placeCoach();
    }

    function stopGuide() {
      step = -1;
      coach.hidden = true;
      ring.hidden = true;
    }

    // The card goes on the side asked for when it fits on the page, else
    // under the thing; the ring follows the thing.
    function placeCoach() {
      if (step < 0) return;
      const g = guide[step];
      const base = stage.getBoundingClientRect();
      const box = screen.getBoundingClientRect();
      let target = g.target();
      if (target && !(target instanceof Element)) {
        target = {
          left: box.left + (target.x / W) * box.width, top: box.top + (target.y / H) * box.height,
          width: (target.w / W) * box.width, height: (target.h / H) * box.height,
        };
        target.right = target.left + target.width;
        target.bottom = target.top + target.height;
      } else if (target) {
        target = target.getBoundingClientRect();
      }
      const page = document.documentElement.clientWidth;
      const w = coach.offsetWidth;
      const h = coach.offsetHeight;
      const gap = 16;
      let side = g.side === "start" ? (rtl ? "right" : "left") : g.side === "end" ? (rtl ? "left" : "right") : g.side;
      let x;
      let y;
      const at = (s) => {
        if (s === "left") { x = target.left - gap - w; y = target.top + Math.min(target.height / 2, 60) - h / 2; }
        else if (s === "right") { x = target.right + gap; y = target.top + Math.min(target.height / 2, 60) - h / 2; }
        else if (s === "below") { x = target.left + target.width / 2 - w / 2; y = target.bottom + gap; }
        return x >= 8 && x + w <= page - 8;
      };
      if (!target) {
        side = "none";
        x = box.left + box.width / 2 - w / 2;
        y = box.top + box.height * 0.42 - h / 2;
      } else if (!at(side)) {
        side = "below";
        at(side);
      }
      x = Math.min(Math.max(x, 8), page - w - 8);
      coach.dataset.side = side;
      coach.style.left = x - base.left + "px";
      coach.style.top = y - base.top + "px";
      if (target) {
        coach.style.setProperty("--ax", Math.min(Math.max(target.left + target.width / 2 - x, 20), w - 20) + "px");
        coach.style.setProperty("--ay", Math.min(Math.max(target.top + Math.min(target.height / 2, 60) - y, 20), h - 20) + "px");
        const pad = g.round ? 5 : 6;
        Object.assign(ring.style, {
          left: target.left - base.left - pad + "px", top: target.top - base.top - pad + "px",
          width: target.width + pad * 2 + "px", height: target.height + pad * 2 + "px",
        });
        ring.classList.toggle("round", !!g.round);
      }
      ring.hidden = !target;
    }

    // The pointer goes to a thing, presses it, and it happens.
    const pointAt = (x, y) => {
      if (pointer.hidden) {
        pointer.style.transition = "none";
        setPointer(rtl ? 0.62 : 0.38, 0.62);
        pointer.hidden = false;
        void pointer.offsetWidth;
        pointer.style.transition = "";
      }
      requestAnimationFrame(() => setPointer(x, y));
    };

    async function press(el, then) {
      const r = el.getBoundingClientRect();
      const box = screen.getBoundingClientRect();
      pointAt((r.left + r.width / 2 - box.left) / box.width, (r.top + r.height / 2 - box.top) / box.height);
      await wait(reduced.matches ? 50 : 1000);
      pointer.classList.add("press");
      await wait(140);
      pointer.classList.remove("press");
      then();
      setTimeout(() => { if (!countdown) pointer.hidden = true; }, 700);
    }

    // Drags over the flight list, as a person would.
    async function drag() {
      if (overlay.hidden) {
        choose("shot");
        await wait(300);
      }
      const from = { x: rtl ? flights.x + flights.w - 24 : flights.x + 24, y: flights.y + 118 };
      const to = { x: rtl ? flights.x + 24 : flights.x + flights.w - 24, y: flights.y + flights.h - 10 };
      pointAt(from.x / W, from.y / H);
      await wait(reduced.matches ? 50 : 1000);
      pointer.style.transition = "none";
      overlay.classList.add("dragging");
      area.hidden = false;
      const length = reduced.matches ? 1 : 1000;
      const began = performance.now();
      const region = await new Promise((done) => {
        const frame = (now) => {
          const k = Math.min((now - began) / length, 1);
          const e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
          const p = { x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e };
          const r = { x: Math.min(from.x, p.x), y: Math.min(from.y, p.y), w: Math.abs(p.x - from.x), h: Math.abs(p.y - from.y) };
          place(area, r);
          size.textContent = `${Math.round(r.w * 1.44)} × ${Math.round(r.h * 1.44)}`;
          setPointer(p.x / W, p.y / H);
          if (k < 1) requestAnimationFrame(frame);
          else done(r);
        };
        requestAnimationFrame(frame);
      });
      pointer.style.transition = "";
      await wait(200);
      if (!overlay.hidden) take(region);
      setTimeout(() => { pointer.hidden = true; }, 400);
    }

    showButton.addEventListener("click", () => {
      if (step < 0 || showing || !guide[step].show) return;
      showing = true;
      showButton.disabled = true;
      guide[step].show();
    });
    skipButton.addEventListener("click", stopGuide);
    addEventListener("resize", placeCoach);

    // It starts by itself the first time the screen is in view, before
    // anything was taken, and the button under the screen starts it again.
    if ("IntersectionObserver" in window) {
      const first = new IntersectionObserver((entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return;
        first.disconnect();
        setTimeout(() => { if (!guided && !taken && overlay.hidden) { guided = true; go(0); } }, 700);
      }, { threshold: 0.6 });
      first.observe(screen);
    }
    const again = document.querySelector("[data-tour-again]");
    if (again) {
      again.addEventListener("click", () => {
        guided = true;
        cancelCountdown();
        closeOverlay();
        screen.scrollIntoView({ behavior: reduced.matches ? "auto" : "smooth", block: "center" });
        setTimeout(() => go(0), reduced.matches ? 0 : 450);
      });
    }
  }

  // MARK: Hide Part, said in a sentence

  const hideWindow = document.querySelector("[data-hide]");
  if (hideWindow) setUpHide(hideWindow);

  function setUpHide(win) {
    const shot = win.querySelector(".photo-shot");
    const doc = win.querySelector("[data-doc]");
    const layer = win.querySelector("[data-boxes]");
    const eye = win.querySelector("template[data-eye]").innerHTML;
    const form = win.querySelector("[data-saying]");
    const field = form.querySelector(".say-field");
    const hideButton = form.querySelector("[data-hide-btn]");
    const spinner = form.querySelector(".spinner");
    const note = form.querySelector("[data-note-text]");
    const examples = [...form.querySelectorAll("[data-example]")];
    const removeAll = win.querySelector("[data-remove-all]");
    const pieces = [...doc.querySelectorAll(".pc")];
    let hidden = [];
    let drawing = null;
    let working = false;

    // What a sentence can name, in English, German and Arabic. On the Mac,
    // Apple Intelligence reads the sentence; here a few words stand in.
    const WORDS = {
      name: ["name", "person", "people", "اسم", "أسماء", "اسماء"],
      address: ["address", "adress", "anschrift", "straße", "strasse", "street", "city", "عنوان", "عناوين"],
      email: ["mail", "بريد", "إيميل", "ايميل"],
      phone: ["phone", "telefon", "handy", "mobil", "هاتف", "هواتف", "جوال", "تلفون"],
      amount: ["amount", "total", "sum", "price", "money", "betrag", "summe", "preis", "geld", "مبلغ", "سعر", "المال"],
      date: ["date", "time", "datum", "zeit", "تاريخ", "وقت"],
      bank: ["iban", "bank", "account", "konto", "karte", "card", "حساب", "بنك", "ايبان", "آيبان", "بطاق"],
      ref: ["reference", "purpose", "rent", "zweck", "referenz", "betreff", "miete", "مرجع", "بيان", "إيجار", "ايجار"],
    };
    const ALL = /\b(everything|all|anything|alles|alle)\b|كل شيء|كل شي|الكل/;
    const BUT = /\b(but|except|besides|apart from|other than|außer|ausser|bis auf)\b|ما عدا|ماعدا|باستثناء|عدا|إلا/;
    const kindsIn = (text) => Object.keys(WORDS).filter((kind) => WORDS[kind].some((word) => text.includes(word)));

    // What kinds of detail to hide, and any other words to hide where they
    // appear: "Lena, IBAN" is a name typed out and the bank accounts.
    function understand(request) {
      const text = request.toLowerCase();
      const split = text.search(BUT);
      if (split >= 0) {
        const before = text.slice(0, split);
        const keep = kindsIn(text.slice(split));
        const from = ALL.test(before) || !before.trim() ? Object.keys(WORDS) : kindsIn(before);
        return { kinds: from.filter((kind) => !keep.includes(kind)), words: [] };
      }
      if (ALL.test(text)) return { kinds: Object.keys(WORDS), words: [] };
      const kinds = [];
      const words = [];
      text.split(/[,،;]+/).forEach((part) => {
        const named = kindsIn(part);
        if (named.length) kinds.push(...named);
        else words.push(...part.split(/\s+/).filter((word) => word.length >= 2));
      });
      return { kinds, words };
    }

    // Words are hidden where they appear, as the app does without Apple
    // Intelligence.
    function findWords(words) {
      const found = [];
      const walker = document.createTreeWalker(doc, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const value = node.nodeValue.toLowerCase();
        words.forEach((word) => {
          for (let i = value.indexOf(word); i >= 0; i = value.indexOf(word, i + word.length)) {
            found.push({ node, start: i, end: i + word.length });
          }
        });
      }
      return found;
    }

    const same = (a, b) => (a.piece && a.piece === b.piece) ||
      (a.range && b.range && a.range.node === b.range.node && a.range.start === b.range.start);

    async function hideAsSaid() {
      const request = field.value.trim();
      if (!request || working) return;
      working = true;
      spinner.hidden = false;
      hideButton.disabled = true;
      examples.forEach((example) => { example.disabled = true; });
      await wait(reduced.matches ? 150 : 650);
      const { kinds, words } = understand(request);
      let added = pieces.filter((piece) => kinds.includes(piece.dataset.k)).map((piece) => ({ piece }))
        .concat(findWords(words).map((range) => ({ range })));
      added = added.filter((a) => !hidden.some((h) => same(h, a)));
      hidden = hidden.concat(added);
      working = false;
      spinner.hidden = true;
      hideButton.disabled = !field.value.trim();
      examples.forEach((example) => { example.disabled = false; });
      render(added);
      const parts = hidden.filter((h) => !h.rect).length;
      note.textContent = parts ? win.dataset.note.replace("%d", parts) : win.dataset.nothing;
    }

    function rectsOf(h, base) {
      if (h.rect) {
        return [{ x: h.rect.x * base.width, y: h.rect.y * base.height, w: h.rect.w * base.width, h: h.rect.h * base.height }];
      }
      let rects;
      if (h.piece) {
        rects = [...h.piece.getClientRects()];
      } else {
        const range = document.createRange();
        range.setStart(h.range.node, h.range.start);
        range.setEnd(h.range.node, h.range.end);
        rects = [...range.getClientRects()];
      }
      return rects.filter((r) => r.width > 0)
        .map((r) => ({ x: r.left - base.left - 2, y: r.top - base.top - 1, w: r.width + 4, h: r.height + 2 }));
    }

    function render(fresh = []) {
      layer.replaceChildren();
      const base = shot.getBoundingClientRect();
      let delay = 0;
      hidden.forEach((h, index) => {
        rectsOf(h, base).forEach((r) => {
          const box = document.createElement("span");
          box.className = "cover-box";
          box.innerHTML = eye;
          box.dataset.index = index;
          Object.assign(box.style, { left: r.x + "px", top: r.y + "px", width: r.w + "px", height: r.h + "px" });
          if (fresh.includes(h)) {
            box.classList.add("new");
            box.style.setProperty("--d", `${delay++ * 45}ms`);
          }
          layer.appendChild(box);
        });
      });
      removeAll.disabled = !hidden.length;
      shot.classList.remove("saved");
    }

    // A click on a box shows what is under it again.
    layer.addEventListener("click", (event) => {
      const box = event.target.closest(".cover-box");
      if (!box) return;
      hidden.splice(Number(box.dataset.index), 1);
      render();
    });

    // A box dragged over anything hides it too.
    shot.addEventListener("pointerdown", (event) => {
      if (event.button !== 0 || event.target.closest(".cover-box")) return;
      event.preventDefault();
      try { shot.setPointerCapture(event.pointerId); } catch (e) { /* gone */ }
      const base = shot.getBoundingClientRect();
      drawing = { x: event.clientX - base.left, y: event.clientY - base.top };
    });
    shot.addEventListener("pointermove", (event) => {
      if (!drawing) return;
      const base = shot.getBoundingClientRect();
      const x = Math.min(Math.max(event.clientX - base.left, 0), base.width);
      const y = Math.min(Math.max(event.clientY - base.top, 0), base.height);
      const r = { x: Math.min(x, drawing.x), y: Math.min(y, drawing.y), w: Math.abs(x - drawing.x), h: Math.abs(y - drawing.y) };
      if (!drawing.box) {
        if (r.w < 4 && r.h < 4) return;
        drawing.box = document.createElement("span");
        drawing.box.className = "drawing-box";
        layer.appendChild(drawing.box);
      }
      drawing.r = r;
      Object.assign(drawing.box.style, { left: r.x + "px", top: r.y + "px", width: r.w + "px", height: r.h + "px" });
    });
    const endDrawing = () => {
      if (!drawing) return;
      const d = drawing;
      drawing = null;
      if (d.box) d.box.remove();
      if (!d.r || d.r.w < 6 || d.r.h < 6) return;
      const base = shot.getBoundingClientRect();
      const box = { rect: { x: d.r.x / base.width, y: d.r.y / base.height, w: d.r.w / base.width, h: d.r.h / base.height } };
      hidden.push(box);
      render([box]);
    };
    shot.addEventListener("pointerup", endDrawing);
    shot.addEventListener("pointercancel", () => { if (drawing && drawing.box) drawing.box.remove(); drawing = null; });

    field.addEventListener("input", () => { hideButton.disabled = working || !field.value.trim(); });
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      hideAsSaid();
    });
    // Return hides what the field says; empty, Return is Done, as
    // everywhere else. (A form does not submit while Hide is dimmed.)
    field.addEventListener("keydown", (event) => {
      if (event.key !== "Enter" || event.isComposing) return;
      event.preventDefault();
      if (field.value.trim()) hideAsSaid();
      else done();
    });
    examples.forEach((example) => example.addEventListener("click", () => {
      field.value = example.textContent;
      hideAsSaid();
    }));
    removeAll.addEventListener("click", () => { hidden = []; render(); });
    win.querySelector("[data-cancel]").addEventListener("click", () => {
      hidden = [];
      field.value = "";
      note.textContent = "";
      hideButton.disabled = true;
      render();
    });
    const done = () => { if (hidden.length) shot.classList.add("saved"); };
    win.querySelector("[data-done]").addEventListener("click", done);
    addEventListener("resize", () => render());
  }
})();

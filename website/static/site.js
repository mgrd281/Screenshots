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
  async function flyPhoto(photo, from, to, delay = 0, host = document.body) {
    if (reduced.matches) return;
    const ghost = photo.cloneNode(true);
    ghost.classList.add("ghost");
    ghost.querySelectorAll("button, .badge-lock, .badge-video, .dbadge").forEach((el) => {
      if (el.matches(".photo-hit, .dcard-hit")) el.replaceWith(el.firstElementChild);
      else el.remove();
    });
    Object.assign(ghost.style, { left: from.left + "px", top: from.top + "px", width: from.width + "px" });
    host.appendChild(ghost);
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

  // MARK: Brand theme

  // Three looks for the same Mac: Original Sunset, Emerald Petrol and
  // Signature Orange. The choice stays on this device and is set before the
  // page paints, by the first script in <head>; light or dark is still the
  // system's.
  const brandSwitch = document.querySelector(".brand-switch");
  if (brandSwitch) {
    const root = document.documentElement;
    const chips = [...brandSwitch.querySelectorAll("[data-brand-pick]")];
    const bars = { sunset: ["#F5F5F7", "#161618"], emerald: ["#F5F8F5", "#081819"], orange: ["#FAFAF8", "#121211"] };
    const known = (brand) => (brand in bars ? brand : "sunset");
    const current = () => known(root.dataset.brand);
    const show = (brand) => {
      chips.forEach((chip) => {
        const on = chip.dataset.brandPick === brand;
        chip.setAttribute("aria-checked", String(on));
        chip.tabIndex = on ? 0 : -1;
      });
      document.querySelectorAll('meta[name="theme-color"]').forEach((meta) => {
        meta.setAttribute("content", bars[brand][/dark/.test(meta.media) ? 1 : 0]);
      });
    };
    const apply = (brand) => {
      if (brand === "sunset") delete root.dataset.brand;
      else root.dataset.brand = brand;
      show(brand);
    };
    const choose = (brand) => {
      if (brand === current()) return;
      try { localStorage.setItem("snapfly-brand", brand); } catch (e) { /* kept for this visit only */ }
      if (document.startViewTransition && !reduced.matches) document.startViewTransition(() => apply(brand));
      else apply(brand);
    };
    show(current());
    chips.forEach((chip) => chip.addEventListener("click", () => choose(chip.dataset.brandPick)));
    // A radio group: the arrows move to the other theme and choose it.
    brandSwitch.addEventListener("keydown", (event) => {
      const steps = { ArrowUp: -1, ArrowDown: 1, ArrowLeft: rtl ? 1 : -1, ArrowRight: rtl ? -1 : 1 };
      const step = steps[event.key];
      if (!step) return;
      event.preventDefault();
      const at = chips.findIndex((chip) => chip.dataset.brandPick === current());
      const next = chips[(at + step + chips.length) % chips.length];
      choose(next.dataset.brandPick);
      next.focus();
    });
    // Another tab that changes the theme changes this one too.
    addEventListener("storage", (event) => {
      if (event.key === "snapfly-brand") apply(known(event.newValue));
    });
  }

  // MARK: Arrivals

  // The first view's arrival plays once; photos hung on the hero's line
  // later just hang there.
  const intro = document.querySelector(".hero.intro");
  if (intro) setTimeout(() => intro.classList.remove("intro"), 2600);

  // Below the first view, each heading, line of words, window and step
  // arrives once as it comes into view. What is in view when the page
  // opens stays as it is, and Reduce Motion leaves everything in place.
  const arrivals = [
    [".section h2, .close h2", "arrive-words"],
    [".section .copy > p, .design .wrap > p, .close .hero-actions, .close .hero-note", "arrive-text"],
    [".section .window, .desk-frame, .keys, .close-icon", "arrive-window"],
    [".steps > li", "arrive-card"],
  ];
  if (!reduced.matches && "IntersectionObserver" in window) {
    const kinds = arrivals.map(([, kind]) => kind);
    const arrive = new IntersectionObserver((entries) => {
      entries.filter((entry) => entry.isIntersecting).forEach((entry, n) => {
        const thing = entry.target;
        arrive.unobserve(thing);
        thing.style.setProperty("--ad", `${Math.min(n, 4) * 90}ms`);
        thing.classList.remove("pre");
        // Afterwards it keeps its own transitions.
        setTimeout(() => {
          thing.classList.remove("arrive", ...kinds);
          thing.style.removeProperty("--ad");
        }, 1200 + Math.min(n, 4) * 90);
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    arrivals.forEach(([selector, kind]) => document.querySelectorAll(selector).forEach((thing) => {
      const box = thing.getBoundingClientRect();
      if (!box.height || box.top < innerHeight) return;
      thing.classList.add("arrive", kind, "pre");
      arrive.observe(thing);
    }));
  }

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

  // MARK: A Mac desktop to try Snapfly on

  const deskStage = document.querySelector("[data-try-desk]");
  if (deskStage) setUpDesk(deskStage);

  function setUpDesk(stage) {
    const { layouts, words } = JSON.parse(stage.querySelector("[data-desk-data]").textContent);
    const desk = stage.querySelector(".dscreen");
    const fit = stage.querySelector(".desk-fit");
    const scenes = {};
    desk.querySelectorAll(".desk-svg").forEach((svg) => { scenes[svg.dataset.layout] = svg; });
    const barApp = desk.querySelector(".bar-app");
    const statusButton = desk.querySelector(".bar-snapfly");
    const list = desk.querySelector(".dline-pegs");
    const template = stage.querySelector("template[data-card]");
    const controls = { browser: desk.querySelector('.wctl[data-for="browser"]'), chat: desk.querySelector('.wctl[data-for="chat"]') };
    const sortButton = controls.browser.querySelector(".sort-btn");
    const sortMenu = desk.querySelector(".sort-menu");
    const sendButton = controls.chat.querySelector(".dsend");
    const button = desk.querySelector(".dshot");
    const pointer = desk.querySelector(".dpointer");
    const edge = desk.querySelector(".rec-edge");
    const flash = desk.querySelector(".cap-flash");
    const overlay = desk.querySelector(".cap-overlay");
    const tint = overlay.querySelector(".cap-win");
    const area = overlay.querySelector(".cap-area");
    const size = overlay.querySelector(".cap-size");
    const hint = overlay.querySelector("[data-hint]");
    const ring = desk.querySelector(".dring");
    const toasts = desk.querySelector(".dtoasts");
    const capsule = desk.querySelector(".capsule");
    const menu = desk.querySelector(".sf-menu");
    const shotMenu = desk.querySelector(".shot-menu");
    const sub = menu.querySelector(".has-sub");
    const subButton = sub.querySelector(":scope > .dmenu-item");
    const trashPop = desk.querySelector(".trash-pop");
    const trashList = trashPop.querySelector(".trash-list");
    const trashClear = trashPop.querySelector(".trash-clear");
    const dock = stage.querySelector(".dock");
    const dockItems = [...dock.querySelectorAll(".dock-item")];
    const dockItem = (app) => dock.querySelector(`.dock-item[data-app="${app}"]`);
    const guide = stage.querySelector(".guide");
    const startButton = stage.parentElement.querySelector("[data-guide-start]");

    // The motion tokens, read once, for what the script animates itself.
    const css = getComputedStyle(stage);
    const T1 = parseFloat(css.getPropertyValue("--d-t1")) || 120;
    const T2 = parseFloat(css.getPropertyValue("--d-t2")) || 200;
    const T3 = parseFloat(css.getPropertyValue("--d-t3")) || 280;
    const EASE_IN = css.getPropertyValue("--d-in").trim() || "ease-out";
    const EASE_OUT = css.getPropertyValue("--d-out").trim() || "ease-in";
    const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
    const time = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
    const tilts = ["-2deg", "1.5deg", "-1deg", "2deg", "-1.5deg"];
    const fine = matchMedia("(hover: hover) and (pointer: fine)");

    // What the desktop shows. Every change goes through render(), so the
    // three layouts, a recording and a screenshot all agree.
    const state = {
      front: "browser",
      open: { browser: true, chat: false },
      min: { browser: false, chat: false },
      sort: 0,
      sortOpen: false,
      sortHover: 0,
      chat: words.chat_in.map((text) => ({ kind: "in", text })),
    };
    const snapshot = () => ({ ...state, open: { ...state.open }, min: { ...state.min }, chat: state.chat.slice() });
    const visible = (app, st = state) => st.open[app] && !st.min[app] && st.front === app;
    let trash = [];
    let copied = null;
    let taken = 0;
    let seen = false;
    let choosing = null;
    let pick = null;
    let keyPick = -1;
    let countdown = null;
    let recording = null;
    let name = "wide";
    let L = layouts.wide;

    // MARK: Layout and scale

    const wideQuery = matchMedia("(min-width: 1280px)");
    const mediumQuery = matchMedia("(min-width: 768px)");

    function applyLayout() {
      name = wideQuery.matches ? "wide" : mediumQuery.matches ? "medium" : "tall";
      L = layouts[name];
      desk.dataset.layout = name;
      stage.dataset.layout = name;
      desk.style.width = L.w + "px";
      desk.style.height = L.h + "px";
      desk.style.setProperty("--card-w", L.card + "px");
      fit.style.aspectRatio = `${L.w} / ${L.h}`;
      // The Dock and the guide go where this layout keeps them.
      const dockSlot = stage.querySelector(`.dock-slot[data-slot="${name === "tall" ? "bar" : "desk"}"]`);
      if (dock.parentElement !== dockSlot) dockSlot.appendChild(dock);
      const guideSlot = stage.querySelector(`.guide-slot[data-slot="${{ wide: "desk", medium: "below", tall: "sheet" }[name]}"]`);
      if (guide.parentElement !== guideSlot) guideSlot.appendChild(guide);
      closeMenus();
      closeTrash();
      scale();
      placeControls();
      while (cards().length > L.cards) toTrash(cards()[0], true);
      layoutLine();
      render();
      placeGuide();
    }

    function scale() {
      desk.style.setProperty("--k", fit.clientWidth / L.w);
    }

    const k = () => desk.getBoundingClientRect().width / L.w;

    // From the page to the desktop's own pixels, and back.
    const at = (event) => {
      const box = desk.getBoundingClientRect();
      return {
        x: clamp(((event.clientX - box.left) / box.width) * L.w, 0, L.w),
        y: clamp(((event.clientY - box.top) / box.height) * L.h, 0, L.h),
      };
    };
    const inDesk = (rect) => {
      const box = desk.getBoundingClientRect();
      const s = box.width / L.w;
      return { x: (rect.left - box.left) / s, y: (rect.top - box.top) / s, w: rect.width / s, h: rect.height / s };
    };
    const onPage = (r) => {
      const box = desk.getBoundingClientRect();
      const s = box.width / L.w;
      return { left: box.left + r.x * s, top: box.top + r.y * s, width: r.w * s, height: r.h * s };
    };
    const place = (el, r) => Object.assign(el.style, { left: r.x + "px", top: r.y + "px", width: r.w + "px", height: r.h + "px" });
    const winRect = () => ({ x: L.win[0], y: L.win[1], w: L.win[2], h: L.win[3] });

    function placeControls() {
      ["browser", "chat"].forEach((app) => {
        controls[app].querySelectorAll(".dlight").forEach((light, i) => {
          Object.assign(light.style, { left: L.lights[i][0] + "px", top: L.lights[i][1] + "px" });
        });
      });
      place(sortButton, { x: L.sort[0], y: L.sort[1], w: L.sort[2], h: L.sort[3] });
      Object.assign(sendButton.style, { left: L.chatSend[0] + (rtl ? -14 : 14) + "px", top: L.chatSend[1] - 22 + "px" });
      Object.assign(button.style, { left: L.shot[0] + "px", top: L.shot[1] + "px" });
    }

    // MARK: Drawing the windows

    const order = (key) => [0, 1, 2].sort((a, b) => words.flights[a][key] - words.flights[b][key]);
    const measure = document.createElement("canvas").getContext("2d");
    const textWidth = (text, px) => {
      measure.font = `${px}px -apple-system, BlinkMacSystemFont, system-ui, sans-serif`;
      return measure.measureText(text).width;
    };
    const NS = "http://www.w3.org/2000/svg";
    const make = (tag, attrs) => {
      const el = document.createElementNS(NS, tag);
      Object.entries(attrs).forEach(([key, value]) => el.setAttribute(key, value));
      return el;
    };

    function renderScene(svg, st) {
      const lay = layouts[svg.dataset.layout];
      ["browser", "chat"].forEach((app) => {
        const win = svg.querySelector(`.win[data-win="${app}"]`);
        if (!win) return;
        if (visible(app, st)) win.removeAttribute("display");
        else win.setAttribute("display", "none");
      });
      const rows = order(st.sort);
      svg.querySelectorAll(".row").forEach((row) => {
        row.setAttribute("transform", `translate(0 ${lay.rowsTop + rows.indexOf(Number(row.dataset.i)) * lay.rowStep})`);
      });
      const label = svg.querySelector(".sort-label");
      if (label) label.textContent = `${words.sort}: ${words.sort_items[st.sort]}`;
      const copy = svg.querySelector(".sort-copy");
      if (copy) {
        const top = lay.menuTop - lay.win[1];
        copy.setAttribute("display", st.sortOpen ? "inline" : "none");
        copy.querySelector(".sort-hl").setAttribute("y", top + 4 + st.sortHover * 28);
        const check = copy.querySelector(".sort-check");
        check.setAttribute("transform", `translate(${check.dataset.x} ${top + 18 + st.sort * 28})`);
        copy.querySelectorAll(".sort-item").forEach((item) => {
          item.style.fill = Number(item.dataset.j) === st.sortHover ? "var(--d-on-accent)" : "var(--d-g9)";
        });
      }
      renderChat(svg, st.chat, lay);
      const app = svg.querySelector(".cap-app");
      if (app) app.textContent = st.front ? words[st.front] : words.desktop;
    }

    function renderChat(svg, items, lay) {
      const group = svg.querySelector(".msgs");
      if (!group) return;
      group.replaceChildren();
      const [ax, ay, aw, ah] = lay.chatArea;
      const W = lay.win[2];
      const max = Math.min(aw * 0.72, 300);
      const mirror = (x, w) => (rtl ? W - x - w : x);
      let y = ay + 8;
      items.forEach((item, n) => {
        if (item.kind === "in") {
          const w = Math.min(textWidth(item.text, 15) + 28, max);
          const x = mirror(ax, w);
          group.appendChild(make("rect", { x, y, width: w, height: 36, rx: 18, style: "fill:var(--d-g2)" }));
          const text = make("text", { x: rtl ? x + w - 14 : x + 14, y: y + 23, "font-size": 15, style: "fill:var(--d-g9)" });
          text.textContent = item.text;
          group.appendChild(text);
          y += 44;
          return;
        }
        // An album of the photos sent, at the end of the line of messages.
        const count = item.images.length;
        const cols = count === 1 ? 1 : 2;
        const width = Math.min(aw * 0.62, 240);
        const cell = (width - (cols - 1) * 4) / cols;
        const cellH = count === 1 ? width / clamp(item.ratios[0], 0.5, 4) : cell * 0.75;
        const rowsN = Math.ceil(count / cols);
        const height = rowsN * cellH + (rowsN - 1) * 4;
        const x = mirror(ax + aw - width, width);
        const id = `${svg.dataset.layout}-album-${n}-${Math.random().toString(36).slice(2, 7)}`;
        const clip = make("clipPath", { id });
        clip.appendChild(make("rect", { x, y, width, height, rx: 14 }));
        group.appendChild(clip);
        const album = make("g", { "clip-path": `url(#${id})` });
        item.images.forEach((image, i) => {
          const col = i % cols;
          const row = Math.floor(i / cols);
          const pic = image.cloneNode(true);
          const px = rtl ? x + width - (col + 1) * cell - col * 4 : x + col * (cell + 4);
          Object.entries({ x: px, y: y + row * (cellH + 4), width: cell, height: cellH, preserveAspectRatio: "xMidYMid slice" })
            .forEach(([key, value]) => pic.setAttribute(key, value));
          album.appendChild(pic);
        });
        group.appendChild(album);
        y += height + 8;
      });
      // The newest stays in view; older messages scroll up out of it.
      const overflow = y - (ay + ah);
      if (overflow > 0) group.setAttribute("transform", `translate(0 ${-overflow})`);
      else group.removeAttribute("transform");
    }

    // Everything on the page follows the state: the drawings, the controls
    // over them, the menu bar and the Dock.
    function render() {
      Object.values(scenes).forEach((svg) => renderScene(svg, state));
      controls.browser.hidden = !visible("browser");
      controls.chat.hidden = !visible("chat");
      barApp.textContent = state.front ? words[state.front] : words.desktop;
      dockItem("browser").classList.toggle("open", state.open.browser);
      dockItem("chat").classList.toggle("open", state.open.chat);
      dockItem("trash").classList.toggle("full", trash.length > 0);
      sortButton.querySelector("[data-sort-label]").textContent = `${words.sort}: ${words.sort_items[state.sort]}`;
      sortMenu.querySelectorAll(".dmenu-item").forEach((item) => item.setAttribute("aria-checked", String(Number(item.dataset.j) === state.sort)));
      updateSend();
      updateMenu();
    }

    // After every change: a frame for a recording under way, and the guide
    // moves along.
    function changed() {
      render();
      if (recording) recording.frames.push({ t: (performance.now() - recording.from) / 1000, st: snapshot() });
      placeGuide();
    }

    // MARK: Windows

    const group = (app) => scenes[name].querySelector(`.win[data-win="${app}"]`);
    const frontApp = () => ["browser", "chat"].find((app) => visible(app)) || null;

    // With Reduce Motion, only what fades still fades.
    function animate(el, frames, duration, easing) {
      if (reduced.matches) {
        if (frames.every((f) => f.opacity === undefined)) return Promise.resolve();
        frames = frames.map((f) => ({ opacity: f.opacity }));
      }
      return el.animate(frames, { duration, easing }).finished.catch(() => {});
    }

    // Toward the app's icon in the Dock, or from it.
    function dockOffset(app) {
      const icon = inDesk(dockItem(app).getBoundingClientRect());
      const [x, y, w, h] = L.win;
      return `translate(${icon.x + icon.w / 2 - (x + w / 2)}px, ${icon.y + icon.h / 2 - (y + h / 2)}px) scale(0.08)`;
    }

    async function openApp(app) {
      closeTrash();
      if (visible(app)) return;
      const from = state.min[app] ? dockOffset(app) : "scale(0.98)";
      const old = frontApp();
      if (old) await animate(group(old), [{ opacity: 1, transform: "none" }, { opacity: 0, transform: "scale(0.98)" }], T2, EASE_OUT);
      state.open[app] = true;
      state.min[app] = false;
      state.front = app;
      if (app !== "browser") closeSortMenu();
      changed();
      animate(group(app), [{ opacity: 0, transform: from }, { opacity: 1, transform: "none" }], T3, EASE_IN);
      did(app);
    }

    async function closeApp(app) {
      closeSortMenu();
      await animate(group(app), [{ opacity: 1, transform: "none" }, { opacity: 0, transform: "scale(0.96)" }], T3, EASE_OUT);
      state.open[app] = false;
      state.min[app] = false;
      state.front = null;
      changed();
      toast(words.toast.closed.replace("{app}", words[app]), words.toast.open, () => openApp(app));
    }

    async function minimizeApp(app) {
      closeSortMenu();
      await animate(group(app), [{ opacity: 1, transform: "none" }, { opacity: 0, transform: dockOffset(app) }], T3, EASE_OUT);
      state.min[app] = true;
      state.front = null;
      changed();
    }

    Object.entries(controls).forEach(([app, el]) => {
      el.querySelector('[data-act="close"]').addEventListener("click", () => closeApp(app));
      el.querySelector('[data-act="min"]').addEventListener("click", () => minimizeApp(app));
    });

    // MARK: Sorting the flights

    function openSortMenu() {
      if (!visible("browser")) return;
      closeMenus();
      state.sortOpen = true;
      state.sortHover = state.sort;
      Object.assign(sortMenu.style, { left: L.sort[0] + "px", top: L.sort[1] + L.sort[3] + 4 + "px", minWidth: L.sort[2] + "px" });
      sortMenu.hidden = false;
      sortButton.setAttribute("aria-expanded", "true");
      changed();
    }

    function closeSortMenu() {
      if (sortMenu.hidden && !state.sortOpen) return;
      sortMenu.hidden = true;
      sortButton.setAttribute("aria-expanded", "false");
      state.sortOpen = false;
      changed();
    }

    function sortBy(j) {
      const svg = scenes[name];
      const before = new Map([...svg.querySelectorAll(".row")].map((row) => [row, row.getBoundingClientRect().top]));
      state.sort = j;
      sortMenu.hidden = true;
      sortButton.setAttribute("aria-expanded", "false");
      state.sortOpen = false;
      changed();
      // Each row slides from where it was to its new place.
      before.forEach((top, row) => {
        const dy = (top - row.getBoundingClientRect().top) / k();
        if (dy) animate(row.querySelector(".row-in"), [{ transform: `translateY(${dy}px)` }, { transform: "none" }], T3, EASE_IN);
      });
    }

    sortButton.addEventListener("click", () => (sortMenu.hidden ? openSortMenu() : closeSortMenu()));
    sortButton.addEventListener("keydown", (event) => {
      if (event.key === "ArrowDown" && sortMenu.hidden) {
        event.preventDefault();
        openSortMenu();
        sortMenu.querySelector('[aria-checked="true"]').focus();
      }
    });
    sortMenu.addEventListener("click", (event) => {
      const item = event.target.closest(".dmenu-item");
      if (item) { sortBy(Number(item.dataset.j)); sortButton.focus({ preventScroll: true }); }
    });
    sortMenu.addEventListener("pointerover", (event) => {
      const item = event.target.closest(".dmenu-item");
      if (item && Number(item.dataset.j) !== state.sortHover) { state.sortHover = Number(item.dataset.j); changed(); }
    });
    sortMenu.addEventListener("keydown", (event) => menuKeys(event, sortMenu, () => { closeSortMenu(); sortButton.focus(); }));

    // MARK: The line

    const cards = () => [...list.children].filter((card) => !card.classList.contains("leaving"));
    const newest = () => cards().pop();

    // Spread from the middle, over the window's width, hanging from the rope.
    function layoutLine() {
      const all = cards();
      const gap = name === "tall" ? 12 : 16;
      const total = all.length * L.card + Math.max(all.length - 1, 0) * gap;
      const start = (L.w - total) / 2;
      all.forEach((card, i) => {
        const offset = start + i * (L.card + gap);
        const x = rtl ? L.w - offset - L.card : offset;
        const s = ((x + L.card / 2) / L.w * 1000 + 20) / 1040;
        const y = (12 + 116 * s * (1 - s)) * 0.48 - 4;
        card.style.transform = `translate(${x}px, ${y}px) rotate(${card.shot.tilt})`;
      });
      updateSend();
      updateMenu();
      placeGuide();
    }

    function makeCard(shot) {
      const card = template.content.firstElementChild.cloneNode(true);
      card.shot = shot;
      card.querySelector(".dcard-hit").setAttribute("aria-label", `${words.copy}: ${shot.name}`);
      card.querySelector(".dcard-x").setAttribute("aria-label", `${words.discard}: ${shot.name}`);
      const frame = card.querySelector(".dcard-img");
      frame.style.aspectRatio = String(shot.ratio);
      frame.appendChild(shot.image.cloneNode(true));
      if (shot.video) {
        card.classList.add("video");
        card.querySelector(".dbadge span").textContent = time(Math.max(shot.video.seconds, 1));
        playable(card);
      }
      return card;
    }

    // A photo goes onto the line, at the end, or back where it was.
    function hangCard(shot, at = null) {
      while (cards().length >= L.cards) toTrash(cards()[0], true);
      const card = makeCard(shot);
      list.insertBefore(card, at === null ? null : cards()[at] || null);
      layoutLine();
      return card;
    }

    function removeCard(card) {
      card.classList.add("leaving");
      setTimeout(() => card.remove(), T2);
      layoutLine();
    }

    function toTrash(card, quiet) {
      const index = cards().indexOf(card);
      trash.push({ ...card.shot, index });
      removeCard(card);
      render();
      if (!quiet) {
        toast(words.toast.removed, words.toast.undo, () => {
          const item = trash.find((entry) => entry.image === card.shot.image);
          if (!item) return;
          trash = trash.filter((entry) => entry !== item);
          hangCard(item, index);
          render();
        });
      }
    }

    list.addEventListener("click", (event) => {
      const card = event.target.closest(".dcard");
      if (!card || card.classList.contains("leaving")) return;
      if (event.target.closest(".dcard-x")) { toTrash(card); return; }
      if (!event.target.closest(".dcard-hit")) return;
      copied = card.shot;
      copyImage(card.querySelector(".dcard-img svg"), card.shot.ratio);
      toast(words.toast.copied, words.toast.paste, () => paste());
      did("copy");
    });

    // A recording plays what it caught while the pointer rests on it.
    function playable(card) {
      const { frames, seconds } = card.shot.video;
      const image = card.querySelector(".dcard-img svg");
      let frame = 0;
      let shown = -1;
      const start = () => {
        if (frame || reduced.matches || frames.length < 2) return;
        const from = performance.now();
        const step = () => {
          const t = ((performance.now() - from) / 1000) % Math.max(seconds, 0.5);
          let i = 0;
          while (i + 1 < frames.length && frames[i + 1].t <= t) i += 1;
          if (i !== shown) { renderScene(image, frames[i].st); shown = i; }
          frame = requestAnimationFrame(step);
        };
        frame = requestAnimationFrame(step);
      };
      const end = () => {
        cancelAnimationFrame(frame);
        frame = 0;
        shown = -1;
        renderScene(image, frames[0].st);
      };
      card.addEventListener("pointerenter", start);
      card.addEventListener("pointerleave", end);
      card.addEventListener("focusin", start);
      card.addEventListener("focusout", end);
      renderScene(image, frames[0].st);
    }

    // MARK: Taking it

    function crop(region) {
      const source = scenes[name];
      const image = source.cloneNode(true);
      image.removeAttribute("class");
      image.setAttribute("viewBox", [region.x, region.y, region.w, region.h].map((v) => v.toFixed(1)).join(" "));
      image.setAttribute("preserveAspectRatio", "xMidYMid slice");
      image.querySelectorAll("[data-cap]").forEach((el) => el.setAttribute("display", "inline"));
      // Colours are frozen as they are now, so the picture keeps them.
      const from = source.querySelectorAll("*");
      const to = image.querySelectorAll("*");
      from.forEach((el, i) => {
        if (!to[i] || !el.getAttribute("style")) return;
        const look = getComputedStyle(el);
        ["fill", "stroke", "stop-color", "color"].forEach((prop) => to[i].style.setProperty(prop, look.getPropertyValue(prop)));
      });
      return image;
    }

    function snap(region) {
      place(flash, region);
      flash.classList.remove("go");
      void flash.offsetWidth;
      flash.classList.add("go");
      hang(crop(region), region);
    }

    async function hang(image, region, video) {
      taken += 1;
      const shot = {
        image, video, tilt: tilts[taken % tilts.length],
        ratio: clamp(region.w / region.h, 0.8, 2.4),
        aspect: region.w / region.h,
        name: (video ? words.rec : words.shot).replace("{n}", taken),
      };
      const card = hangCard(shot);
      await wait(reduced.matches ? 0 : 60);
      const photo = card.querySelector(".dphoto");
      await flyPhoto(photo, onPage(region), photo.getBoundingClientRect(), 0, stage);
      card.classList.remove("landing");
      const label = video ? `${words.toast.recorded} · ${time(Math.max(video.seconds, 1))}` : words.toast.taken;
      toast(label, words.toast.undo, () => removeCard(card));
      did("hang");
    }

    // MARK: Choosing what to take

    function candidates() {
      const out = [];
      const app = frontApp();
      if (app) out.push(winRect());
      out.push({ x: 0, y: 0, w: L.w, h: 28 });
      if (desk.contains(dock)) out.push(inDesk(dock.getBoundingClientRect()));
      return out;
    }
    const pickAt = (p) => candidates().find((w) => p.x >= w.x && p.x <= w.x + w.w && p.y >= w.y && p.y <= w.y + w.h);
    const whole = () => ({ x: 0, y: 0, w: L.w, h: L.h });

    function choose(kind, n = 0) {
      if (recording) { stop(); return; }
      cancelCountdown();
      closeMenus();
      closeTrash();
      choosing = { kind, n };
      hint.textContent = words.hints[kind];
      overlay.hidden = false;
      overlay.classList.remove("dragging");
      tint.hidden = true;
      area.hidden = true;
      keyPick = -1;
      const box = desk.getBoundingClientRect();
      if (box.top < 0 || box.bottom > innerHeight) {
        desk.scrollIntoView({ behavior: reduced.matches ? "auto" : "smooth", block: "center" });
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
        const r = { x: Math.min(pick.from.x, p.x), y: Math.min(pick.from.y, p.y), w: Math.abs(p.x - pick.from.x), h: Math.abs(p.y - pick.from.y) };
        if (!pick.moved && Math.hypot(r.w, r.h) < 6) return;
        pick.moved = true;
        pick.r = r;
        overlay.classList.add("dragging");
        area.hidden = false;
        place(area, r);
        size.textContent = `${Math.round(r.w)} × ${Math.round(r.h)}`;
        return;
      }
      const w = pickAt(p);
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
      take(p.moved && p.r.w >= 10 && p.r.h >= 10 ? p.r : pickAt(p.from) || whole());
    });
    overlay.addEventListener("pointercancel", () => {
      pick = null;
      overlay.classList.remove("dragging");
      area.hidden = true;
    });
    overlay.addEventListener("contextmenu", (event) => { event.preventDefault(); closeOverlay(true); });
    // Return takes the whole screen, the arrows pick a window and Space
    // takes it, Escape cancels.
    overlay.addEventListener("keydown", (event) => {
      const list = candidates();
      if (event.key === "Escape") { event.preventDefault(); closeOverlay(true); }
      else if (event.key === "Enter") { event.preventDefault(); take(whole()); }
      else if (event.key === "ArrowRight" || event.key === "ArrowLeft" || event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        const step = event.key === "ArrowRight" || event.key === "ArrowDown" ? 1 : -1;
        keyPick = (keyPick + step + list.length) % list.length;
        tint.hidden = false;
        place(tint, list[keyPick]);
      } else if (event.key === " " && keyPick >= 0) {
        event.preventDefault();
        take(list[keyPick]);
      }
    });
    overlay.querySelector(".cap-cancel").addEventListener("click", () => closeOverlay(true));

    function take(region) {
      const { kind, n } = choosing;
      closeOverlay();
      if (kind === "timer") startCountdown(region, n);
      else if (kind === "record") startRecording(region);
      else snap(region);
    }

    // MARK: The timer and recording

    const setPointer = (x, y) => Object.assign(pointer.style, { transform: `translate(${x}px, ${y}px)` });

    function showCapsule(kind) {
      capsule.dataset.kind = kind;
      capsule.hidden = false;
      const label = kind === "countdown" ? words.cancelTimer : words.stop;
      capsule.setAttribute("aria-label", label);
      capsule.title = label;
    }

    function startCountdown(region, n) {
      let left = n;
      countdown = { timers: [] };
      const later = (ms, run) => countdown.timers.push(setTimeout(run, ms));
      showCapsule("countdown");
      capsule.querySelector(".cap-count").textContent = left;
      // Meanwhile someone opens the sort menu, which is what the timer is for.
      if (visible("browser")) {
        const open = Math.max(0.3, n - 2) * 1000;
        later(open, () => movePointer(L.sort[0] + L.sort[2] / 2, L.sort[1] + L.sort[3] / 2));
        later(open + T3 * 3, () => openSortMenu());
        later(open + T3 * 4, () => {
          state.sortHover = (state.sort + 1) % 3;
          changed();
        });
      }
      const tick = () => {
        left -= 1;
        if (left > 0) {
          capsule.querySelector(".cap-count").textContent = left;
          later(1000, tick);
          return;
        }
        countdown = null;
        capsule.hidden = true;
        snap(region);
        setTimeout(() => { if (!countdown) { pointer.hidden = true; closeSortMenu(); } }, 1200);
      };
      later(1000, tick);
    }

    function cancelCountdown(say) {
      if (!countdown) return;
      countdown.timers.forEach(clearTimeout);
      countdown = null;
      capsule.hidden = true;
      pointer.hidden = true;
      closeSortMenu();
      if (say) toast(words.toast.timer_off);
    }

    function startRecording(region) {
      recording = { region, from: performance.now(), frames: [{ t: 0, st: snapshot() }] };
      place(edge, region);
      edge.hidden = false;
      showCapsule("recording");
      capsule.querySelector(".cap-time").textContent = "0:00";
      desk.classList.add("recording");
      button.setAttribute("aria-label", words.stop);
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
      desk.classList.remove("recording");
      button.setAttribute("aria-label", words.take);
      updateMenu();
      hang(crop(r.region), r.region, { frames: r.frames, seconds: (performance.now() - r.from) / 1000 });
    }

    capsule.addEventListener("click", () => {
      if (countdown) cancelCountdown(true);
      else if (recording) stop();
    });

    // MARK: Sending into the chat

    function updateSend() {
      const all = cards();
      sendButton.hidden = !visible("chat") || !all.length;
      if (sendButton.hidden) return;
      sendButton.querySelector(".dsend-count").textContent = all.length;
      const thumbs = sendButton.querySelectorAll(".dsend-thumbs span");
      const last = all.slice(-2);
      thumbs.forEach((thumb) => thumb.replaceChildren());
      last.forEach((card, i) => thumbs[last.length === 1 ? 1 : i].appendChild(card.shot.image.cloneNode(true)));
      thumbs[0].hidden = last.length < 2;
    }

    async function sendAll() {
      const all = cards();
      if (!all.length) { toast(words.toast.nothing); return; }
      if (!visible("chat")) await openApp("chat");
      const before = state.chat.slice();
      const shots = all.map((card) => card.shot);
      state.chat = state.chat.concat({ kind: "album", images: shots.map((s) => s.image), ratios: shots.map((s) => s.aspect) });
      changed();
      const photos = all.map((card) => card.querySelector(".dphoto"));
      const albums = scenes[name].querySelectorAll(".msgs g[clip-path]");
      const target = albums[albums.length - 1];
      const to = target ? target.getBoundingClientRect() : sendButton.getBoundingClientRect();
      all.forEach((card) => card.classList.add("landing"));
      await Promise.all(photos.map((photo, i) => flyPhoto(photo, photo.getBoundingClientRect(), { left: to.left, top: to.top, width: to.width }, i * 70, stage)));
      all.forEach((card) => card.remove());
      layoutLine();
      setTimeout(() => {
        if (state.chat.length && state.chat[state.chat.length - 1].kind === "album") {
          state.chat = state.chat.concat({ kind: "in", text: words.chat_reply });
          changed();
        }
      }, 700);
      toast(words.toast.sent, words.toast.undo, () => {
        state.chat = before;
        shots.forEach((shot) => hangCard(shot));
        changed();
      });
      did("send");
    }

    // ⌘V in the chat, or the note's action, sends what was copied last.
    async function paste() {
      if (!copied) return;
      if (!visible("chat")) await openApp("chat");
      const before = state.chat.slice();
      state.chat = state.chat.concat({ kind: "album", images: [copied.image], ratios: [copied.aspect] });
      changed();
      toast(words.toast.sent, words.toast.undo, () => { state.chat = before; changed(); });
    }

    sendButton.addEventListener("click", sendAll);

    // MARK: The Trash

    function openTrash() {
      closeMenus();
      trashList.replaceChildren();
      trash.slice().reverse().slice(0, 6).forEach((item) => {
        const li = document.createElement("li");
        const put = document.createElement("button");
        put.type = "button";
        put.className = "trash-item";
        put.setAttribute("aria-label", `${words.put_back}: ${item.name}`);
        const thumb = item.image.cloneNode(true);
        thumb.setAttribute("preserveAspectRatio", "xMidYMid slice");
        put.appendChild(thumb);
        const label = document.createElement("span");
        label.textContent = words.put_back;
        put.appendChild(label);
        put.addEventListener("click", () => {
          trash = trash.filter((entry) => entry !== item);
          hangCard(item);
          render();
          toast(words.toast.restored);
          closeTrash(true);
        });
        li.appendChild(put);
        trashList.appendChild(li);
      });
      trashPop.classList.toggle("has-items", trash.length > 0);
      trashClear.disabled = !trash.length;
      trashPop.hidden = false;
      const w = trashPop.offsetWidth;
      const h = trashPop.offsetHeight;
      if (desk.contains(dock)) {
        const icon = inDesk(dockItem("trash").getBoundingClientRect());
        Object.assign(trashPop.style, { left: clamp(icon.x + icon.w / 2 - w / 2, 8, L.w - w - 8) + "px", top: icon.y - h - 16 + "px" });
      } else {
        Object.assign(trashPop.style, { left: (L.w - w) / 2 + "px", top: L.h - h - 12 + "px" });
      }
      dockItem("trash").setAttribute("aria-expanded", "true");
      (trashPop.querySelector("button:not(:disabled)") || trashPop).focus({ preventScroll: true });
    }

    function closeTrash(refocus) {
      if (trashPop.hidden) return;
      trashPop.hidden = true;
      dockItem("trash").setAttribute("aria-expanded", "false");
      if (refocus) dockItem("trash").focus({ preventScroll: true });
    }

    trashClear.addEventListener("click", () => {
      const gone = trash;
      trash = [];
      render();
      closeTrash(true);
      toast(words.toast.emptied, words.toast.undo, () => { trash = gone; render(); });
    });
    trashPop.addEventListener("keydown", (event) => {
      if (event.key === "Escape") { event.preventDefault(); closeTrash(true); }
    });

    // MARK: The Dock

    // The icon under the pointer grows, and its neighbours less, from their
    // bottom edge, so nothing else moves.
    function magnify(event) {
      if (!fine.matches || reduced.matches || name === "tall") return;
      const reach = (L.w > 1100 ? 120 : 100) * k();
      dockItems.forEach((item) => {
        const box = item.getBoundingClientRect();
        const d = Math.abs(event.clientX - (box.left + box.width / 2));
        const f = d < reach ? (1 + Math.cos((Math.PI * d) / reach)) / 2 : 0;
        const mag = 1 + 0.32 * f;
        item.style.setProperty("--mag", mag.toFixed(3));
        item.style.setProperty("--lift", ((mag - 1) * item.offsetHeight).toFixed(1) + "px");
      });
    }
    dock.addEventListener("pointermove", magnify);
    dock.addEventListener("pointerleave", () => dockItems.forEach((item) => { item.style.removeProperty("--mag"); item.style.removeProperty("--lift"); }));

    dockItems.forEach((item) => {
      let wait300 = 0;
      item.addEventListener("pointerenter", (event) => {
        if (event.pointerType !== "mouse") return;
        wait300 = setTimeout(() => item.classList.add("tip"), 300);
      });
      item.addEventListener("pointerleave", () => { clearTimeout(wait300); item.classList.remove("tip"); });
      item.addEventListener("click", (event) => {
        const app = item.dataset.app;
        // A tap shows the name for a moment too, as there is no hover.
        if (event.pointerType === "touch") {
          item.classList.add("tip");
          setTimeout(() => item.classList.remove("tip"), 1200);
        }
        if (app === "trash") { if (trashPop.hidden) openTrash(); else closeTrash(); }
        else openApp(app);
      });
    });
    dock.addEventListener("keydown", (event) => {
      const at = dockItems.indexOf(document.activeElement);
      if (at < 0) return;
      let next = -1;
      const forward = rtl ? "ArrowLeft" : "ArrowRight";
      const backward = rtl ? "ArrowRight" : "ArrowLeft";
      if (event.key === forward) next = (at + 1) % dockItems.length;
      if (event.key === backward) next = (at - 1 + dockItems.length) % dockItems.length;
      if (event.key === "Home") next = 0;
      if (event.key === "End") next = dockItems.length - 1;
      if (next < 0) return;
      event.preventDefault();
      dockItems.forEach((item, i) => { item.tabIndex = i === next ? 0 : -1; });
      dockItems[next].focus();
    });

    // MARK: Snapfly's menus

    function openMenu(which, anchor, event) {
      closeMenus();
      closeTrash();
      which.hidden = false;
      const a = inDesk(anchor.getBoundingClientRect());
      const w = which.offsetWidth;
      let left;
      let top;
      if (which === menu) {
        left = rtl ? a.x : a.x + a.w - w;
        top = a.y + a.h + 4;
      } else {
        const p = event && (event.clientX || event.clientY) ? at(event) : { x: rtl ? a.x + a.w : a.x, y: a.y };
        left = rtl ? p.x : p.x - w;
        top = p.y;
      }
      Object.assign(which.style, { left: clamp(left, 8, L.w - w - 8) + "px", top: clamp(top, 32, L.h - which.offsetHeight - 8) + "px" });
      if (which === menu) statusButton.setAttribute("aria-expanded", "true");
      const first = which.querySelector(".dmenu-item:not(:disabled)");
      if (first) first.focus({ preventScroll: true });
      if (which === menu) did("menu");
    }

    function closeMenus() {
      menu.hidden = true;
      shotMenu.hidden = true;
      closeSub();
      statusButton.setAttribute("aria-expanded", "false");
      if (!sortMenu.hidden) closeSortMenu();
    }

    // Beside its item on the trailing side, else the leading side, else
    // under it where the screen is too narrow for either.
    function openSub(focus) {
      const box = desk.getBoundingClientRect();
      const inner = sub.querySelector(".dmenu-sub");
      const fits = () => {
        const r = inner.getBoundingClientRect();
        return r.left >= box.left + 4 && r.right <= box.right - 4;
      };
      sub.classList.remove("flip", "below");
      sub.classList.add("open");
      subButton.setAttribute("aria-expanded", "true");
      if (!fits()) {
        sub.classList.add("flip");
        if (!fits()) sub.classList.replace("flip", "below");
      }
      if (focus) inner.querySelector(".dmenu-item").focus();
    }

    function closeSub() {
      sub.classList.remove("open", "flip", "below");
      subButton.setAttribute("aria-expanded", "false");
    }

    sub.addEventListener("pointerenter", () => openSub(false));
    sub.addEventListener("pointerleave", (event) => { if (event.pointerType === "mouse") closeSub(); });

    function updateMenu() {
      const record = menu.querySelector('[data-act="record"] span');
      record.textContent = recording ? words.stop : words.record;
      menu.querySelector('[data-act="clear"]').disabled = !cards().length;
    }

    // Up and down move, the inward arrow opens a submenu, Escape closes.
    function menuKeys(event, which, close) {
      const current = event.target.closest(".dmenu");
      const items = [...current.querySelectorAll(":scope > li > .dmenu-item:not(:disabled)")];
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
      } else if ((event.key === outward || event.key === "Escape") && current.classList.contains("dmenu-sub")) {
        event.preventDefault();
        closeSub();
        subButton.focus();
      } else if (event.key === "Escape") {
        event.preventDefault();
        close();
      } else if (event.key === "Tab") {
        closeMenus();
      }
    }

    [menu, shotMenu].forEach((which) => {
      which.addEventListener("click", (event) => {
        const item = event.target.closest(".dmenu-item");
        if (!item || item.disabled) return;
        const act = item.dataset.act;
        if (act === "sub") { openSub(true); return; }
        closeMenus();
        // Once the menu has gone, so it is not in the picture.
        if (act === "shot") setTimeout(() => choose("shot"), T2);
        else if (act === "timer") setTimeout(() => choose("timer", Number(item.dataset.n)), T2);
        else if (act === "record") { if (recording) stop(); else setTimeout(() => choose("record"), T2); }
        else if (act === "whole") setTimeout(() => snap(whole()), T2);
        else if (act === "button") {
          button.hidden = !button.hidden;
          item.setAttribute("aria-checked", String(!button.hidden));
          statusButton.focus({ preventScroll: true });
          if (button.hidden) {
            toast(words.toast.button_off, words.toast.undo, () => {
              button.hidden = false;
              item.setAttribute("aria-checked", "true");
            });
          }
        } else if (act === "clear") {
          const gone = cards().map((card) => card.shot);
          cards().forEach((card) => removeCard(card));
          toast(words.toast.cleared, words.toast.undo, () => gone.forEach((shot) => hangCard(shot)));
        }
      });
      which.addEventListener("keydown", (event) => menuKeys(event, which, () => {
        closeMenus();
        (which === menu ? statusButton : button).focus({ preventScroll: true });
      }));
    });

    statusButton.addEventListener("click", () => (menu.hidden ? openMenu(menu, statusButton) : closeMenus()));
    button.addEventListener("click", () => (recording ? stop() : choose("shot")));
    button.addEventListener("contextmenu", (event) => {
      event.preventDefault();
      if (!recording) openMenu(shotMenu, button, event);
    });

    document.addEventListener("pointerdown", (event) => {
      const inside = (el) => el.contains(event.target);
      if ((!menu.hidden || !shotMenu.hidden) && !inside(menu) && !inside(shotMenu) && !inside(statusButton)) closeMenus();
      if (!sortMenu.hidden && !inside(sortMenu) && !inside(sortButton)) closeSortMenu();
      if (!trashPop.hidden && !inside(trashPop) && !inside(dockItem("trash"))) closeTrash();
    });

    // ⌃⌥S, ⌃⌥R and ⌘V, while the desktop is in view.
    document.addEventListener("keydown", (event) => {
      if (!seen) return;
      if (event.target.closest && event.target.closest("input, textarea, [contenteditable]")) return;
      if (event.ctrlKey && event.altKey && !event.metaKey) {
        if (event.code === "KeyS" && !recording) { event.preventDefault(); choose("shot"); }
        else if (event.code === "KeyR") { event.preventDefault(); if (recording) stop(); else choose("record"); }
      } else if ((event.metaKey || event.ctrlKey) && event.code === "KeyV" && copied && visible("chat")) {
        event.preventDefault();
        paste();
      }
    });

    // MARK: Notes

    // A short note for each action, gone after four seconds, held while
    // the pointer or the keyboard is on it.
    function toast(text, label, act) {
      const note = document.createElement("div");
      note.className = "dtoast";
      const line = document.createElement("span");
      line.textContent = text;
      note.appendChild(line);
      let left = 4000;
      let since = 0;
      let timer = 0;
      const dismiss = () => {
        clearTimeout(timer);
        note.classList.add("out");
        setTimeout(() => note.remove(), T1);
      };
      if (label) {
        const action = document.createElement("button");
        action.type = "button";
        action.textContent = label;
        action.addEventListener("click", () => { act(); dismiss(); });
        note.appendChild(action);
      }
      const run = () => { since = performance.now(); timer = setTimeout(dismiss, left); };
      const hold = () => { clearTimeout(timer); left -= performance.now() - since; };
      note.addEventListener("pointerenter", hold);
      note.addEventListener("pointerleave", run);
      note.addEventListener("focusin", hold);
      note.addEventListener("focusout", run);
      toasts.appendChild(note);
      while (toasts.children.length > 2) toasts.firstElementChild.remove();
      run();
    }

    // MARK: The guide

    const guideStep = guide.querySelector("[data-guide-step]");
    const guideTitle = guide.querySelector(".guide-title");
    const guideText = guide.querySelector(".guide-text");
    const guideBar = guide.querySelector(".guide-bar span");
    const goButton = guide.querySelector("[data-guide-go]");
    const getLink = guide.querySelector(".guide-get");
    const skipButton = guide.querySelector("[data-guide-skip]");
    const visibleRect = (el) => (desk.contains(el) && el.getClientRects().length ? inDesk(el.getBoundingClientRect()) : null);

    const steps = [
      { target: () => (button.hidden ? statusButton : button), round: true, until: "choose",
        show: () => press(button.hidden ? statusButton : button, () => (button.hidden ? openMenu(menu, statusButton) : choose("shot"))) },
      { target: () => (visible("browser") ? winRect() : dockItem("browser")), until: "hang", show: drag },
      { target: () => (newest() ? newest().querySelector(".dphoto") : button), until: "copy",
        show: async () => {
          if (!newest()) await quickShot();
          const hit = newest().querySelector(".dcard-hit");
          press(hit, () => hit.click());
        } },
      { target: () => dockItem("chat"), until: "chat", show: () => press(dockItem("chat"), () => openApp("chat")) },
      { target: () => (visible("chat") && cards().length ? sendButton : dockItem("chat")), until: "send",
        show: async () => {
          if (!cards().length) await quickShot();
          if (!visible("chat")) { await openApp("chat"); await wait(T3); }
          press(sendButton, () => sendAll());
        } },
      { target: () => statusButton, round: true, until: "menu", show: () => press(statusButton, () => openMenu(menu, statusButton)) },
    ];
    let step = -1;
    let guided = false;
    let busy = false;

    function did(event) {
      if (step < 0 || step >= steps.length || steps[step].until !== event) return;
      setTimeout(() => showStep(step + 1), event === "choose" ? T2 : T3 * 2);
    }

    function showStep(n, focus) {
      step = clamp(n, 0, steps.length);
      busy = false;
      const finished = step === steps.length;
      guideStep.textContent = finished ? "" : words.step_of.replace("{n}", step + 1).replace("{total}", steps.length);
      guideBar.parentElement.hidden = finished;
      guideBar.style.setProperty("--p", (step + 1) / steps.length);
      const [title, text] = finished ? words.done : words.steps[step];
      guideTitle.textContent = title;
      guideText.textContent = text;
      goButton.hidden = finished;
      goButton.disabled = false;
      getLink.hidden = !finished;
      skipButton.textContent = finished ? words.again : words.skip;
      guide.hidden = false;
      placeGuide();
      if (focus) (finished ? getLink : goButton).focus({ preventScroll: true });
    }

    function closeGuide() {
      step = -1;
      guide.hidden = true;
      ring.hidden = true;
      dockItems.forEach((item) => item.classList.remove("hinted"));
    }

    function placeGuide() {
      dockItems.forEach((item) => item.classList.remove("hinted"));
      if (guide.hidden || step < 0) { ring.hidden = true; return; }
      const finished = step === steps.length;
      const s = finished ? null : steps[step];
      let target = s ? s.target() : null;
      // The Dock's own icons get their ring from the Dock.
      if (target instanceof Element && target.classList.contains("dock-item")) {
        target.classList.add("hinted");
        ring.hidden = true;
      }
      const rect = !target ? null : target instanceof Element ? visibleRect(target) : target;
      if (rect && !(target instanceof Element && target.classList.contains("dock-item"))) {
        const pad = s.round ? 6 : 8;
        place(ring, { x: rect.x - pad, y: rect.y - pad, w: rect.w + pad * 2, h: rect.h + pad * 2 });
        ring.style.setProperty("--ring-r", s.round ? "50%" : "var(--d-r-lg)");
        ring.hidden = false;
      } else if (!(target instanceof Element && target.classList.contains("dock-item"))) {
        ring.hidden = true;
      }
      const goal = rect || (target instanceof Element ? inDesk(target.getBoundingClientRect()) : null);
      if (name === "wide") placeBeside(goal);
      else if (name === "medium") pointUp(target instanceof Element ? target.getBoundingClientRect() : goal ? onPage(goal) : null);
      else guide.dataset.side = "none";
    }

    // Inside the desktop, beside the thing, never over a window, the Dock
    // or the screenshot button; where nothing beside it is free, the nearest
    // free spot in the empty space either side of the window.
    function placeBeside(goal) {
      const w = guide.offsetWidth;
      const h = guide.offsetHeight;
      const margin = 16;
      const blocked = [];
      if (frontApp()) blocked.push(winRect());
      if (desk.contains(dock)) blocked.push(inDesk(dock.getBoundingClientRect()));
      if (!button.hidden) blocked.push({ x: L.shot[0] - 24, y: L.shot[1] - 24, w: 48, h: 48 });
      if (goal) blocked.push(goal);
      const gap = 8;
      const hits = (r) => blocked.some((b) => r.x < b.x + b.w + gap && r.x + r.w > b.x - gap && r.y < b.y + b.h + gap && r.y + r.h > b.y - gap);
      const inside = (r) => r.x >= margin && r.y >= 28 + margin && r.x + r.w <= L.w - margin && r.y + r.h <= L.h - margin;
      let spot = null;
      if (goal) {
        const cy = clamp(goal.y + goal.h / 2 - h / 2, 28 + margin, L.h - h - margin);
        const cx = clamp(goal.x + goal.w / 2 - w / 2, margin, L.w - w - margin);
        const tries = [
          { x: goal.x + goal.w + margin, y: cy },
          { x: goal.x - margin - w, y: cy },
          { x: cx, y: goal.y + goal.h + margin },
          { x: cx, y: goal.y - margin - h },
        ];
        if (rtl) [tries[0], tries[1]] = [tries[1], tries[0]];
        spot = tries.map((p) => ({ ...p, w, h })).find((r) => inside(r) && !hits(r)) || null;
      }
      if (!spot) {
        const target = goal ? { x: goal.x + goal.w / 2, y: goal.y + goal.h / 2 } : { x: L.w, y: L.h / 2 };
        let best = Infinity;
        [margin, L.w - w - margin].forEach((x) => {
          for (let y = 28 + margin; y + h <= L.h - margin; y += 8) {
            const r = { x, y, w, h };
            if (hits(r)) continue;
            const d = Math.hypot(x + w / 2 - target.x, y + h / 2 - target.y);
            if (d < best) { best = d; spot = r; }
          }
        });
      }
      spot = spot || { x: L.w - w - margin, y: 28 + margin, w, h };
      Object.assign(guide.style, { left: spot.x + "px", top: spot.y + "px" });
      if (!goal) { guide.dataset.side = "none"; return; }
      const gx = goal.x + goal.w / 2;
      const gy = goal.y + goal.h / 2;
      let side = "none";
      if (gx > spot.x + w) side = "left";
      else if (gx < spot.x) side = "right";
      else if (gy < spot.y) side = "below";
      else if (gy > spot.y + h) side = "above";
      guide.dataset.side = side;
      guide.style.setProperty("--ax", clamp(gx - spot.x, 20, w - 20) + "px");
      guide.style.setProperty("--ay", clamp(gy - spot.y, 20, h - 20) + "px");
    }

    // Under the screen, its arrow pointing up at the thing.
    function pointUp(rect) {
      guide.style.left = "";
      guide.style.top = "";
      if (!rect) { guide.dataset.side = "none"; return; }
      guide.dataset.side = "below";
      const box = guide.getBoundingClientRect();
      guide.style.setProperty("--ax", clamp(rect.left + rect.width / 2 - box.left, 20, box.width - 20) + "px");
    }

    // Show me: the pointer goes there, presses, and it happens.
    function movePointer(x, y) {
      if (pointer.hidden) {
        pointer.style.transition = "none";
        setPointer(rtl ? L.w * 0.35 : L.w * 0.65, L.h * 0.6);
        pointer.hidden = false;
        void pointer.offsetWidth;
      }
      pointer.style.transition = reduced.matches ? "none" : `transform ${T3 * 3}ms ${EASE_IN}`;
      requestAnimationFrame(() => setPointer(x, y));
    }

    async function press(el, then) {
      if (desk.contains(el)) {
        const r = inDesk(el.getBoundingClientRect());
        movePointer(r.x + r.w / 2, r.y + r.h / 2);
        await wait(reduced.matches ? 60 : T3 * 3 + 80);
      }
      then();
      setTimeout(() => { if (!countdown) pointer.hidden = true; }, T3 * 2);
    }

    async function ensureBrowser() {
      if (!visible("browser")) { await openApp("browser"); await wait(T3); }
    }

    async function quickShot() {
      await ensureBrowser();
      const [x, y, w] = L.win;
      snap({ x: x + 16, y: y + L.rowsTop - 8, w: w - 32, h: L.rowStep * 2 });
      await wait(reduced.matches ? 100 : 1100);
    }

    // Drags over the flight list, as a person would.
    async function drag() {
      await ensureBrowser();
      if (overlay.hidden) { choose("shot"); await wait(T3); }
      const [x, y, w] = L.win;
      const from = { x: rtl ? x + w - 16 : x + 16, y: y + L.rowsTop - 8 };
      const to = { x: rtl ? x + 16 : x + w - 16, y: y + L.rowsTop + L.rowStep * 2 + 4 };
      movePointer(from.x, from.y);
      await wait(reduced.matches ? 60 : T3 * 3 + 80);
      pointer.style.transition = "none";
      overlay.classList.add("dragging");
      area.hidden = false;
      const length = reduced.matches ? 1 : 900;
      const began = performance.now();
      const region = await new Promise((done) => {
        const frame = (now) => {
          const t = Math.min((now - began) / length, 1);
          const e = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
          const p = { x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e };
          const r = { x: Math.min(from.x, p.x), y: Math.min(from.y, p.y), w: Math.abs(p.x - from.x), h: Math.abs(p.y - from.y) };
          place(area, r);
          size.textContent = `${Math.round(r.w)} × ${Math.round(r.h)}`;
          setPointer(p.x, p.y);
          if (t < 1) requestAnimationFrame(frame);
          else done(r);
        };
        requestAnimationFrame(frame);
      });
      await wait(T2);
      if (!overlay.hidden) take(region);
      setTimeout(() => { pointer.hidden = true; }, T3);
    }

    goButton.addEventListener("click", () => {
      if (step < 0 || step >= steps.length || busy) return;
      busy = true;
      goButton.disabled = true;
      steps[step].show();
    });
    skipButton.addEventListener("click", () => {
      if (step >= steps.length) showStep(0, true);
      else showStep(step + 1, true);
    });
    guide.querySelector("[data-guide-close]").addEventListener("click", () => {
      closeGuide();
      startButton.focus({ preventScroll: true });
    });
    // Enter does the step, the arrows go back and forth, Escape closes.
    guide.addEventListener("keydown", (event) => {
      const forward = rtl ? "ArrowLeft" : "ArrowRight";
      const backward = rtl ? "ArrowRight" : "ArrowLeft";
      if (event.key === "Escape") {
        event.preventDefault();
        closeGuide();
        startButton.focus({ preventScroll: true });
      } else if (event.key === forward) {
        event.preventDefault();
        showStep(Math.min(step + 1, steps.length), true);
      } else if (event.key === backward) {
        event.preventDefault();
        showStep(Math.max(step - 1, 0), true);
      } else if (event.key === "Enter" && !event.target.closest("button, a")) {
        event.preventDefault();
        if (step >= steps.length) getLink.click();
        else goButton.click();
      }
    });

    startButton.addEventListener("click", () => {
      guided = true;
      cancelCountdown();
      closeOverlay();
      desk.scrollIntoView({ behavior: reduced.matches ? "auto" : "smooth", block: "center" });
      showStep(0, true);
    });

    // MARK: Starting

    applyLayout();
    wideQuery.addEventListener("change", applyLayout);
    mediumQuery.addEventListener("change", applyLayout);
    if ("ResizeObserver" in window) new ResizeObserver(() => { scale(); placeGuide(); }).observe(fit);
    addEventListener("resize", () => { closeMenus(); closeTrash(); });
    if ("IntersectionObserver" in window) {
      new IntersectionObserver((entries) => {
        seen = entries.some((entry) => entry.isIntersecting);
      }, { threshold: 0.15 }).observe(desk);
      // The guide starts by itself the first time the desktop is in view,
      // before anything was taken; it never takes the keyboard away.
      const first = new IntersectionObserver((entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return;
        first.disconnect();
        setTimeout(() => { if (!guided && !taken && overlay.hidden) { guided = true; showStep(0); } }, T3 * 2);
      }, { threshold: 0.5 });
      first.observe(desk);
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

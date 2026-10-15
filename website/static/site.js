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
    let replied = false;
    let refilling = false;

    const hanging = () => [...list.children].filter((peg) =>
      !peg.classList.contains("leaving") && !peg.classList.contains("sending") &&
      getComputedStyle(peg).display !== "none");

    // Photos spread evenly along the rope, and close the gap when one goes.
    function layout() {
      const pegs = hanging();
      pegs.forEach((peg, i) => peg.style.setProperty("--t", ((i + 0.5) / pegs.length).toFixed(4)));
    }
    layout();
    addEventListener("resize", layout);

    function announce(text) {
      status.textContent = "";
      requestAnimationFrame(() => { status.textContent = text; });
    }

    list.addEventListener("click", (event) => {
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

    async function send(peg) {
      if (!thread) return discard(peg);
      const art = peg.querySelector(".photo-img svg");
      const bubble = document.createElement("li");
      bubble.className = "msg out image";
      const frame = document.createElement("span");
      frame.className = "photo-img";
      frame.appendChild(art.cloneNode(true));
      bubble.appendChild(frame);
      bubble.style.visibility = "hidden";
      thread.appendChild(bubble);
      thread.scrollTop = thread.scrollHeight;

      // On a small screen the chat sits below the line: bring it into view.
      const box = chat.getBoundingClientRect();
      if (box.top > innerHeight - 160 || box.bottom < 160) {
        chat.scrollIntoView({ behavior: reduced.matches ? "auto" : "smooth", block: "center" });
        await wait(reduced.matches ? 0 : 520);
      }

      const photo = peg.querySelector(".photo");
      const from = photo.getBoundingClientRect();
      const to = frame.getBoundingClientRect();
      peg.classList.add("sending");
      layout();

      if (!reduced.matches) {
        // It takes off up and away, as on the icon, then lands in the chat.
        const ghost = photo.cloneNode(true);
        ghost.classList.add("ghost");
        ghost.querySelectorAll("button, .badge-lock").forEach((el) => {
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
        ], { duration: 820, easing: "cubic-bezier(.45,.05,.25,1)" });
        await flight.finished.catch(() => {});
        ghost.remove();
      }

      bubble.style.visibility = "";
      bubble.classList.add("landed");
      peg.remove();
      layout();
      announce(status.dataset.sent);
      trimThread();
      if (!replied && reply) {
        replied = true;
        setTimeout(answer, 700);
      }
      refillIfEmpty();
    }

    async function answer() {
      const typing = document.createElement("li");
      typing.className = "msg in typing pop";
      typing.innerHTML = "<p aria-hidden=\"true\"><i></i><i></i><i></i></p>";
      thread.appendChild(typing);
      thread.scrollTop = thread.scrollHeight;
      await wait(reduced.matches ? 200 : 1100);
      const message = reply.content.firstElementChild.cloneNode(true);
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

  // A real copy of the picture, so ⌘V after a click pastes it.
  function copyImage(svg) {
    if (!svg || !navigator.clipboard || !window.ClipboardItem) return;
    const copy = svg.cloneNode(true);
    copy.setAttribute("width", "900");
    copy.setAttribute("height", "600");
    const source = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(new XMLSerializer().serializeToString(copy));
    const png = new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => {
        const canvas = document.createElement("canvas");
        canvas.width = 900;
        canvas.height = 600;
        canvas.getContext("2d").drawImage(image, 0, 0, 900, 600);
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

    // Where each file hangs is worked out from the layout, not from where
    // it is drawn, so a sweep in the middle of another lands right.
    const sweep = () => {
      const files = [...desk.querySelectorAll(".file")].filter((f) => getComputedStyle(f).display !== "none");
      const width = desk.clientWidth;
      const deskBox = desk.getBoundingClientRect();
      const ropeBox = desk.querySelector(".desk-rope").getBoundingClientRect();
      const ropeTop = ropeBox.top - deskBox.top;
      files.forEach((file, i) => {
        const center = file.offsetLeft + (rtl ? file.offsetWidth : 0);
        const t = (i + 0.5) / files.length;
        const x = (rtl ? 1 - t : t) * width;
        const y = ropeTop + ropeBox.height * (0.1 + 1.2 * t * (1 - t)) - 2;
        file.style.setProperty("--dx", `${x - center}px`);
        file.style.setProperty("--dy", `${y - file.offsetTop}px`);
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
    const master = cover.querySelector("[data-master]");
    const kinds = cover.querySelector("[data-kinds]");
    const apply = () => {
      kinds.disabled = !master.checked;
      const chosen = new Set([...kinds.querySelectorAll("input:checked")].map((box) => box.value));
      let any = false;
      invoice.querySelectorAll("[data-pd]").forEach((field) => {
        const covered = master.checked && chosen.has(field.dataset.pd);
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
  const screen = document.querySelector("[data-style-screen]");
  const caption = document.querySelector("[data-style-caption]");
  if (styles && screen) {
    styles.addEventListener("change", (event) => {
      screen.dataset.style = event.target.value;
      if (caption) caption.textContent = event.target.dataset.caption;
    });
  }
})();

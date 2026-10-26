// Snapfly's share links: a covered screenshot, a recording or a PDF,
// uploaded from the app, behind a link that works for seven days. Files sit
// in an R2 bucket whose lifecycle rule deletes them after that; the Worker
// refuses them from the moment they are due, in case the rule runs late.
// Nothing about who uploaded is kept: no name, no address, no account.

/** How long a link works. */
export const DAYS = 7;
/** The largest file taken, under the 100 MB a Worker accepts. */
export const MAX_BYTES = 95 * 1024 * 1024;
/** What all uploads together may come to in a day: plenty for people
 * sharing their screenshots, and a bound on what anyone can make the bucket
 * hold, as uploads need no account. Seven days of it stay within R2's free
 * 10 GB; raise it when more people share. */
export const DAILY_BYTES = 1_200_000_000;

/** What may be shared, by type, and how it is shown. Never HTML or SVG. */
export const TYPES = {
  "image/png": { ext: "png", kind: "image" },
  "image/jpeg": { ext: "jpg", kind: "image" },
  "image/gif": { ext: "gif", kind: "image" },
  "image/heic": { ext: "heic", kind: "image" },
  "video/mp4": { ext: "mp4", kind: "video" },
  "video/quicktime": { ext: "mov", kind: "video" },
  "application/pdf": { ext: "pdf", kind: "pdf" },
};

const ID = /^[A-Za-z0-9_-]{22}$/;

export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (error) {
      console.error(error);
      return json({ error: "server" }, 500);
    }
  },
};

async function route(request, env) {
  const url = new URL(request.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const method = request.method;

  if (parts.length === 2 && parts[0] === "api" && parts[1] === "files" && method === "POST") {
    return upload(request, env, url);
  }
  if (parts.length === 3 && parts[0] === "api" && parts[1] === "files" && method === "DELETE") {
    return remove(request, env, parts[2]);
  }
  if (method !== "GET" && method !== "HEAD") return json({ error: "method" }, 405);
  if (parts.length === 0) return Response.redirect(env.SITE_URL, 302);
  if (parts.length === 1 && ID.test(parts[0])) return page(request, env, url, parts[0]);
  if (parts.length === 2 && ID.test(parts[0]) && parts[1] === "file") return file(request, env, parts[0]);
  return notFound(request);
}

// MARK: Upload and delete

/** How many bytes were uploaded today, by everyone together: one count in
 * one place, so uploads at the same moment are counted one after another.
 * Nothing else is kept, not who sent what. */
export class Quota {
  constructor(state) {
    this.state = state;
  }

  async fetch(request) {
    const { bytes } = await request.json();
    const today = new Date().toISOString().slice(0, 10);
    const day = await this.state.storage.get("day");
    const sent = day === today ? (await this.state.storage.get("bytes")) || 0 : 0;
    if (!(bytes > 0) || sent + bytes > DAILY_BYTES) return new Response(null, { status: 429 });
    await this.state.storage.put({ day: today, bytes: sent + bytes });
    return new Response(null, { status: 204 });
  }
}

async function upload(request, env, url) {
  const type = (request.headers.get("Content-Type") || "").split(";")[0].trim().toLowerCase();
  const known = TYPES[type];
  if (!known) return json({ error: "type" }, 415);
  const length = Number(request.headers.get("Content-Length") || "0");
  if (!length) return json({ error: "length" }, 411);
  if (length > MAX_BYTES) return json({ error: "size" }, 413);

  // A few uploads a minute from one place are plenty; more is abuse.
  if (env.UPLOADS) {
    const place = request.headers.get("CF-Connecting-IP") || "unknown";
    const { success } = await env.UPLOADS.limit({ key: place });
    if (!success) return json({ error: "busy" }, 429);
  }
  // All uploads together, a day at a time; counted, never who sent them.
  if (env.QUOTA) {
    const quota = env.QUOTA.get(env.QUOTA.idFromName("uploads"));
    const answer = await quota.fetch("https://quota/take", { method: "POST", body: JSON.stringify({ bytes: length }) });
    if (answer.status !== 204) return json({ error: "busy" }, 429);
  }

  const id = randomID();
  const token = randomID() + randomID();
  const created = new Date();
  await env.SHARES.put(key(id), request.body, {
    httpMetadata: { contentType: type },
    customMetadata: { token: await sha256(token), kind: known.kind, ext: known.ext },
  });
  const expires = new Date(created.getTime() + DAYS * 86400000);
  return json({ id, url: `${url.origin}/${id}`, deleteToken: token, expires: expires.toISOString() }, 201);
}

async function remove(request, env, id) {
  if (!ID.test(id)) return json({ error: "id" }, 404);
  const object = await env.SHARES.head(key(id));
  if (!object) return json({ deleted: true }, 200);
  const given = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!given || !same(await sha256(given), object.customMetadata?.token || "")) {
    return json({ error: "token" }, 403);
  }
  await env.SHARES.delete(key(id));
  return json({ deleted: true }, 200);
}

// MARK: Showing a link

async function page(request, env, url, id) {
  const object = await env.SHARES.head(key(id));
  if (!object || expired(object)) return notFound(request);
  const words = wording(request);
  const kind = object.customMetadata?.kind || "image";
  const ext = object.customMetadata?.ext || "png";
  const src = `/${id}/file`;
  const fileURL = `${url.origin}${src}`;
  const left = Math.max(1, Math.ceil((due(object) - Date.now()) / 86400000));
  const shown =
    kind === "video"
      ? `<video src="${src}" controls playsinline preload="metadata"></video>`
      : kind === "pdf"
        ? `<iframe src="${src}" title="PDF"></iframe>`
        : `<img src="${src}" alt="">`;
  const preview = kind === "image" ? `<meta property="og:image" content="${fileURL}">` : "";
  const html = `<!doctype html>
<html lang="${words.lang}" dir="${words.lang === "ar" ? "rtl" : "ltr"}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<meta name="referrer" content="no-referrer">
<title>${words.title}</title>
<meta property="og:title" content="${words.title}">
<meta property="og:site_name" content="Snapfly">
${preview}
<style>
:root { color-scheme: light dark; --bg: #f5f5f7; --fg: #1d1d1f; --dim: #6e6e73; --card: #fff; --edge: rgba(0,0,0,.1); }
@media (prefers-color-scheme: dark) { :root { --bg: #161617; --fg: #f5f5f7; --dim: #a1a1a6; --card: #232326; --edge: rgba(255,255,255,.12); } }
* { box-sizing: border-box; }
body { margin: 0; min-height: 100vh; background: var(--bg); color: var(--fg);
  font: 15px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif;
  display: flex; flex-direction: column; align-items: center; padding: 24px 16px; gap: 16px; }
main { width: 100%; max-width: 1100px; background: var(--card); border: 1px solid var(--edge);
  border-radius: 16px; padding: 4px; }
img, video { display: block; width: 100%; height: auto; max-height: 82vh; object-fit: contain; border-radius: 12px; }
iframe { display: block; width: 100%; height: 82vh; border: 0; border-radius: 12px; }
nav { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: center; justify-content: center; color: var(--dim); font-size: 13px; }
a { color: inherit; }
a.save { color: var(--fg); font-weight: 600; text-decoration: none; padding: 6px 14px;
  border: 1px solid var(--edge); border-radius: 999px; }
</style>
</head>
<body>
<main>${shown}</main>
<nav>
<a class="save" href="${src}" download="Snapfly.${ext}">${words.save}</a>
<span>${words.left(left)}</span>
<span>${words.made} <a href="${esc(env.SITE_URL)}">Snapfly</a></span>
<a href="${esc(env.SITE_URL)}support.html">${words.report}</a>
</nav>
</body>
</html>`;
  return new Response(request.method === "HEAD" ? null : html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Security-Policy":
        "default-src 'none'; img-src 'self'; media-src 'self'; frame-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      ...common(),
    },
  });
}

async function file(request, env, id) {
  let object;
  try {
    object = await env.SHARES.get(key(id), { range: request.headers });
  } catch {
    // A range outside the file: the whole file instead.
    object = await env.SHARES.get(key(id));
  }
  if (!object || expired(object)) return notFound(request);
  const headers = new Headers(common());
  object.writeHttpMetadata(headers);
  headers.set("ETag", object.httpEtag);
  headers.set("Accept-Ranges", "bytes");
  headers.set("Cache-Control", "private, max-age=3600");
  headers.set("Content-Disposition", "inline");
  // Shown in the page or on its own, never inside another site. A picture or
  // a film runs nothing; a PDF keeps the browser's own viewer.
  headers.set(
    "Content-Security-Policy",
    object.customMetadata?.kind === "pdf" ? "frame-ancestors 'self'" : "default-src 'none'; sandbox; frame-ancestors 'self'",
  );
  let status = 200;
  const range = object.range;
  if (range && request.headers.has("Range")) {
    const size = object.size;
    const start = "suffix" in range ? size - range.suffix : range.offset ?? 0;
    const length = "suffix" in range ? range.suffix : range.length ?? size - start;
    headers.set("Content-Range", `bytes ${start}-${start + length - 1}/${size}`);
    headers.set("Content-Length", String(length));
    status = 206;
  } else {
    headers.set("Content-Length", String(object.size));
  }
  return new Response(request.method === "HEAD" ? null : object.body, { status, headers });
}

function notFound(request) {
  const words = wording(request);
  const html = `<!doctype html><html lang="${words.lang}" dir="${words.lang === "ar" ? "rtl" : "ltr"}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex"><title>Snapfly</title><style>:root{color-scheme:light dark}body{margin:0;min-height:100vh;display:grid;place-items:center;font:15px/1.45 -apple-system,BlinkMacSystemFont,system-ui,sans-serif;padding:16px;text-align:center}</style></head><body><p>${words.gone}</p></body></html>`;
  return new Response(request.method === "HEAD" ? null : html, {
    status: 404,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'",
      ...common(),
    },
  });
}

// MARK: Helpers

export function key(id) {
  return `f/${id}`;
}

function due(object) {
  return new Date(object.uploaded).getTime() + DAYS * 86400000;
}

export function expired(object, now = Date.now()) {
  return now >= due(object);
}

function common() {
  return {
    "X-Content-Type-Options": "nosniff",
    "X-Robots-Tag": "noindex, nofollow",
    "Referrer-Policy": "no-referrer",
  };
}

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...common() },
  });
}

/** 22 characters from 16 random bytes: never guessed. */
export function randomID() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Compares two hashes in a time that does not depend on where they differ. */
function same(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function esc(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

/** The page's few words, in German, Arabic or English, as the browser asks. */
export function wording(request) {
  const asked = (request.headers.get("Accept-Language") || "").toLowerCase();
  const first = asked.split(",").map((part) => part.trim().slice(0, 2)).find((code) => ["de", "ar", "en"].includes(code));
  switch (first) {
    case "de":
      return {
        lang: "de",
        title: "Mit Snapfly geteilt",
        save: "Sichern",
        left: (days) => (days === 1 ? "Der Link gilt noch 1 Tag" : `Der Link gilt noch ${days} Tage`),
        made: "Geteilt mit",
        report: "Missbrauch melden",
        gone: "Dieser Link ist abgelaufen oder wurde gelöscht.",
      };
    case "ar":
      return {
        lang: "ar",
        title: "مُشارَك عبر Snapfly",
        save: "حفظ",
        left: (days) =>
          days === 1 ? "يعمل الرابط يومًا واحدًا بعد" : days === 2 ? "يعمل الرابط يومين بعد" : `يعمل الرابط ${days} أيام بعد`,
        made: "شُورك عبر",
        report: "الإبلاغ عن إساءة",
        gone: "انتهت صلاحية هذا الرابط أو حُذف.",
      };
    default:
      return {
        lang: "en",
        title: "Shared with Snapfly",
        save: "Save",
        left: (days) => (days === 1 ? "The link works for 1 more day" : `The link works for ${days} more days`),
        made: "Shared with",
        report: "Report abuse",
        gone: "This link has expired or was deleted.",
      };
  }
}

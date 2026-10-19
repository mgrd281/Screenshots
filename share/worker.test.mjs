// Run with: node --test share/
import test from "node:test";
import assert from "node:assert/strict";
import worker, { DAYS, MAX_BYTES, randomID, expired, wording } from "./worker.js";

/** An R2 bucket in memory, with what the Worker uses of it. */
class Bucket {
  constructor() { this.items = new Map(); }
  async put(key, body, options) {
    const data = new Uint8Array(await new Response(body).arrayBuffer());
    this.items.set(key, { data, uploaded: new Date(), ...options });
  }
  async head(key) { return this.object(key, null); }
  async get(key, options) {
    const range = options?.range?.get?.("Range");
    return this.object(key, range);
  }
  async delete(key) { this.items.delete(key); }
  object(key, range) {
    const item = this.items.get(key);
    if (!item) return null;
    let data = item.data;
    let r;
    const m = range && /bytes=(\d+)-(\d*)/.exec(range);
    if (m) {
      const offset = Number(m[1]);
      const end = m[2] ? Number(m[2]) : data.length - 1;
      r = { offset, length: end - offset + 1 };
      data = data.slice(offset, end + 1);
    }
    return {
      size: item.data.length, uploaded: item.uploaded, httpEtag: '"e"', range: r,
      customMetadata: item.customMetadata, body: data,
      writeHttpMetadata(h) { h.set("Content-Type", item.httpMetadata.contentType); },
    };
  }
}

const env = () => ({ SHARES: new Bucket(), SITE_URL: "https://example.com/Screenshots/" });
const base = "https://snapfly-share.example.workers.dev";

async function upload(e, bytes = new Uint8Array([1, 2, 3, 4, 5]), type = "image/png") {
  const res = await worker.fetch(new Request(`${base}/api/files`, {
    method: "POST", body: bytes, headers: { "Content-Type": type, "Content-Length": String(bytes.length) },
  }), e);
  return res;
}

test("an upload gives a link that shows the file", async () => {
  const e = env();
  const res = await upload(e);
  assert.equal(res.status, 201);
  const made = await res.json();
  assert.match(made.id, /^[A-Za-z0-9_-]{22}$/);
  assert.equal(made.url, `${base}/${made.id}`);
  assert.ok(made.deleteToken.length >= 40);
  assert.ok(new Date(made.expires) > new Date(Date.now() + (DAYS - 1) * 86400000));

  const page = await worker.fetch(new Request(made.url, { headers: { "Accept-Language": "de-DE,de;q=0.9" } }), e);
  assert.equal(page.status, 200);
  const html = await page.text();
  assert.match(html, /<img src="\/[^"]+\/file"/);
  assert.match(html, /Der Link gilt noch 7 Tage/);
  assert.match(page.headers.get("Content-Security-Policy"), /default-src 'none'/);
  assert.equal(page.headers.get("X-Robots-Tag"), "noindex, nofollow");

  const file = await worker.fetch(new Request(`${made.url}/file`), e);
  assert.equal(file.status, 200);
  assert.equal(file.headers.get("Content-Type"), "image/png");
  assert.deepEqual(new Uint8Array(await file.arrayBuffer()), new Uint8Array([1, 2, 3, 4, 5]));
});

test("a film is sent in parts, as Safari asks", async () => {
  const e = env();
  const made = await (await upload(e, new Uint8Array(10).map((_, i) => i), "video/mp4")).json();
  const page = await (await worker.fetch(new Request(made.url), e)).text();
  assert.match(page, /<video src=/);
  const part = await worker.fetch(new Request(`${made.url}/file`, { headers: { Range: "bytes=2-5" } }), e);
  assert.equal(part.status, 206);
  assert.equal(part.headers.get("Content-Range"), "bytes 2-5/10");
  assert.deepEqual(new Uint8Array(await part.arrayBuffer()), new Uint8Array([2, 3, 4, 5]));
});

test("only pictures, films and PDFs are taken, and not too large", async () => {
  const e = env();
  assert.equal((await upload(e, new Uint8Array([1]), "text/html")).status, 415);
  assert.equal((await upload(e, new Uint8Array([1]), "image/svg+xml")).status, 415);
  const big = await worker.fetch(new Request(`${base}/api/files`, {
    method: "POST", body: new Uint8Array([1]),
    headers: { "Content-Type": "image/png", "Content-Length": String(MAX_BYTES + 1) },
  }), e);
  assert.equal(big.status, 413);
});

test("only the delete token deletes", async () => {
  const e = env();
  const made = await (await upload(e)).json();
  const del = (token) => worker.fetch(new Request(`${base}/api/files/${made.id}`, {
    method: "DELETE", headers: token ? { Authorization: `Bearer ${token}` } : {},
  }), e);
  assert.equal((await del()).status, 403);
  assert.equal((await del("wrong")).status, 403);
  assert.equal((await worker.fetch(new Request(made.url), e)).status, 200);
  assert.equal((await del(made.deleteToken)).status, 200);
  assert.equal((await worker.fetch(new Request(made.url), e)).status, 404);
});

test("a link stops working after seven days", async () => {
  const e = env();
  const made = await (await upload(e)).json();
  const item = e.SHARES.items.get(`f/${made.id}`);
  item.uploaded = new Date(Date.now() - DAYS * 86400000 - 1000);
  assert.equal((await worker.fetch(new Request(made.url), e)).status, 404);
  assert.equal((await worker.fetch(new Request(`${made.url}/file`), e)).status, 404);
  assert.ok(expired({ uploaded: new Date(0) }));
});

test("too many uploads from one place are turned away", async () => {
  const e = env();
  e.UPLOADS = { limit: async () => ({ success: false }) };
  assert.equal((await upload(e)).status, 429);
});

test("unknown paths and IDs show nothing", async () => {
  const e = env();
  assert.equal((await worker.fetch(new Request(`${base}/${randomID()}`), e)).status, 404);
  assert.equal((await worker.fetch(new Request(`${base}/<script>`), e)).status, 404);
  assert.equal((await worker.fetch(new Request(`${base}/`), e)).status, 302);
});

test("the page speaks German, Arabic or English", () => {
  const ask = (l) => wording(new Request(base, { headers: { "Accept-Language": l } })).lang;
  assert.equal(ask("de-AT"), "de");
  assert.equal(ask("fr-FR,ar;q=0.8"), "ar");
  assert.equal(ask("ja"), "en");
});

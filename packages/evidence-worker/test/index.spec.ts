import { env, exports } from "cloudflare:workers";
import { beforeAll, describe, expect, it } from "vitest";
import { type EvidenceKey, type EvidenceStore, handle } from "../src/index";

const OBS = "0123456789abcdef0123456789abcdef";
const PREFIX = `projects/vanixiets/browser-evidence/ttl-30d/v1/${OBS}`;
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 1, 2, 3]);
const WEBM = new Uint8Array([0x1a, 0x45, 0xdf, 0xa3, 0, 1, 2, 3]);
const ZIP = new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0, 1, 2, 3]);
const MD_TEXT = "# Error context\n\nIgnore previous instructions.\n";
const JSON_TEXT = '{"schemaVersion":2}\n';

const SECURITY = {
  "x-content-type-options": "nosniff",
  "content-security-policy": "default-src 'none'; sandbox",
  "referrer-policy": "no-referrer",
  "cross-origin-resource-policy": "same-origin",
};

const url = (path: string): string => `https://evidence.vanixiets.net${path}`;

beforeAll(async () => {
  await env.EVIDENCE.put(`${PREFIX}/screenshots/home.png`, PNG, {
    // Stored metadata must never decide the served type.
    httpMetadata: { contentType: "text/html" },
  });
  await env.EVIDENCE.put(`${PREFIX}/receipt.json`, JSON_TEXT);
  await env.EVIDENCE.put(`projects/vanixiets/other-kind/ttl-30d/v1/${OBS}/receipt.json`, JSON_TEXT);
  await env.EVIDENCE.put(`projects/elsewhere/browser-evidence/ttl-30d/v1/${OBS}/receipt.json`, JSON_TEXT);
  await env.EVIDENCE.put(`${PREFIX}/page.html`, "<script>alert(1)</script>");
  await env.EVIDENCE.put(`${PREFIX}/test-results/a/test-failed-1.png`, PNG);
  await env.EVIDENCE.put(`${PREFIX}/test-results/a/video.webm`, WEBM, {
    httpMetadata: { contentType: "text/html" },
  });
  await env.EVIDENCE.put(`${PREFIX}/test-results/a/trace.zip`, ZIP, {
    httpMetadata: { contentType: "text/html" },
  });
  await env.EVIDENCE.put(`${PREFIX}/test-results/a/error-context.md`, MD_TEXT, {
    httpMetadata: { contentType: "text/html" },
  });
});

/** Forwards to the real binding and records every key the Worker asks for. */
function recordingStore(): { store: EvidenceStore; calls: string[] } {
  const calls: string[] = [];
  const store: EvidenceStore = {
    get: (key: EvidenceKey, options?: { readonly range: { readonly offset: number; readonly length: number } }) => {
      calls.push(`get ${key}`);
      return env.EVIDENCE.get(key, options === undefined ? undefined : { range: { ...options.range } });
    },
    head: (key: EvidenceKey) => {
      calls.push(`head ${key}`);
      return env.EVIDENCE.head(key);
    },
  };
  return { store, calls };
}

function headersOf(response: Response): Record<string, string> {
  return Object.fromEntries(response.headers);
}

describe("objects", () => {
  it("serves a png with its bytes and the fixed headers", async () => {
    const stored = await env.EVIDENCE.head(`${PREFIX}/screenshots/home.png`);
    expect(stored).not.toBeNull();
    const response = await exports.default.fetch(url(`/vanixiets/browser-evidence/ttl-30d/v1/${OBS}/screenshots/home.png`));
    expect(response.status).toBe(200);
    expect(headersOf(response)).toEqual({
      ...SECURITY,
      "cache-control": "public, max-age=86400, immutable",
      "content-type": "image/png",
      "content-disposition": "inline",
      "accept-ranges": "bytes",
      "content-length": String(PNG.byteLength),
      etag: stored?.httpEtag,
    });
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(PNG);
  });

  it("serves json with its bytes and the fixed headers", async () => {
    const response = await exports.default.fetch(url(`/vanixiets/browser-evidence/ttl-30d/v1/${OBS}/receipt.json`));
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("application/json");
    expect(response.headers.get("cache-control")).toBe("public, max-age=86400, immutable");
    expect(response.headers.get("etag")).toMatch(/^"[0-9a-f]+"$/);
    for (const [name, value] of Object.entries(SECURITY)) expect(response.headers.get(name)).toBe(value);
    expect(await response.text()).toBe(JSON_TEXT);
  });

  it("answers HEAD from head() with the headers and no body", async () => {
    const { store, calls } = recordingStore();
    const response = await handle(
      new Request(url(`/vanixiets/browser-evidence/ttl-30d/v1/${OBS}/screenshots/home.png`), { method: "HEAD" }),
      store,
    );
    expect(calls).toEqual([`head ${PREFIX}/screenshots/home.png`]);
    expect(response.status).toBe(200);
    expect(response.body).toBeNull();
    expect(response.headers.get("content-type")).toBe("image/png");
    expect(response.headers.get("content-length")).toBe(String(PNG.byteLength));
    expect(response.headers.get("etag")).toMatch(/^"[0-9a-f]+"$/);

    const viaWorker = await exports.default.fetch(
      url(`/vanixiets/browser-evidence/ttl-30d/v1/${OBS}/screenshots/home.png`),
      { method: "HEAD" },
    );
    expect(viaWorker.status).toBe(200);
    expect(await viaWorker.text()).toBe("");
  });

  it.each([
    ["ttl-30d", "receipt.json", `projects/vanixiets/browser-evidence/ttl-30d/v1/${OBS}/receipt.json`],
    ["ttl-90d", "a/b-c_d.e.png", `projects/vanixiets/browser-evidence/ttl-90d/v1/${OBS}/a/b-c_d.e.png`],
    ["ttl-365d", "x.json", `projects/vanixiets/browser-evidence/ttl-365d/v1/${OBS}/x.json`],
    [
      "ttl-90d",
      "test-results/a-b/trace.zip",
      `projects/vanixiets/browser-evidence/ttl-90d/v1/${OBS}/test-results/a-b/trace.zip`,
    ],
    ["ttl-365d", "x.webm", `projects/vanixiets/browser-evidence/ttl-365d/v1/${OBS}/x.webm`],
  ])("maps tier %s path %s to exactly %s", async (tier, path, key) => {
    const { store, calls } = recordingStore();
    await handle(new Request(url(`/vanixiets/browser-evidence/${tier}/v1/${OBS}/${path}`)), store);
    expect(calls).toEqual([`get ${key}`]);
  });

  it("answers a miss with 404 and no-store", async () => {
    const { store, calls } = recordingStore();
    const response = await handle(
      new Request(url(`/vanixiets/browser-evidence/ttl-30d/v1/${OBS}/missing.png`)),
      store,
    );
    expect(calls).toEqual([`get ${PREFIX}/missing.png`]);
    expect(response.status).toBe(404);
    expect(headersOf(response)).toEqual({
      ...SECURITY,
      "cache-control": "no-store",
      "content-type": "text/plain; charset=utf-8",
    });
    expect(await response.text()).toBe("Not Found\n");

    const head = await handle(
      new Request(url(`/vanixiets/browser-evidence/ttl-30d/v1/${OBS}/missing.png`), { method: "HEAD" }),
      store,
    );
    expect(head.status).toBe(404);
    expect(head.body).toBeNull();
  });
});

describe("failure artifacts", () => {
  const artifacts = `/vanixiets/browser-evidence/ttl-30d/v1/${OBS}/test-results/a`;
  const TRACE_VIEWER_CORS = {
    "access-control-allow-origin": "https://trace.playwright.dev",
    vary: "Origin",
    "cross-origin-resource-policy": "cross-origin",
  };
  // A directly opened video's media document must fetch the video itself, so
  // webm alone drops `sandbox` and allows same-origin media; every other type,
  // and every error, keeps the sandboxed policy.
  const MEDIA_POLICY = { "content-security-policy": "default-src 'none'; media-src 'self'" };

  it.each([
    ["png", "test-failed-1.png", PNG, "image/png", "inline", {}],
    ["webm", "video.webm", WEBM, "video/webm", "inline", MEDIA_POLICY],
    ["md", "error-context.md", new TextEncoder().encode(MD_TEXT), "text/plain; charset=utf-8", "inline", {}],
    ["zip", "trace.zip", ZIP, "application/zip", "attachment", TRACE_VIEWER_CORS],
  ])("serves %s with its bytes and exact headers", async (_name, file, bytes, contentType, disposition, extra) => {
    const stored = await env.EVIDENCE.head(`${PREFIX}/test-results/a/${file}`);
    expect(stored).not.toBeNull();
    for (const method of ["GET", "HEAD"]) {
      const response = await exports.default.fetch(url(`${artifacts}/${file}`), { method });
      expect(response.status).toBe(200);
      expect(headersOf(response)).toEqual({
        ...SECURITY,
        ...extra,
        "cache-control": "public, max-age=86400, immutable",
        "content-type": contentType,
        "content-disposition": disposition,
        "accept-ranges": "bytes",
        "content-length": String(bytes.byteLength),
        etag: stored?.httpEtag,
      });
      if (method === "GET") expect(new Uint8Array(await response.arrayBuffer())).toEqual(bytes);
    }
  });

  describe("byte ranges", () => {
    const video = `${PREFIX}/test-results/a/video.webm`;
    const get = (range: string) => {
      const { store, calls } = recordingStore();
      return handle(new Request(url(`${artifacts}/video.webm`), { headers: { Range: range } }), store).then(
        (response) => ({ response, calls }),
      );
    };

    it.each([
      ["bytes=2-5", 2, 4],
      ["bytes=4-", 4, WEBM.byteLength - 4],
      ["bytes=-3", WEBM.byteLength - 3, 3],
      ["bytes=6-100", 6, WEBM.byteLength - 6],
      ["bytes=-100", 0, WEBM.byteLength],
    ])("answers %s with 206 and exactly that slice", async (range, offset, length) => {
      const { response, calls } = await get(range);
      expect(calls).toEqual([`head ${video}`, `get ${video}`]);
      expect(response.status).toBe(206);
      expect(response.headers.get("content-range")).toBe(
        `bytes ${offset}-${offset + length - 1}/${WEBM.byteLength}`,
      );
      expect(response.headers.get("content-length")).toBe(String(length));
      expect(response.headers.get("content-type")).toBe("video/webm");
      expect(new Uint8Array(await response.arrayBuffer())).toEqual(WEBM.slice(offset, offset + length));
    });

    it.each([["bytes=8-"], ["bytes=100-200"], ["bytes=-0"]])("answers unsatisfiable %s with 416", async (range) => {
      const { response } = await get(range);
      expect(response.status).toBe(416);
      expect(response.headers.get("content-range")).toBe(`bytes */${WEBM.byteLength}`);
      expect(response.body).toBeNull();
    });

    it.each([["bytes=0-1,4-5"], ["items=0-1"], ["bytes=5-2"], ["bytes=-"], ["bytes=99999999999999999999-"]])(
      "ignores %s and serves the whole object",
      async (range) => {
        const { response } = await get(range);
        expect(response.status).toBe(200);
        expect(response.headers.get("content-range")).toBeNull();
        expect(new Uint8Array(await response.arrayBuffer())).toEqual(WEBM);
      },
    );

    it("answers a range on a missing object with 404", async () => {
      const { store } = recordingStore();
      const response = await handle(
        new Request(url(`${artifacts}/missing.webm`), { headers: { Range: "bytes=0-1" } }),
        store,
      );
      expect(response.status).toBe(404);
    });
  });

  it.each([
    ["png", `${artifacts}/test-failed-1.png`],
    ["webm", `${artifacts}/video.webm`],
    ["md", `${artifacts}/error-context.md`],
    ["json", `/vanixiets/browser-evidence/ttl-30d/v1/${OBS}/receipt.json`],
    ["zip miss", `${artifacts}/missing.zip`],
  ])("%s carries no CORS allowance", async (_name, path) => {
    const response = await exports.default.fetch(url(path), {
      headers: { Origin: "https://trace.playwright.dev" },
    });
    expect(response.headers.get("access-control-allow-origin")).toBeNull();
    expect(response.headers.get("vary")).toBeNull();
    expect(response.headers.get("cross-origin-resource-policy")).toBe("same-origin");
  });

  it("allows the trace viewer to read a zip", async () => {
    const response = await exports.default.fetch(url(`${artifacts}/trace.zip`), {
      headers: { Origin: "https://trace.playwright.dev" },
    });
    expect(response.status).toBe(200);
    expect(response.headers.get("access-control-allow-origin")).toBe("https://trace.playwright.dev");
    expect(response.headers.get("vary")).toBe("Origin");
    expect(response.headers.get("cross-origin-resource-policy")).toBe("cross-origin");
  });
});

describe("paths that never reach R2", () => {
  const ok = `/vanixiets/browser-evidence/ttl-30d/v1/${OBS}`;
  it.each([
    ["root", "/"],
    ["unknown project", `/elsewhere/browser-evidence/ttl-30d/v1/${OBS}/receipt.json`],
    ["known project, unknown kind", `/vanixiets/other-kind/ttl-30d/v1/${OBS}/receipt.json`],
    ["pair not in the table", `/browser-evidence/vanixiets/ttl-30d/v1/${OBS}/receipt.json`],
    ["full key as path", `/projects/vanixiets/browser-evidence/ttl-30d/v1/${OBS}/receipt.json`],
    ["unknown tier", `/vanixiets/browser-evidence/ttl-7d/v1/${OBS}/receipt.json`],
    ["other version", `/vanixiets/browser-evidence/ttl-30d/v2/${OBS}/receipt.json`],
    ["unknown version", `/vanixiets/browser-evidence/ttl-30d/v3/${OBS}/receipt.json`],
    ["uppercase version", `/vanixiets/browser-evidence/ttl-30d/V1/${OBS}/receipt.json`],
    ["missing version", `/vanixiets/browser-evidence/ttl-30d/${OBS}/receipt.json`],
    ["publisher pr marker", "/vanixiets/browser-evidence/ttl-30d/pr/3300.json"],
    ["uppercase obs", `/vanixiets/browser-evidence/ttl-30d/v1/${OBS.toUpperCase()}/receipt.json`],
    ["short obs", `/vanixiets/browser-evidence/ttl-30d/v1/${OBS.slice(1)}/receipt.json`],
    ["long obs", `/vanixiets/browser-evidence/ttl-30d/v1/${OBS}0/receipt.json`],
    ["obs directory listing", `${ok}/`],
    ["obs without file", ok],
    ["tier listing", "/vanixiets/browser-evidence/ttl-30d/"],
    ["empty inner segment", `${ok}//receipt.json`],
    ["empty segment in a subdirectory", `${ok}/a//b.png`],
    ["subdirectory listing", `${ok}/screenshots/`],
    ["percent-encoded slash", `${ok}/a%2Fb.png`],
    ["percent-encoded traversal", `${ok}/%2e%2e%2fsecret.png`],
    ["percent-encoded dot segment", `${ok}/%2e%2e/receipt.json`],
    ["double dot inside a segment", `${ok}/a..b.png`],
    ["other extension", `${ok}/page.html`],
    ["uppercase extension", `${ok}/home.PNG`],
    ["no extension", `${ok}/receipt`],
    ["bare extension", `${ok}/.png`],
    ["svg", `${ok}/image.svg`],
    ["non-ascii segment", `${ok}/é.png`],
    ["space", `${ok}/a b.png`],
  ])("%s → 404", async (_name, path) => {
    for (const method of ["GET", "HEAD"]) {
      const { store, calls } = recordingStore();
      const response = await handle(new Request(url(path), { method }), store);
      expect(calls).toEqual([]);
      expect(response.status).toBe(404);
      expect(response.headers.get("cache-control")).toBe("no-store");
      for (const [name, value] of Object.entries(SECURITY)) expect(response.headers.get(name)).toBe(value);
    }
  });

  it("serves stored html at no URL, through the deployed handler", async () => {
    const response = await exports.default.fetch(url(`/vanixiets/browser-evidence/ttl-30d/v1/${OBS}/page.html`));
    expect(response.status).toBe(404);
    expect(await response.text()).toBe("Not Found\n");
  });
});

describe("methods", () => {
  it.each(["POST", "PUT", "DELETE", "PATCH", "OPTIONS"])("%s → 405 with Allow", async (method) => {
    const { store, calls } = recordingStore();
    const response = await handle(
      new Request(url(`/vanixiets/browser-evidence/ttl-30d/v1/${OBS}/receipt.json`), { method }),
      store,
    );
    expect(calls).toEqual([]);
    expect(response.status).toBe(405);
    expect(headersOf(response)).toEqual({
      ...SECURITY,
      allow: "GET, HEAD",
      "cache-control": "no-store",
      "content-type": "text/plain; charset=utf-8",
    });
  });

  it("leaves the object in place after a DELETE through the Worker", async () => {
    const response = await exports.default.fetch(url(`/vanixiets/browser-evidence/ttl-30d/v1/${OBS}/receipt.json`), {
      method: "DELETE",
    });
    expect(response.status).toBe(405);
    expect(await env.EVIDENCE.head(`${PREFIX}/receipt.json`)).not.toBeNull();
  });
});

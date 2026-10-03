// Read-only view of evidence objects in the sciexp R2 bucket.
//
// The URL path is the R2 key with its leading `projects/` removed:
// `/<project>/<kind>/<tier>/v1/<obs>/<path>` serves
// `projects/<project>/<kind>/<tier>/v1/<obs>/<path>`. Only GET and HEAD
// of a path that parses to a key under a registered collection ever reach R2;
// everything else is answered without touching the bucket, and nothing lists.

/** Registered (project, kind) collections; onboarding one adds one entry. */
const COLLECTIONS = [{ project: "vanixiets", kind: "browser-evidence" }] as const;
export type Collection = (typeof COLLECTIONS)[number];

/** Retention tiers; each is a lifecycle-rule prefix in the bucket. */
const TIERS = ["ttl-30d", "ttl-90d", "ttl-365d"] as const;
export type Tier = (typeof TIERS)[number];

export type ContentType =
  | "image/png"
  | "application/json"
  | "video/webm"
  | "application/zip"
  | "text/plain; charset=utf-8";

export type Disposition = "inline" | "attachment";

/**
 * Who may read a response cross-origin. `trace-viewer` exists so the hosted
 * Playwright trace viewer can fetch a trace; every other file stays same-origin.
 */
export type Exposure = "same-origin" | "trace-viewer";

/**
 * The document policy a file is served under. `sandboxed` gives an opaque
 * origin and blocks every fetch. `media` exists because the browser's own
 * media document for a directly opened video must fetch that same video:
 * under `sandbox` the opaque origin turns that fetch cross-origin, and
 * `same-origin` resource policy then blocks it. A `video/webm` response with
 * `nosniff` is never interpreted as a document that can run script.
 */
export type DocumentPolicy = "sandboxed" | "media";

export interface FileType {
  readonly contentType: ContentType;
  readonly disposition: Disposition;
  readonly exposure: Exposure;
  readonly policy: DocumentPolicy;
}

/** The only servable extensions; the content type never comes from metadata. */
const FILE_TYPES: Readonly<Record<string, FileType>> = {
  ".png": { contentType: "image/png", disposition: "inline", exposure: "same-origin", policy: "sandboxed" },
  ".json": { contentType: "application/json", disposition: "inline", exposure: "same-origin", policy: "sandboxed" },
  ".webm": { contentType: "video/webm", disposition: "inline", exposure: "same-origin", policy: "media" },
  ".md": {
    contentType: "text/plain; charset=utf-8",
    disposition: "inline",
    exposure: "same-origin",
    policy: "sandboxed",
  },
  ".zip": { contentType: "application/zip", disposition: "attachment", exposure: "trace-viewer", policy: "sandboxed" },
};

const OBS = /^[0-9a-f]{32}$/;
const SEGMENT = /^[A-Za-z0-9._-]+$/;

declare const evidenceKeyBrand: unique symbol;
/** An R2 key under a registered collection; only `parseRoute` builds one. */
export type EvidenceKey = string & { readonly [evidenceKeyBrand]: true };

export type Route =
  | { readonly kind: "object"; readonly key: EvidenceKey; readonly fileType: FileType }
  | { readonly kind: "not-found" };

type ObjectRoute = Extract<Route, { readonly kind: "object" }>;

const NOT_FOUND: Route = { kind: "not-found" };

/**
 * Maps a URL pathname to the object it names. Percent-escapes are never
 * decoded: `%` is outside the segment alphabet, so an encoded `/` or `.`
 * cannot form a separator or a traversal segment.
 */
export function parseRoute(pathname: string): Route {
  if (!pathname.startsWith("/")) return NOT_FOUND;
  const [project, kind, tier, version, obs, ...path] = pathname.slice(1).split("/");

  const collection = COLLECTIONS.find((c) => c.project === project && c.kind === kind);
  if (collection === undefined) return NOT_FOUND;
  const tierName = TIERS.find((t) => t === tier);
  if (tierName === undefined) return NOT_FOUND;
  if (version !== "v1") return NOT_FOUND;
  if (obs === undefined || !OBS.test(obs)) return NOT_FOUND;
  if (!path.every((segment) => SEGMENT.test(segment) && !segment.includes(".."))) {
    return NOT_FOUND;
  }

  const file = path.at(-1);
  if (file === undefined) return NOT_FOUND;
  const dot = file.lastIndexOf(".");
  if (dot <= 0) return NOT_FOUND;
  const extension = file.slice(dot);
  const fileType = Object.hasOwn(FILE_TYPES, extension) ? FILE_TYPES[extension] : undefined;
  if (fileType === undefined) return NOT_FOUND;

  // Every component was validated above against the closed tables and the
  // segment alphabet, which is what an EvidenceKey asserts.
  const key = ["projects", collection.project, collection.kind, tierName, "v1", obs, ...path].join(
    "/",
  ) as EvidenceKey;
  return { kind: "object", key, fileType };
}

/** The slice of R2Bucket the Worker uses. */
export interface EvidenceStore {
  get(key: EvidenceKey, options?: { readonly range: ByteRange }): Promise<R2ObjectBody | null>;
  head(key: EvidenceKey): Promise<R2Object | null>;
}

/** A resolved, satisfiable byte range of an object. */
export interface ByteRange {
  readonly offset: number;
  readonly length: number;
}

export type RangeRequest =
  | { readonly kind: "whole" }
  | { readonly kind: "partial"; readonly range: ByteRange }
  | { readonly kind: "unsatisfiable" };

const WHOLE: RangeRequest = { kind: "whole" };
const SINGLE_RANGE = /^bytes=(\d*)-(\d*)$/;

/**
 * Resolves a `Range` header against an object's size. Only a single
 * `bytes=` range is honoured: video seeking needs one, and RFC 9110 lets a
 * server ignore any other form and send the whole object.
 */
export function resolveRange(header: string | null, size: number): RangeRequest {
  if (header === null) return WHOLE;
  const match = SINGLE_RANGE.exec(header.trim());
  if (match === null) return WHOLE;
  const [, first = "", last = ""] = match;
  const start = first === "" ? undefined : Number(first);
  const end = last === "" ? undefined : Number(last);
  if (start !== undefined && !Number.isSafeInteger(start)) return WHOLE;
  if (end !== undefined && !Number.isSafeInteger(end)) return WHOLE;

  if (start === undefined) {
    if (end === undefined) return WHOLE;
    if (end === 0 || size === 0) return { kind: "unsatisfiable" };
    const length = Math.min(end, size);
    return { kind: "partial", range: { offset: size - length, length } };
  }
  if (start >= size) return { kind: "unsatisfiable" };
  const lastByte = end === undefined ? size - 1 : Math.min(end, size - 1);
  if (lastByte < start) return WHOLE;
  return { kind: "partial", range: { offset: start, length: lastByte - start + 1 } };
}

const SECURITY_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
} as const;

const CONTENT_SECURITY_POLICIES = {
  sandboxed: "default-src 'none'; sandbox",
  media: "default-src 'none'; media-src 'self'",
} as const satisfies Record<DocumentPolicy, string>;

/** Cross-origin headers per exposure; errors are always `same-origin`. */
const EXPOSURE_HEADERS = {
  "same-origin": { "Cross-Origin-Resource-Policy": "same-origin" },
  "trace-viewer": {
    "Access-Control-Allow-Origin": "https://trace.playwright.dev",
    Vary: "Origin",
    "Cross-Origin-Resource-Policy": "cross-origin",
  },
} as const satisfies Record<Exposure, Readonly<Record<string, string>>>;

const ALLOW = "GET, HEAD";

function errorResponse(status: 404 | 405, withBody: boolean): Response {
  const headers = new Headers({ ...SECURITY_HEADERS, ...EXPOSURE_HEADERS["same-origin"] });
  headers.set("Content-Security-Policy", CONTENT_SECURITY_POLICIES.sandboxed);
  headers.set("Cache-Control", "no-store");
  headers.set("Content-Type", "text/plain; charset=utf-8");
  if (status === 405) headers.set("Allow", ALLOW);
  const text = status === 404 ? "Not Found\n" : "Method Not Allowed\n";
  return new Response(withBody ? text : null, { status, headers });
}

function objectHeaders(object: R2Object, fileType: FileType): Headers {
  const headers = new Headers({ ...SECURITY_HEADERS, ...EXPOSURE_HEADERS[fileType.exposure] });
  headers.set("Content-Security-Policy", CONTENT_SECURITY_POLICIES[fileType.policy]);
  headers.set("Cache-Control", "public, max-age=86400, immutable");
  headers.set("Content-Type", fileType.contentType);
  headers.set("Content-Disposition", fileType.disposition);
  headers.set("ETag", object.httpEtag);
  headers.set("Accept-Ranges", "bytes");
  headers.set("Content-Length", String(object.size));
  return headers;
}

async function rangeResponse(request: Request, store: EvidenceStore, route: ObjectRoute): Promise<Response> {
  const object = await store.head(route.key);
  if (object === null) return errorResponse(404, true);
  const resolved = resolveRange(request.headers.get("Range"), object.size);
  const headers = objectHeaders(object, route.fileType);
  if (resolved.kind === "unsatisfiable") {
    headers.set("Content-Range", `bytes */${object.size}`);
    headers.set("Content-Length", "0");
    return new Response(null, { status: 416, headers });
  }
  if (resolved.kind === "whole") {
    const body = await store.get(route.key);
    if (body === null) return errorResponse(404, true);
    return new Response(body.body, { status: 200, headers });
  }
  const { offset, length } = resolved.range;
  const body = await store.get(route.key, { range: resolved.range });
  if (body === null) return errorResponse(404, true);
  headers.set("Content-Range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
  headers.set("Content-Length", String(length));
  return new Response(body.body, { status: 206, headers });
}

export async function handle(request: Request, store: EvidenceStore): Promise<Response> {
  const method = request.method;
  if (method !== "GET" && method !== "HEAD") return errorResponse(405, true);
  const isGet = method === "GET";

  const route = parseRoute(new URL(request.url).pathname);
  if (route.kind === "not-found") return errorResponse(404, isGet);

  if (isGet) {
    if (request.headers.has("Range")) return rangeResponse(request, store, route);
    const object = await store.get(route.key);
    if (object === null) return errorResponse(404, true);
    return new Response(object.body, { status: 200, headers: objectHeaders(object, route.fileType) });
  }

  const object = await store.head(route.key);
  if (object === null) return errorResponse(404, false);
  return new Response(null, { status: 200, headers: objectHeaders(object, route.fileType) });
}

export default {
  async fetch(request, env) {
    return handle(request, env.EVIDENCE);
  },
} satisfies ExportedHandler<Env>;

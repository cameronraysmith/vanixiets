// Read-only view of evidence objects in the sciexp R2 bucket.
//
// The URL path is the R2 key with its leading `projects/` removed:
// `/<project>/<kind>/<tier>/v1/<obs>/<path>` serves
// `projects/<project>/<kind>/<tier>/v1/<obs>/<path>`. Only GET and HEAD of a
// path that parses to a key under a registered collection ever reach R2;
// everything else is answered without touching the bucket, and nothing lists.

/** Registered (project, kind) collections; onboarding one adds one entry. */
const COLLECTIONS = [{ project: "vanixiets", kind: "browser-evidence" }] as const;
export type Collection = (typeof COLLECTIONS)[number];

/** Retention tiers; each is a lifecycle-rule prefix in the bucket. */
const TIERS = ["ttl-30d", "ttl-90d", "ttl-365d"] as const;
export type Tier = (typeof TIERS)[number];

export type ContentType = "image/png" | "application/json";

/** The only servable extensions; the content type never comes from metadata. */
const CONTENT_TYPES: Readonly<Record<string, ContentType>> = {
  ".png": "image/png",
  ".json": "application/json",
};

const OBS = /^[0-9a-f]{32}$/;
const SEGMENT = /^[A-Za-z0-9._-]+$/;

declare const evidenceKeyBrand: unique symbol;
/** An R2 key under a registered collection; only `parseRoute` builds one. */
export type EvidenceKey = string & { readonly [evidenceKeyBrand]: true };

export type Route =
  | { readonly kind: "object"; readonly key: EvidenceKey; readonly contentType: ContentType }
  | { readonly kind: "not-found" };

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
  const contentType = Object.hasOwn(CONTENT_TYPES, extension) ? CONTENT_TYPES[extension] : undefined;
  if (contentType === undefined) return NOT_FOUND;

  // Every component was validated above against the closed tables and the
  // segment alphabet, which is what an EvidenceKey asserts.
  const key = ["projects", collection.project, collection.kind, tierName, "v1", obs, ...path].join(
    "/",
  ) as EvidenceKey;
  return { kind: "object", key, contentType };
}

/** The slice of R2Bucket the Worker uses. */
export interface EvidenceStore {
  get(key: EvidenceKey): Promise<R2ObjectBody | null>;
  head(key: EvidenceKey): Promise<R2Object | null>;
}

const SECURITY_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "Content-Security-Policy": "default-src 'none'; sandbox",
  "Referrer-Policy": "no-referrer",
  "Cross-Origin-Resource-Policy": "same-origin",
} as const;

const ALLOW = "GET, HEAD";

function errorResponse(status: 404 | 405, withBody: boolean): Response {
  const headers = new Headers(SECURITY_HEADERS);
  headers.set("Cache-Control", "no-store");
  headers.set("Content-Type", "text/plain; charset=utf-8");
  if (status === 405) headers.set("Allow", ALLOW);
  const text = status === 404 ? "Not Found\n" : "Method Not Allowed\n";
  return new Response(withBody ? text : null, { status, headers });
}

function objectHeaders(object: R2Object, contentType: ContentType): Headers {
  const headers = new Headers(SECURITY_HEADERS);
  headers.set("Cache-Control", "public, max-age=86400, immutable");
  headers.set("Content-Type", contentType);
  headers.set("Content-Disposition", "inline");
  headers.set("ETag", object.httpEtag);
  headers.set("Content-Length", String(object.size));
  return headers;
}

export async function handle(request: Request, store: EvidenceStore): Promise<Response> {
  const method = request.method;
  if (method !== "GET" && method !== "HEAD") return errorResponse(405, true);
  const isGet = method === "GET";

  const route = parseRoute(new URL(request.url).pathname);
  if (route.kind === "not-found") return errorResponse(404, isGet);

  if (isGet) {
    const object = await store.get(route.key);
    if (object === null) return errorResponse(404, true);
    return new Response(object.body, { status: 200, headers: objectHeaders(object, route.contentType) });
  }

  const object = await store.head(route.key);
  if (object === null) return errorResponse(404, false);
  return new Response(null, { status: 200, headers: objectHeaders(object, route.contentType) });
}

export default {
  async fetch(request, env) {
    return handle(request, env.EVIDENCE);
  },
} satisfies ExportedHandler<Env>;

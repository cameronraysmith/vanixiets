# cognee on Modal: serverless deployment design

Status: design locked 2026-05-30 (WO session `cognee-modal-vanixiets-deploy`); revised after spec self-review and after the Phase-0 auth + postgres_graph probes.
Target architecture: C — cognee serving on Modal, state on Neon, per-host local stdio MCP.
This note is the assessment-and-design artifact that feeds the implementation plan; it does not itself implement anything.

## Goal

Replace an always-on, clan-managed Hetzner deployment of cognee with a production-grade serverless deployment that optimizes cost, availability, and scalability.
cognee is the semantic-recall "super-memory" consumed by the `ouroboros-loop` skill and, prospectively, by the wider agent fleet (Claude Code, codex, opencode across stibnite/blackphos/argentum/rosegold).
cognee is *not* the authoritative store of record for the ouroboros loop; that remains a separate append-only SQLite event ledger.
cognee is purely the deduplicating semantic mirror, exercised through the `remember`/`recall`/`forget` trio.

## Established constraints

These facts were verified read-only against local clones and are the load-bearing constraints that force the design.
Sources: `~/projects/planning-workspace/cognee` (fork `cameronraysmith/cognee`), `~/projects/planning-workspace/cognee-nix`, `~/projects/sciops-workspace/modal-client`, `~/projects/sciops-workspace/modal-examples`, `~/projects/sciops-workspace/terraform-provider-neon`. Code facts are anchored at the `v1.1.0` tag (what cognee-nix builds).

Modal hosts stateless compute, not live databases.
Its `Volume` is a commit/reload snapshot store with last-write-wins semantics and no file locking (`modal-client/py/modal/volume.py:357-397`), and `NetworkFileSystem` is deprecated.
Modal's own examples externalize databases to managed services reached via a connection string in a `Secret` (`modal-examples/misc/vector_similarity_search.py:67` uses Neon).
Therefore cognee's backing stores cannot live on Modal; they must be an external managed Postgres.

The Modal serving knobs the design relies on are verified in the SDK: `@modal.asgi_app` and `@modal.concurrent` (exported in `modal-client/py/modal/__init__.py:86,89`), `requires_proxy_auth` (`_partial_function.py:344`, Modal-Key/Modal-Secret enforced at the edge), `min_containers`/`scaledown_window` (`_functions.py:660`), and for nix-driven deploy `Secret.objects.create(name, contents, allow_existing=True)` (`secret.py:46-70`; `contents` is the positional env-dict) plus `App.deploy()` (`app.py:431`).

cognee's three stores collapse into one Postgres, and the graph layer needs no special database.
The relational store uses `postgres`, the vector store uses `pgvector`, and the graph store uses cognee's `postgres` provider.
That graph provider is *not* a Postgres graph extension (not Apache AGE or pgRouting) — it is cognee's own adapter (`graph/postgres/adapter.py`, `class PostgresAdapter(GraphDBInterface)`) over two ordinary tables, `graph_node` and `graph_edge` with JSONB property columns (`graph/postgres/tables.py`), using only standard SQL (JSONB, `ON CONFLICT` upserts, JOINs, `WITH RECURSIVE` CTEs for k-hop traversal).
It runs no `CREATE EXTENSION` and needs no superuser — only `CREATE TABLE/INDEX` within an ordinary role.
The single `CREATE EXTENSION vector` belongs to the vector store (`vector/pgvector/create_db_and_tables.py:17`), which Neon supports for non-superuser roles.
So one pgvector-enabled Postgres serves all three stores; `USE_UNIFIED_PROVIDER=pghybrid` points the graph adapter at the relational DSN, the intended one-Postgres topology.
The zero-config defaults are otherwise file-based (relational `sqlite`, vector `lancedb`, graph `ladybug` — `graph/config.py:45`; kuzu is an alternative graph provider, not the default), which the cognee deploy README flags as unfit for concurrent containerized writes — hence the Postgres requirement for any serverless deployment.

cognee ships an official Modal deployment for the core API.
`distributed/deploy/modal_app.py` exposes `cognee.api.client:app` (FastAPI) through a single `@modal.asgi_app()`, with a `cognee-secrets` Secret group and a Volume for the file-based fallback.
Our deployment follows this as a template but points `DB_PROVIDER=postgres` / `VECTOR_DB_PROVIDER=pgvector` / `GRAPH_DATABASE_PROVIDER=postgres` (or `USE_UNIFIED_PROVIDER=pghybrid`) at Neon instead of the Volume.
A separate `distributed/` tree is a Modal Queue fan-out batch pipeline for heavy ingestion; it is distinct from the API server and is a later-phase lever, not v1.

The MCP server is a stateless HTTP client in API mode.
`cognee-mcp` (entry `cognee-mcp/src/server.py`) registers eleven `@mcp.tool` functions; the consumer uses only `remember`/`recall`/`forget`.
With `--api-url`/`--api-token` set, `CogneeClient` becomes an `httpx` client and every trio method routes to the remote FastAPI; the direct-cognee branch is gated behind `if not self.use_api` (`cognee_client.py:453-560`), and startup migrations are skipped.
All three trio routes are guarded by `Depends(get_authenticated_user)` (verified at v1.1.0: `get_add_router.py:46`, `get_search_router.py:106`, the delete router) — including the write path — so the deployment must provision a cognee user and a token that each host's MCP presents via `--api-token`.
For a self-hosted (non-`tenant-*.cognee.ai`) `--api-url`, `CogneeClient` sends the token as `Authorization: Bearer` only (`cognee_client.py:79-84`), never `X-Api-Key`; this constrains the token type (see Phase-0 Gate 3).

Upstream cognee `v1.1.0` already satisfies the trio + API-mode contract.
The `v1.1.0` tag that cognee-nix fetches is a genuine upstream tag, and at that tag `cognee-mcp/src/server.py` is byte-identical to the fork (a 0-line diff on fork `main`).
The fork's only MCP delta vs v1.1.0 is a ~29-line session-mode routing change in `cognee-mcp/src/cognee_client.py`'s API-mode `remember` branch (routing `session_id` writes to `/api/v1/remember/entry`); it matters *only* when `session_id` is passed.
The ouroboros consumer calls `remember(data)` without `session_id`, so a fork switch is optional, not required (pin the fork by changing `owner`/`rev`/`hash` in `packages/cognee/default.nix` and `packages/cognee-mcp/default.nix` only if a fork patch is wanted — see Gate 3).

Neon is provisionable declaratively via terranix.
The provider is `kislerdm/neon` (Terraform registry source `kislerdm/neon`); the local fork is `~/projects/sciops-workspace/terraform-provider-neon` (`cameronraysmith/terraform-provider-neon`).
It exposes `neon_project`, `neon_branch`, `neon_endpoint`, `neon_role`, `neon_database`, and `neon_api_key`.
The `neon_project` resource yields a `connection_uri` attribute (plus `database_user` and `default_branch_id` — `resource_project.go:198,187,167`), and `neon_role.password` is a sensitive output (`resource_role.go:44-48`), so `modules/terranix/neon.nix` can emit the connection string straight into the Modal `cognee-modal` Secret.
Use Neon's **direct** (non-pooled) endpoint in the connection string: cognee connects via `postgresql+asyncpg://`, and asyncpg's default prepared statements are unsupported on Neon's pooled endpoint.
The provider does not manage Postgres extensions, so `pgvector` is enabled out-of-band — see the Phase-0 gates.
vanixiets already drives terranix providers via `modules/terranix/{base,hetzner,gcp,cloudflare}.nix`, so a sibling `modules/terranix/neon.nix` fits the established pattern.
Canonical provider reference: https://neon.com/docs/reference/terraform.md; Neon pgvector: https://neon.com/docs/extensions/pgvector.md.

## Architecture C

Data flow: an agent on any host invokes a trio tool through a per-host *local stdio* `cognee-mcp` running in API mode, which proxies over HTTPS to the cognee FastAPI on Modal, which reads and writes a single pgvector-enabled Postgres on Neon, with LLM and embedding calls going out to OpenAI.
The MCP protocol session stays local per agent (clean isolation, no shared-session contention); only the semantic-memory operations cross the network.

Component to substrate mapping:

| Component | Substrate | Form | Notes |
|---|---|---|---|
| cognee core FastAPI API | Modal | `@modal.asgi_app()`, scale-to-zero | templated on `distributed/deploy/modal_app.py`, DB points at Neon |
| cognify / embedding | Modal | inline in API container for v1; Modal Queue fan-out + optional GPU later | OpenAI embeddings for v1 (no GPU) |
| cognee-mcp | per-host local | stdio, API mode (`--api-url`, `--api-token`) | from the cognee-nix package; not on Modal in v1 |
| relational + vector + graph store | Neon | one pgvector Postgres (`pghybrid`: postgres + pgvector + postgres-graph) | provisioned via terranix, direct endpoint |
| frontend (Next.js UI) | out of scope (v1) | — | the trio does not need it |

Authentication has two layers, both enabled from P1.
The Modal endpoint carries `requires_proxy_auth=True` (Modal-Key / Modal-Secret enforced at Modal's edge) so the public URL is closed to unauthenticated callers.
Inside the app, a cognee user plus long-lived Bearer JWT (delivered per-host via sops-nix home-manager) authorizes the trio; the concrete provisioning recipe is Gate 3.

Availability and cost: the API runs scale-to-zero by default (`min_containers=0`); set `min_containers=1` + a `scaledown_window` only if recall latency demands it, trading warm-pool cost for cold-start elimination.
`@modal.concurrent` packs multiple in-flight requests per container.
Neon's compute endpoint autoscales and scales to zero independently, so the idle-cost floor of the whole system is near zero.

nix drives Modal: cognee-nix gains a flake-parts module (e.g. `dev/modal/flake-module.nix`) exposing a flake app `apps.deploy-cognee-modal` — a devshell carrying `modal-client` + a thin `dev/modal/modal_app.py` — that (1) upserts sops-decrypted secrets via `Secret.objects.create("cognee-modal", contents, allow_existing=True)`, then (2) calls `App.deploy()`.
The thin `modal_app.py` follows cognee's `distributed/deploy/modal_app.py` as its template but sets the Neon DSN + `pghybrid`/provider env (via the `cognee-modal` Secret) in place of the upstream Volume-backed file DBs; it does not vendor a modified copy of the upstream file.
The container image is Modal-built (`debian_slim().uv_pip_install`) for v1 simplicity; P3 replaces it with a nix `dockerTools` OCI image pushed to a registry and pulled via `Image.from_registry` for hermeticity.

Consumer wiring in vanixiets: add the `cognee-mcp` package to the relevant hosts and register a `cognee` stdio MCP server in `modules/home/ai/claude-code/mcp-servers.nix` whose command is `cognee-mcp --transport stdio --api-url <modal-url> --api-token <sops>`.
The ouroboros `SKILL.md` uses `cognee` as a non-binding placeholder server name (it explicitly notes the `mcp__<server>__*` segment depends on how the MCP server is registered), so register the vanixiets server as `cognee` to make the existing `mcp__cognee__remember/recall/forget` allowlist entries resolve; vanixiets owns the canonical name.

Secret delivery splits cleanly by consumer.
The per-host MCP Bearer JWT is consumed by `cognee-mcp` inside each agent's Claude Code (home-manager context on the nix-darwin laptops), so it is a **sops-nix home-manager** secret — the same pattern as the existing bearer-token MCP servers in `mcp-servers.nix`.
The Modal-side secrets (LLM/embedding API key, the Neon `connection_uri`, `FASTAPI_USERS_JWT_SECRET`, `DEFAULT_USER_EMAIL`/`DEFAULT_USER_PASSWORD`) are consumed by the deploy flake app at deploy time, so they live in the **vanixiets `secrets/`** sops tree and are pushed to the Modal `cognee-modal` Secret by the deploy app.
Clan-managed vars do not apply: Modal is not a clan machine, and the MCP token is a home-manager user secret, not a machine-provisioned system one.

## Knowledge architecture (datasets)

The deployment is single-tenant with multiple named datasets, not multi-user-tenant.
Initial durable, shared knowledge bases: `handbook` (company handbook knowledgebase), `sci-modeling` (scientific modeling), and `eng-practices` (engineering practices); project-specific datasets are added over time.
These are distinct from the ouroboros loop's ephemeral per-mission datasets (`ooo-<mission_id>`), which the loop creates and prunes on its own cadence.
Agents and skills select the target dataset per `remember`/`recall` call (`dataset_name=` on write, `datasets=` on read), so dataset choice is a call-site concern, not a deployment toggle.
Single-tenant means `ENABLE_BACKEND_ACCESS_CONTROL` may be left at its default with one provisioned user owning all datasets; per-user tenancy is a later option if the fleet needs isolation rather than shared knowledge.

## Unified cognee-nix module surface

The systematization is a single composable module surface whose toggles span the whole spectrum, so the same code expresses the recommended C target and the alternatives:

- `services.cognee.serving.target = magnetite | modal`
- `services.cognee.storage.backend = neon | magnetite`
- `services.cognee.cognify.runner = local | modal`
- a vanixiets consumer module registering a per-host stdio `cognee-mcp` against the chosen API URL with a sops Bearer token

These toggles EXTEND, rather than replace, the existing `services.cognee` option tree in cognee-nix, which today exposes `database.{createLocally,enablePgvector,host,port,name,user}`, `vectorStore.backend` (pgvector|lancedb|qdrant), `graphStore.backend` (ladybug|neo4j), `llm.*`, `auth.*`, `mcp.*`, and on-host `listenAddress`/`port`/`workers`.
Mapping: `storage.backend=neon` sets `database.createLocally=false` + `vectorStore.backend=pgvector` + `graphStore.backend=postgres` and feeds an external Neon connection string via a new option (e.g. `database.connectionStringFile`); `serving.target` and `cognify.runner` are NEW top-level switches the current module lacks (it only serves on-host plus an `mcp` submodule), and `serving.target=modal` bypasses the on-host systemd unit in favor of the Modal flake app.
Existing option names are retained; the new switches sit above them, and the current consumers (the nixosTests/eval fixtures referencing `services.cognee`) keep working under the default on-host path.

The three coherent targets:
A (`serving=magnetite, storage=magnetite, cognify=local`) runs the entire stack on magnetite over the ZeroTier admin mesh with no public exposure — the lowest-ceremony, fully self-sovereign baseline.
B (`serving=magnetite, storage=magnetite, cognify=modal`) keeps serving and state co-located on magnetite while offloading the bursty/GPU cognify pipeline to Modal, which reaches magnetite Postgres via a Modal Proxy static IP.
C (`serving=modal, storage=neon, cognify=modal`) is the locked target: fully off-Hetzner, best availability and scalability and isolation, at the cost of state living on Neon and recall paying occasional cold starts.

The first build is C with `serving=modal, storage=neon`; the magnetite paths remain in the module as toggles but are not exercised in v1.

## Phase 0 verification gates

Gate 1 — postgres_graph serves `GRAPH_COMPLETION`: PASSED by code inspection, confirmed empirically by the smoke test.
cognee's postgres graph adapter is native over plain `graph_node`/`graph_edge` tables (no extension); the `GRAPH_COMPLETION` retriever calls `get_nodeset_subgraph`/`get_graph_data`/`get_filtered_graph_data`/`get_neighborhood`/`is_empty`, all implemented in the adapter (only the raw-Cypher `CYPHER`/`NATURAL_LANGUAGE` search types are unsupported, and neither is used).
The empirical check: ingest a small fixture via `cognee.add` + `cognify` against a Neon-backed store, then `cognee.search` with `search_type=GRAPH_COMPLETION`; pass if it returns a non-empty result without erroring.
No Neo4j fallback is needed.
Performance note: the postgres adapter lacks `get_id_filtered_graph_data`, so non-neighborhood `GRAPH_COMPLETION` projects the whole graph and filters in Python; set `neighborhood_depth` to use the bounded recursive-CTE path as graphs grow.

Gate 2 — Neon pgvector + cognee schema init + trio smoke test.
Because cognee skips startup migrations in API mode, `CREATE EXTENSION vector` cannot rely on cognee's init; enable it as an explicit provisioning step (a terranix `null_resource`/`local-exec` running `psql` against the Neon branch, or a one-shot Modal function) before first API use.
Use Neon's direct (non-pooled) endpoint in the DSN (asyncpg prepared statements).
Then run a trio smoke test (`remember` a fact, `recall` it, `forget` it) against the Modal API through an *ad-hoc* local stdio MCP invocation; this precedes any durable per-host registration.

Gate 3 — auth path: RESOLVED (config-only for P1).
cognee auto-creates a default superuser from `DEFAULT_USER_EMAIL`/`DEFAULT_USER_PASSWORD` (default `default_user@example.com`/`default_password`) lazily on first authenticated request; `ENABLE_BACKEND_ACCESS_CONTROL` (default true) forces auth on.
Recipe: pin `DEFAULT_USER_EMAIL`/`DEFAULT_USER_PASSWORD`, a stable `FASTAPI_USERS_JWT_SECRET`, and a large `JWT_LIFETIME_SECONDS` (e.g. `315360000` ≈ 10y) in the Modal `cognee-modal` Secret; mint the token via `POST /api/v1/auth/login` (OAuth2 password *form*: `username`/`password`) and read `.access_token`; the MCP presents it via `--api-token`, sent as `Authorization: Bearer`.
Wrinkle: cognee's static, individually-revocable API keys (`POST /api/v1/auth/api-keys` → `X-Api-Key`, no expiry) are the cleaner fleet credential, but the self-hosted `CogneeClient` sends `--api-token` as `Authorization: Bearer` (it only uses `X-Api-Key` for `tenant-*.cognee.ai` cloud URLs), so the API key is unreachable without a ~10-line fork patch to `cognee_client.py`.
Decision: P1 uses the long-lived JWT (no fork patch); a fork patch enabling per-host revocable `X-Api-Key` credentials is a documented P2/P3 upgrade if fleet-wide independent revocation becomes worth the fork maintenance.
Residual: a long-lived JWT couples to the shared `FASTAPI_USERS_JWT_SECRET` — revoking one host means rotating the secret, which invalidates all tokens.

## Phasing

P1 establishes the spine: provision Neon via terranix (direct endpoint, `CREATE EXTENSION vector`), deploy the cognee API on Modal (with `requires_proxy_auth` enabled, `pghybrid` at Neon) pointed at Neon, provision the user and long-lived JWT (Gate 3), pass Gates 1-2 with a trio smoke test via an ad-hoc local stdio MCP, then commit the first durable per-host stdio MCP registration and seed the `handbook`/`sci-modeling`/`eng-practices` datasets.

P2 committed: move cognify to Modal as scheduled/on-demand functions.
P2 conditional: add a GPU embedding function only when embedding volume justifies it (trigger: embedding latency dominates ingestion wall-clock, or batch size exceeds a few hundred docs/run); add a remote MCP-on-Modal app only if a non-local consumer appears; add the fork patch for revocable `X-Api-Key` credentials if fleet-wide independent revocation is wanted.

P3 committed: replace the Modal-built image with a hermetic nix `dockerTools` image pulled via `Image.from_registry`.
P3 conditional: add OTel export to the SigNoz instance on magnetite, and surface the magnetite/hybrid toggles (A/B) once a second target is actually wanted.

## Decision record

Target C over A/B: storage location is the architecture pivot, and the user chose full-serverless off-Hetzner.
magnetite's existing Postgres is a shared, socket-only, no-pgvector instance backing Gitea/niks3/Matrix, so the magnetite-storage paths (A/B) require exposing a dedicated cognee DB on the public interface and adding pgvector — net-new surface on a security-sensitive box.
Neon removes that surface entirely (managed TLS endpoint, connection string in a Secret) and gives true end-to-end scale-to-zero, at the cost of state residing on Neon.

MCP placement: per-host local stdio over a remote MCP-on-Modal.
API mode makes the local MCP a thin stateless proxy, so N users each run their own local stdio MCP against one shared remote brain; no remote MCP is required.
This yields the simplest auth, isolated per-agent MCP sessions, and sidesteps Modal's stateless-MCP constraint and 5s first-message timeout.

Auth credential: long-lived JWT for P1 (config-only, aligns with the lean against fork patches), with the static-`X-Api-Key`-via-fork-patch as a documented upgrade for per-host revocability.

Graph store: cognee's native postgres adapter, not Neo4j — `GRAPH_COMPLETION` is served over plain tables, so one Neon Postgres holds all three stores and no managed graph DB is needed.

Build path: nix-driven via cognee-nix; Modal supports programmatic deploy (`App.deploy()`) and Secret upsert (`Secret.objects.create(..., allow_existing=True)`), so the whole deployment is a flake app that consumes sops secrets.

## Implementation surface (cross-repo)

The work spans two repositories with different VCS modes, which is the one axis of genuine parallelism (different working copies):

cognee-nix (`~/projects/planning-workspace/cognee-nix`, git-native): the `dev/modal/flake-module.nix` exposing `apps.deploy-cognee-modal`, the thin `dev/modal/modal_app.py`, the Modal Secret sync, the unified `services.cognee` toggle surface (extending the existing option tree), and the optional fork pin / API-key patch / hermetic image work.
vanixiets (jj diamond): `modules/terranix/neon.nix` for Neon provisioning (incl. the `CREATE EXTENSION vector` step), the consumer `cognee` stdio MCP registration in `modules/home/ai/claude-code/mcp-servers.nix`, and the secrets (per-host MCP JWT via sops-nix home-manager; Modal-side secrets in `secrets/`).

Per the orchestration decision for this session, vanixiets edits are serialized through the diamond development join (append-route to the `cognee-modal-deploy` chain); independent cognee-nix edits may proceed in parallel because they touch a separate working copy.

## Open questions and risks

Auth residual: the long-lived JWT couples to the shared `FASTAPI_USERS_JWT_SECRET`; if per-host independent revocation matters, take the `X-Api-Key` fork patch (P2).
Graph projection performance: the postgres adapter's whole-graph projection on non-neighborhood `GRAPH_COMPLETION` is fine for small/medium graphs; use `neighborhood_depth` at scale.
Neon: free-tier compute/storage limits and Neon-compute cold-start latency should be measured against real ouroboros recall cadence; ensure the DSN uses the direct (non-pooled) endpoint for asyncpg.
Modal cold-start latency on recall is acceptable for asynchronous reflection but should be re-evaluated if recall moves onto a latency-critical path; `min_containers=1` is the lever.
Dataset growth: as `handbook`/`sci-modeling`/`eng-practices` and project datasets accumulate, revisit whether single-tenant-multi-dataset still suffices or per-user tenancy is wanted.

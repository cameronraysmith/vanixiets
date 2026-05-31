# cognee on Modal: serverless deployment design

Status: design locked 2026-05-30 (WO session `cognee-modal-vanixiets-deploy`).
Target architecture: C — cognee serving on Modal, state on Neon, per-host local stdio MCP.
This note is the assessment-and-design artifact that feeds the implementation plan; it does not itself implement anything.

## Goal

Replace an always-on, clan-managed Hetzner deployment of cognee with a production-grade serverless deployment that optimizes cost, availability, and scalability.
cognee is the semantic-recall "super-memory" consumed by the `ouroboros-loop` skill and, prospectively, by the wider agent fleet (Claude Code, codex, opencode across stibnite/blackphos/argentum/rosegold).
cognee is *not* the authoritative store of record for the ouroboros loop; that remains a separate append-only SQLite event ledger.
cognee is purely the deduplicating semantic mirror, exercised through the `remember`/`recall`/`forget` trio.

## Established constraints

These facts were verified read-only against local clones and are the load-bearing constraints that force the design.
Sources: `~/projects/planning-workspace/cognee` (fork `cameronraysmith/cognee`), `~/projects/planning-workspace/cognee-nix`, `~/projects/sciops-workspace/modal-client`, `~/projects/sciops-workspace/modal-examples`, `~/projects/sciops-workspace/terraform-provider-neon`.

Modal hosts stateless compute, not live databases.
Its `Volume` is a commit/reload snapshot store with last-write-wins semantics and no file locking (`modal-client/py/modal/volume.py:357-397`), and `NetworkFileSystem` is deprecated.
Modal's own examples externalize databases to managed services reached via a connection string in a `Secret` (`modal-examples/misc/vector_similarity_search.py:67` uses Neon).
Therefore cognee's backing stores cannot live on Modal; they must be an external managed Postgres.

cognee's three stores collapse into one Postgres.
The relational store supports `postgres`, the vector store supports `pgvector`, and the graph store supports a `postgres` provider routed through the `postgres_graph` handler (`cognee/infrastructure/databases/*/config.py` and the engine factories).
So relational + vector + graph can share a single pgvector-enabled Postgres database.
The zero-config defaults are file-based (sqlite + lancedb + kuzu/ladybug), which the cognee deploy README itself flags as unfit for concurrent containerized writes — hence the Postgres requirement for any serverless deployment.

cognee ships an official Modal deployment for the core API.
`distributed/deploy/modal_app.py` exposes `cognee.api.client:app` (FastAPI) through a single `@modal.asgi_app()`, with a `cognee-secrets` Secret group and a Volume for the file-based fallback.
Our deployment extends this but points `DB_PROVIDER=postgres` / `VECTOR_DB_PROVIDER=pgvector` / `GRAPH_DATABASE_PROVIDER=postgres` at Neon instead of the Volume.
A separate `distributed/` tree is a Modal Queue fan-out batch pipeline for heavy ingestion; it is distinct from the API server and is a later-phase lever, not v1.

The MCP server is a stateless HTTP client in API mode.
`cognee-mcp` (entry `cognee-mcp/src/server.py`) registers eleven `@mcp.tool` functions; the consumer uses only `remember`/`recall`/`forget`.
With `--api-url`/`--api-token` set, `CogneeClient` becomes an `httpx` client and every trio method routes to the remote FastAPI (`POST /api/v1/remember`, `POST /api/v1/recall`, `POST /api/v1/forget`); there is no direct-DB fallback inside the trio's API branch, and startup migrations are skipped.
`recall` and `forget` are guarded by `Depends(get_authenticated_user)`, so the deployment must mint a cognee user and a Bearer token that each host's MCP presents via `--api-token`.

Upstream cognee `v1.1.0` already satisfies the trio + API-mode contract.
The `v1.1.0` tag that cognee-nix fetches is a genuine upstream tag, and at that tag `cognee-mcp/src/server.py` is byte-identical to the fork for the trio and the `--api-url`/`--api-token` flags.
The fork's only MCP delta is a 31-line session-mode routing fix in `remember` that matters *only* when `session_id` is passed; the ouroboros consumer calls `remember(data)` without `session_id`, so a fork switch is optional, not required.
Pinning the fork remains available (change `owner`/`rev`/`hash` in `packages/cognee/default.nix` and `packages/cognee-mcp/default.nix`) if future session-scoped writes are wanted.

Neon is provisionable declaratively via terranix.
The provider is `kislerdm/neon` (Terraform registry source `kislerdm/neon`); the local fork is `~/projects/sciops-workspace/terraform-provider-neon` (`cameronraysmith/terraform-provider-neon`).
It exposes `neon_project`, `neon_branch`, `neon_endpoint`, `neon_role`, `neon_database`, and `neon_api_key`.
The `neon_project` resource yields a `connection_uri` attribute (plus `database_user` and `default_branch_id`), and `neon_role.password` is a sensitive output, so `modules/terranix/neon.nix` can emit the connection string straight into the Modal `cognee-modal` Secret.
The provider does not manage Postgres extensions, so `pgvector` is enabled out-of-band (cognee init or an explicit `CREATE EXTENSION vector`) — see the Phase-0 gates.
vanixiets already drives terranix providers via `modules/terranix/{base,hetzner,gcp,cloudflare}.nix`, so a sibling `modules/terranix/neon.nix` fits the established pattern.
Canonical provider reference: https://neon.com/docs/reference/terraform.md.

## Architecture C

Data flow: an agent on any host invokes a trio tool through a per-host *local stdio* `cognee-mcp` running in API mode, which proxies over HTTPS to the cognee FastAPI on Modal, which reads and writes a single pgvector-enabled Postgres on Neon, with LLM and embedding calls going out to OpenAI.
The MCP protocol session stays local per agent (clean isolation, no shared-session contention); only the semantic-memory operations cross the network.

Component to substrate mapping:

| Component | Substrate | Form | Notes |
|---|---|---|---|
| cognee core FastAPI API | Modal | `@modal.asgi_app()`, scale-to-zero | extends `distributed/deploy/modal_app.py`, DB points at Neon |
| cognify / embedding | Modal | inline in API container for v1; Modal Queue fan-out + optional GPU later | OpenAI embeddings for v1 (no GPU) |
| cognee-mcp | per-host local | stdio, API mode (`--api-url`, `--api-token`) | from the cognee-nix package; not on Modal in v1 |
| relational + vector + graph store | Neon | one pgvector Postgres (provider=postgres / pgvector / postgres_graph) | provisioned via terranix |
| frontend (Next.js UI) | out of scope (v1) | — | the trio does not need it |

Authentication: the deploy mints a cognee user and issues a Bearer token, delivered to each host through sops; the Modal endpoint additionally carries `requires_proxy_auth=True` (Modal-Key / Modal-Secret enforced at Modal's edge) so the public URL is not open.

Availability and cost: the API runs scale-to-zero by default (`min_containers=0`); set `min_containers=1` + a `scaledown_window` only if recall latency demands it, trading warm-pool cost for cold-start elimination.
`@modal.concurrent` packs multiple in-flight requests per container.
Neon's compute endpoint autoscales and scales to zero independently, so the idle-cost floor of the whole system is near zero.

nix drives Modal: cognee-nix gains a flake app `apps.deploy-cognee-modal` (a devshell carrying `modal-client` + a thin `modal_app.py`) that (1) upserts sops-decrypted secrets via `Secret.objects.create("cognee-modal", {...}, allow_existing=True)`, then (2) calls `App.deploy()`.
The container image is Modal-built (`debian_slim().uv_pip_install`) for v1 simplicity; a hardening step replaces it with a nix `dockerTools` OCI image pushed to a registry and pulled via `Image.from_registry` for hermeticity.

Consumer wiring in vanixiets: add the `cognee-mcp` package to the relevant hosts and register a `cognee` stdio MCP server in `modules/home/ai/claude-code/mcp-servers.nix` whose command is `cognee-mcp --transport stdio --api-url <modal-url> --api-token <sops>`.
The registered server name must equal the `mcp__cognee__*` allowlist prefix asserted in the ouroboros `SKILL.md`; confirm and align.
The Bearer token is a new sops secret per user identity.

## Unified cognee-nix module surface

The systematization is a single composable module surface whose toggles span the whole spectrum, so the same code expresses the recommended C target and the alternatives:

- `services.cognee.serving.target = magnetite | modal`
- `services.cognee.storage.backend = neon | magnetite`
- `services.cognee.cognify.runner = local | modal`
- a vanixiets consumer module registering a per-host stdio `cognee-mcp` against the chosen API URL with a sops Bearer token

These collapse to three coherent targets.
A (`magnetite, magnetite, local`) runs the entire stack on magnetite over the ZeroTier admin mesh with no public exposure — the lowest-ceremony, fully self-sovereign baseline.
B (`magnetite, magnetite, modal`) keeps serving and state co-located on magnetite while offloading the bursty/GPU cognify pipeline to Modal, which reaches magnetite Postgres via a Modal Proxy static IP.
C (`modal, neon, modal`) is the locked target: fully off-Hetzner, best availability and scalability and isolation, at the cost of state living on Neon and recall paying occasional cold starts.

The first build is C with `serving=modal, storage=neon`; the magnetite paths remain in the module as toggles but are not exercised in v1.

## Phase 0 verification gates

These are blockers; the design rests on them and they are cheap to check before any consumer wiring.

The cognee `postgres` graph provider must support the `GRAPH_COMPLETION` search type the ouroboros `recall` uses.
If `postgres_graph` is too thin for the graph traversal cognee needs, the fallback is a managed Neo4j (e.g. Aura) for the graph store while relational and vector stay on Neon — accepted as a known, scoped fallback.

Neon pgvector plus cognee schema initialization must succeed end-to-end.
Confirm the `vector` extension is available and enabled on the Neon branch (cognee's init path or an explicit `CREATE EXTENSION vector`), then run a trio smoke test (`remember` a fact, `recall` it, `forget` it) against the Modal API through a local stdio MCP before wiring any host.

## Phasing

P1 establishes the spine: provision Neon via terranix, deploy the cognee API on Modal pointed at Neon, mint the user and token, pass the two Phase-0 gates with a trio smoke test, and wire exactly one host's stdio MCP.
P2 moves cognify to Modal (scheduled or on-demand, with an optional GPU embedding function if volume justifies it) and hardens auth (`requires_proxy_auth`, and an optional remote MCP-on-Modal app for non-local consumers).
P3 hardens and generalizes: the hermetic nix `dockerTools` image via a registry, OTel export to the SigNoz instance on magnetite, and surfacing the magnetite/hybrid toggles so the unified module genuinely spans A/B/C.

## Decision record

Target C over A/B: storage location is the architecture pivot, and the user chose full-serverless off-Hetzner.
magnetite's existing Postgres is a shared, socket-only, no-pgvector instance backing Gitea/niks3/Matrix, so the magnetite-storage paths (A/B) require exposing a dedicated cognee DB on the public interface (TLS, allowlisted to a Modal Proxy static IP) and adding pgvector — net-new surface on a security-sensitive box.
Neon removes that surface entirely (managed TLS endpoint, connection string in a Secret) and gives true end-to-end scale-to-zero, at the cost of state residing on Neon.

MCP placement: per-host local stdio over a remote MCP-on-Modal.
API mode makes the local MCP a thin stateless proxy, so N users each run their own local stdio MCP against one shared remote brain; no remote MCP is required.
This yields the simplest auth (one Bearer token per identity via sops), isolated per-agent MCP sessions, and sidesteps Modal's stateless-MCP constraint and 5s first-message timeout.
A remote MCP-on-Modal remains an optional P2 add for consumers that cannot spawn a local process (browser/CI/Modal-resident agents).

Build path: nix-driven via cognee-nix, per the user's directive and the dendritic flake-parts conventions.
Modal supports programmatic deploy (`App.deploy()`) and programmatic Secret upsert (`Secret.objects.create(..., allow_existing=True)`), so the whole deployment is expressible as a flake app that consumes sops secrets.

## Implementation surface (cross-repo)

The work spans two repositories with different VCS modes, which is the one axis of genuine parallelism (different working copies):

cognee-nix (`~/projects/planning-workspace/cognee-nix`, git-native): the `apps.deploy-cognee-modal` flake app, the thin `modal_app.py`, the Modal Secret sync, the unified `services.cognee` toggle surface, and the optional fork pin / hermetic image work.
vanixiets (jj diamond): `modules/terranix/neon.nix` for Neon provisioning, the consumer `cognee` stdio MCP registration in `modules/home/ai/claude-code/mcp-servers.nix`, and the sops secret for the Bearer token.

Per the orchestration decision for this session, vanixiets edits are serialized through the diamond development join (append-route to the `cognee-modal-deploy` chain); independent cognee-nix edits may proceed in parallel because they touch a separate working copy.

## Open questions and risks

postgres_graph adequacy for `GRAPH_COMPLETION` is the principal technical risk (mitigated by the Neo4j fallback).
Neon free-tier compute/storage limits and cold-start latency on the Neon compute endpoint should be measured against real ouroboros recall cadence.
Modal cold-start latency on recall is acceptable for asynchronous reflection but should be re-evaluated if recall moves onto a latency-critical path; `min_containers=1` is the lever.
Multi-tenant scoping (shared knowledge graph vs per-user/per-mission datasets via `ENABLE_BACKEND_ACCESS_CONTROL` and `ooo-<mission_id>` dataset names) is a policy choice deferred to writing-plans.

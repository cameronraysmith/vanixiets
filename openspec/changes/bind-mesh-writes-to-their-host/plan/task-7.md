### Task 7: Documentation

Implements `tasks.md` 7.1–7.3 (design "Spec deltas and decision records"; FII `This capability states its own trust boundary`).
It is pull request 3, after Task 6.

**Files:**
- Modify: `modules/clan/services/otel-collector/README.md`, `packages/docs/src/content/docs/development/operations/fleet-observability.md`, `docs/notes/development/observability/charter.md`, `docs/notes/development/observability/decisions/ADR-003-collection-topology.md`, `docs/notes/development/observability/architecture/reference-architecture.md`, `docs/notes/development/observability/components/otel-collector.md`, `modules/README.md`

- [ ] **Step 1: README and runbook (tasks.md 7.1)**

The collector README gains a section on the ingress: caddy on the ZeroTier address, the identity map and its source (`meshIdentities`), `X-Vanixiets-Host`, the socket and its group, the mesh pipelines and their filters, the pinned entries, and C6.
The runbook gains: reading a `C6 binding` failure (filter drop, caddy refusal, neighbour entry) and its first checks; adding a collecting host (its `flake.lib.hosts` address, the certificate reissue with `CLAN_NO_COMMIT=1`, magnetite's deploy after the MAC gate); the lost-machine steps, starting with deauthorizing the member on cinnabar's controller; and the rollback of Task 5 Step 5 over `root@magnetite.scientistexperience.net`.
Expected: `rg -n 'X-Vanixiets-Host|otelcol-mesh|C6|deauthori|magnetite.scientistexperience.net'` over both files shows each (delivered file).

- [ ] **Step 2: Charter and decision records (tasks.md 7.2)**

Add charter v30, dated, after v29: CAM-81's O1 to O11; ADR-003 amended in place at Consequences (:199-201: a host writes over the mesh only under its own name, from its own address; the Android members still cannot write), R3.1 (caddy's site is the one listener off loopback; the collector's `otlp/mesh` is a socket), its envelope (caddy's bound and kill-order place) and Implementation surface; the reference architecture (:102); `components/otel-collector.md`; `modules/README.md` names `flake.lib.zerotierMac`.
Expected: `rg -n 'v30' docs/notes/development/observability/charter.md` and `rg -n 'spiffe://vanixiets' docs/notes/development/observability/` each show the change (delivered file).

- [ ] **Step 3: Format and open pull request 3 (tasks.md 7.3)**

`nix fmt`; `nix fmt -- --fail-on-change`; open the pull request in plain words.
Expected: exit 0; nixbot green (command).

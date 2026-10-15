---
title: Telemetry access control, prompt-content hazard, and tenancy
status: research v1
date: 2026-09-18
sources:
  - cameronraysmith/vanixiets@da74672e5
  - GreptimeTeam/greptimedb@20d87cff4
  - perses/perses@21376aaf
  - https://code.claude.com/docs/en/monitoring-usage
  - https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/redactionprocessor/README.md
---

# Telemetry access control, prompt-content hazard, and tenancy

## Findings

### Prompt content in agent-session telemetry

F1 The one agent harness in the fleet with a documented OpenTelemetry surface emits three signal families: metrics, events over the logs protocol, and beta spans, each content-bearing field individually gated (https://code.claude.com/docs/en/monitoring-usage, fetched 2026-09-18).

F2 Span attributes carrying model input are `user_prompt` on `claude_code.interaction`, which is the literal string `<REDACTED>` unless `OTEL_LOG_USER_PROMPTS` is set, and `file_path`, `full_command`, `skill_name`, `subagent_type` and `workflow.name` on `claude_code.tool`, each gated by `OTEL_LOG_TOOL_DETAILS` (same source).

F3 Repository content reaches spans through the `tool.output` span event on `claude_code.tool`: `content` is Read output or Write input, `output` is a Bash command's stdout with stderr interleaved, `diff` is the applied Edit patch, each truncated at `CLAUDE_CODE_OTEL_CONTENT_MAX_LENGTH`, default 61440 UTF-16 code units (same source).

F4 Log bodies carry the larger hazard: `claude_code.user_prompt.prompt`, `claude_code.assistant_response.response`, and `claude_code.tool_result.tool_input` and `tool_parameters` are content fields on event records, and `claude_code.api_request_body.body` is the serialized Messages API request including system prompt, tools, and the entire conversation history (same source).

F5 `OTEL_LOG_RAW_API_BODIES=file:<dir>` writes untruncated request and response bodies to the emitting host's filesystem and puts only a `body_ref` path in the event, so that gate creates an on-disk corpus outside the telemetry pipeline entirely (same source).

F6 Error messages need separate treatment because their gating is inconsistent: `claude_code.api_error.error` is a free-form error message with no gate, `claude_code.tool_result.error_type` is an ungated category token while its full-message sibling `error` is gated by `OTEL_LOG_TOOL_DETAILS`, and `claude_code.tool.execution.error` carries the category unless that same gate is set (same source).

F7 Identity travels ungated: `user.email` is "always included when available", `user.account_uuid` and `user.account_id` default to included, and `terminal.type` is included when detected; `vcs.repository.url.full`, `vcs.owner.name` and `vcs.repository.name` are opt-in and default to off (same source).

F8 A useful content-free dev-loop vocabulary already exists in the same schema: `bash_argv0` and `bash_command_class` from fixed lists, `tool_name_safe`, `query_source_safe`, `prompt_length`, `response_length`, `tool_input_size_bytes`, `tool_result_size_bytes`, `result_tokens`, and the whole metric set (`claude_code.token.usage`, `cost.usage`, `lines_of_code.count`, `commit.count`, `active_time.total`) (same source).

F9 Every gate in F2 through F6 is an environment variable read by the emitter, and the worker-side environment is the worker's own, so emitter-side default-off is a starting posture rather than an enforced one; the collector is the only enforcement point the fleet controls.

F10 The contrib `redaction` processor fails closed on keys: `allowed_keys` empty removes all attributes, `allow_all_keys: false` is required for that, `blocked_key_patterns` masks values of matching keys, `hash_function` substitutes a digest for the mask, and `summary: silent` suppresses the diagnostic attributes that otherwise name the redacted keys (https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/redactionprocessor/README.md, fetched 2026-09-18).

F11 That processor's documented body handling covers "log records whose body is a map"; a log record with a plain string body has no documented redaction path in it, so string bodies require a `filter` or `transform` stage instead (same source).

F12 Its stability is alpha for logs and metrics and beta for traces, so the log path a prompt would travel is the least-proven path in the component (same source).

### The store as a lateral read capability

F13 Group-based admission exists and is wired, but the repository cannot answer who holds it: `matrix_users` and `omnigent_users` are declared as stubs with `members = [ ]` and `overwriteMembers = false`, membership being operational (`cameronraysmith/vanixiets@da74672e5:modules/nixos/kanidm.nix:198-216`).

F14 Group admission is enforced by scope maps: the `omnigent` client's only scope map is `scopeMaps.omnigent_users = [ "openid" "profile" "email" ]`, so a non-member cannot satisfy the client's scope request (`cameronraysmith/vanixiets@da74672e5:modules/nixos/kanidm.nix:261-266`).

F15 The `sso-gateway` admission mechanism is one shared `oauth2-proxy` unit reached through an nginx `auth_request` subrequest that carries the vhost's authorized groups as an `allowed_groups` query parameter, with a browser 401 redirect and an `/api` fast 401 (`cameronraysmith/vanixiets@da74672e5:modules/nixos/sso-gateway.nix:69-73,134-156`).

F16 The gateway's own doctrine excludes a Perses-shaped consumer: a service with built-in OIDC "should instead register a direct per-service kanidm client and authenticate natively, bypassing the gateway", because routing it through `sso.services.*` would double-gate it (`cameronraysmith/vanixiets@da74672e5:modules/nixos/sso-gateway.nix:18-23`).

F17 The gateway also records a weakened-isolation tradeoff: one shared client secret and one token audience span every gated service (`cameronraysmith/vanixiets@da74672e5:modules/nixos/sso-gateway.nix:39-43`).

F18 The gateway is not running: `sso.enable = false` on magnetite, with the cognee registration and `rootRedirectUrl` retained but inert (`cameronraysmith/vanixiets@da74672e5:modules/machines/nixos/magnetite/default.nix:133,151-153`).

F19 Perses gates authentication and authorization together: `EnableAuth` is a single switch, enabling it with no Kubernetes provider forces `Authorization.Provider.Native.Enable = true`, and configuring an authorization provider without auth is a startup error (`perses/perses@21376aaf:pkg/model/api/config/security.go:157,193-199`).

F20 Perses authorization reaches the datasource proxy: the proxy endpoint calls `checkPermission` per project name, scope and action, and uses the wildcard project for global scopes (`perses/perses@21376aaf:internal/api/impl/proxy/proxy.go:178-191`).

F21 Perses has a global read-only posture independent of RBAC: `Readonly` deactivates every POST, PUT and DELETE endpoint (`perses/perses@21376aaf:pkg/model/api/config/security.go:143-144`).

F22 Perses stores datasource credentials encrypted under a key that silently defaults if unset, logging only a warning, and accepts `encryption_key_file` with a 32-byte requirement (`perses/perses@21376aaf:pkg/model/api/config/security.go:150-154,166-184`).

### Multi-person tenancy

F23 The subject population is two humans and five dedicated worker accounts, Cameron on magnetite, pyrite and stibnite and Janette on magnetite and pyrite, each a separate Unix account with a locked password and an `0700` home (`cameronraysmith/vanixiets@da74672e5:modules/clan/services/omnigent/README.md:121-123,318`).

F24 The repository already holds a per-person partition invariant for credentials: "Static grants are shared across the person's referencing hosts, never across people" (`cameronraysmith/vanixiets@da74672e5:modules/clan/services/omnigent/README.md:298`).

F25 The worker boundary is the Unix account and nothing narrower: "The dedicated Unix account is the whole-worker boundary", with upstream `sandbox: none` explicitly accepted (`cameronraysmith/vanixiets@da74672e5:modules/clan/services/omnigent/README.md:184-186`).

F26 The repository states the consequence for any worker-readable secret directly: the delivered Keychain password "is readable by the worker, so this arrangement preserves the Unix-account boundary, not secrecy against that worker's code or administrators" (`cameronraysmith/vanixiets@da74672e5:modules/clan/services/omnigent/README.md:237`).

F27 GreptimeDB's open-source user providers authenticate but do not authorize: both `StaticUserProvider::authorize` and the watch-file provider's `authorize` return `Ok(())` with the comment "default allow all", so a credential valid for one catalog and schema is valid for all of them (`GreptimeTeam/greptimedb@20d87cff4:src/auth/src/user_provider/static_user_provider.rs:78-86`, `GreptimeTeam/greptimedb@20d87cff4:src/auth/src/user_provider/watch_file_user_provider.rs:94-97`).

F28 The one authorization lever the open build does enforce is a per-user access mode parsed from the credential line as `username:permission_mode=password`, with `ReadWrite`, `ReadOnly` and `WriteOnly` accepted as `rw`, `ro` and `wo`, checked by `DefaultPermissionChecker` against whether the request is a read or a write (`GreptimeTeam/greptimedb@20d87cff4:src/auth/src/user_provider.rs:482-506`, `GreptimeTeam/greptimedb@20d87cff4:src/auth/src/user_info.rs:30-56`, `GreptimeTeam/greptimedb@20d87cff4:src/auth/src/permission.rs:325-356`).

F29 Finer-grained permission is a plug-in seam with no in-tree implementation: the `PermissionChecker` trait takes catalog, schema and table targets and `ALL_ACTIONS` names sixteen actions including `otlp.write`, `promql.query` and `log.query`, but every in-tree implementor is a test double or the mode-only default, and `Option<&PermissionCheckerRef>::None` allows everything (`GreptimeTeam/greptimedb@20d87cff4:src/auth/src/permission.rs:138-180,267-289`).

F30 Schema selection is caller-supplied: the HTTP layer extracts catalog and schema from the `x-greptime-db-name` header or a `db` query parameter before authentication, so a schema-per-person layout is expressible but, under F27, is not a boundary (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http/authorize.rs:60-64,410-412`, `GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http/header.rs:45`).

### The collector and the store as ingress

F31 An unauthenticated store is the default, not a misconfiguration: when no user provider is configured, `inner_auth` sets the request's user to `userinfo_by_name(None)` and returns before any credential check (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http/authorize.rs:72-81`).

F32 With a provider configured, authentication covers the OTLP routes: `need_auth` is true for any path under `/v1/`, the OTLP routes are nested at `/v1/otlp` with `/v1/metrics`, `/v1/traces` and `/v1/logs` beneath it, and only four health paths bypass (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http.rs:126,170-175,767-772,1492-1494`).

F33 Transport authentication in the open build is username and password only: `authenticate_bearer_token` fails with `UnsupportedAuthMethod` in the default trait implementation and no in-tree provider overrides it, so a Kanidm-issued token cannot authenticate to the store and the caller must present HTTP Basic against a static credential file (`GreptimeTeam/greptimedb@20d87cff4:src/auth/src/user_provider.rs:90-108`, `GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http/authorize.rs:83-110`).

F34 The mesh is flat and membership equals reachability: ten machines are declared, all reached over ZeroTier with `cinnabar` the controller, and the inventory declares no flow rules or per-member restrictions (`cameronraysmith/vanixiets@da74672e5:modules/clan/inventory/machines.nix:23-86`).

F35 The repository's mesh-only precedent is cognee: the REST API binds the host's ZeroTier address, the firewall opens the port on `zt+` only, a build-time assertion rejects any listener outside loopback or the ZeroTier prefix, and `REQUIRE_AUTHENTICATION` mitigates "the surface widening from binding the full REST surface to the mesh" (`cameronraysmith/vanixiets@da74672e5:modules/nixos/cognee.nix:26-27,141-142,149-155,172-186,258`).

F36 The second precedent adds a token to the mesh bind: omnigraph binds `magnetite.zt` and reads a generated bearer-token file (`cameronraysmith/vanixiets@da74672e5:modules/machines/nixos/magnetite/default.nix:398,403-404`).

### Secrets for the store's own credentials

F37 The generator pattern to copy for a store credential file is `omnigraph-bearer-tokens`: `runtimeInputs` of openssl and jq, a script writing a JSON token map to `$out/tokens.json`, and `restartUnits` naming the consuming unit (`cameronraysmith/vanixiets@da74672e5:modules/machines/nixos/magnetite/default.nix:375-386`).

F38 For an externally minted credential the pattern is `omnigraph-r2`: `prompts` of type `hidden` with `persist = true`, per-file `deploy = false` on the raw prompt files, and a rendered `env` file carrying `restartUnits` (`cameronraysmith/vanixiets@da74672e5:modules/machines/nixos/magnetite/default.nix:335-372`).

F39 The consumption pattern for a credential a hardened unit must read is `oauth2-proxy-kanidm`: `DynamicUser = true` plus `LoadCredential` entries referenced as `%d/<name>`, with the generator declaring `owner`, `group`, `mode = "0400"` and `restartUnits` (`cameronraysmith/vanixiets@da74672e5:modules/nixos/sso-gateway.nix:374-411,429-445`).

F40 A verbatim-reading consumer forces a trailing-newline decision: `kanidm-oauth2-sso` uses `printf '%s'` to strip the newline that `openssl rand -hex 32 >` would leave, because oauth2-proxy reads the file verbatim while kanidm-provision trims (`cameronraysmith/vanixiets@da74672e5:modules/nixos/sso-gateway.nix:386-393`).

F41 `restartUnits` is load-bearing because `LoadCredential` snapshots at unit start, and the repository records this as an invariant across both kanidm generators (`cameronraysmith/vanixiets@da74672e5:modules/nixos/kanidm.nix:98-121`).

F42 GreptimeDB can avoid a restart on rotation: `watch_file_user_provider` loads the credential file, watches it, reloads on change, and keeps the old map when a reload fails; both an empty and a missing file fail initialization (`GreptimeTeam/greptimedb@20d87cff4:src/auth/src/user_provider/watch_file_user_provider.rs:34-75`).

F43 The per-person sharing shape already exists in clan vars: enabled worker credential sources are "per-person shared hidden-prompt Clan generators (`share = true`)" with secret files owned by the worker at mode `0400`, and adding a referencing machine requires re-encryption for the new recipient list (`cameronraysmith/vanixiets@da74672e5:modules/clan/services/omnigent/README.md:250,300`).

## Bearing on decisions

### D8 Access control and tenancy

The evidence points to a three-layer split with no layer trusted to do another's job.
Content exclusion belongs at the collector as a fail-closed attribute allow-list, because F9 makes emitter-side gates unenforceable and F10 gives the collector a fail-closed primitive; the concrete requirement is `allow_all_keys: false` with an enumerated `allowed_keys` drawn from F8, `summary: silent` per F10, an explicit `filter` stage dropping the `claude_code.api_request_body` and `claude_code.api_response_body` records and the `tool.output` span event by name per F3 through F5, and a `transform` or `filter` rule for string log bodies per F11 since the redaction processor does not cover them.
Error messages need their own rule rather than the same rule: F6 shows `claude_code.api_error.error` is the single ungated free-form message field, so the allow-list must either exclude it or hash it, while the ungated `error_type` and `error_class` category tokens are safe to keep and are the fields a coverage-model decision actually reads.
Admission for the dashboard layer should be a direct Kanidm client on Perses rather than the `sso-gateway`, on the gateway's own stated rule (F16) reinforced by F19 and F20: Perses needs `EnableAuth` true to have any authorization at all, and only its native authorization gates the datasource proxy, so terminating auth in front of an opaque Perses would leave every admitted person with proxy access to the whole store.
Reversal: if Perses' OIDC client turns out not to work against this Kanidm deployment, the gateway plus a `Readonly` Perses (F21) becomes the fallback, at the cost of losing per-project partition.
Tenancy should be per-person by default because F24 already sets that invariant for credentials and F7 shows telemetry carries `user.email` on every record, but F27 through F30 mean the store cannot enforce it: the only open-build levers are separate credentials with `ro`, `wo` or `rw` modes and a schema or catalog that is a label, not a boundary.
Enforcement therefore lands on Perses projects and role bindings (F20), with the store credential held only by the collector and by Perses, never by a worker account; F25 and F26 make any worker-readable read credential equivalent to granting that worker's code the whole fleet read channel.
Reversal: evidence that the open build's `PermissionChecker` seam has a usable in-tree or first-party open implementation (F29) would move partition enforcement down into the store and make per-person store users a real boundary.

### D3 Collection topology and transport authentication

F31 makes an unauthenticated OTLP ingress the default state, and F34 makes any mesh-bound unauthenticated port readable and writable by every process on ten machines, including the five worker accounts.
The evidence points to the cognee shape (F35) as the minimum: mesh-only bind, `zt+`-only firewall port, a build-time assertion that no listener escapes loopback or the ZeroTier prefix, and authentication on regardless, plus the omnigraph token file (F36) for the credential itself.
Transport authentication is HTTP Basic against a static credential file (F33); a bearer or OIDC token path does not exist in the open build, which closes off reusing Kanidm tokens for machine ingress.
A compromised worker with a write-only credential cannot read the store, but F27 means it can insert into any schema, so cross-person poisoning is prevented only if the collector, not the emitter, stamps the identifying attributes and each person's workers hold distinct write credentials.
Flood is not bounded by the auth path at all: nothing in F31 through F33 rate-limits, so the envelope must be declared on collector queue and batch limits plus store retention, with the regulator sampling ingest volume per credential.
Reversal: a first-party per-host collector that emitters reach only over a loopback socket would remove worker-held store credentials entirely and reduce this to a local-socket permission question.

### D1 Store selection

F27 through F29 are a substantive constraint on the leading candidate: the open build authenticates but does not authorize beyond a per-user read/write mode, so a single store holding both humans' agent-session telemetry cannot partition reads internally.
Reversal: a store whose open build does enforce per-schema read authorization would make the single-store, per-person-schema design a real boundary instead of a labeling convention.

### D2 Dashboard layer

F19, F20 and F22 give Perses a usable authorization model and one configuration hazard: the encryption key defaults silently, so `encryption_key_file` plus a generator is a requirement, not a hardening option.

### D4 Signal scope and schema

The allow-list in D8 is the schema: F8 enumerates the content-free fields that survive it, and any signal proposed in D4 that is not on that list must be justified against the hazard rather than added by default.

### D7 Packaging and clan service shape

F37 through F43 fix the generator shapes: a `restartUnits`-bearing openssl-plus-jq generator for the store's static credential file, a `prompts`-based generator only if a credential is minted elsewhere, owner, group and `mode = "0400"` on every secret file, `LoadCredential` at the consuming unit, an explicit trailing-newline decision per F40 because the credential file is parsed verbatim, and `share = true` for anything that must be identical across one person's hosts.

## Flags

W9 is confirmed and understated.
The charter says traces and logs "can carry prompt content and repository contents"; F3 through F5 show the same emitter can also carry the full conversation history including the system prompt, and can write untruncated request bodies to the host filesystem outside the telemetry pipeline.

RK5's confirming observation is already satisfiable in the default schema.
F6 shows `claude_code.api_error.error` is a free-form message attribute with no gate at all, so an unredacted default configuration meets RK5's trigger without anyone enabling a content gate.

The assignment's premise that an `omnigent_users`-style group gate plus `sso-gateway` is available today is contradicted by the deployed configuration.
F18 records `sso.enable = false` on magnetite, so the gateway unit, its Kanidm client and its vhosts are not emitted; any dashboard admission design that depends on the gateway must first re-enable it, and that is a decision with its own blast radius, since the module also owns `auth.scientistexperience.net`.

Group membership is not reviewable from the repository.
F13 means the answer to "who can read the store" lives only in the running Kanidm database, so no check, review, or ADR can assert the current reader set; a regulator over access can only assert the declared group names and scope maps.

Absence, reported explicitly: the repository declares no OpenTelemetry emitter, collector, redaction rule, or store credential today, so every finding above about redaction and ingress describes a design to be created rather than a configuration to be corrected.

Absence, reported explicitly: no ZeroTier flow rule, member allow-list, or per-port mesh ACL appears anywhere in the inventory (F34), so "on the mesh" is a single flat trust zone spanning ten machines, two laptops among them.

Absence, reported explicitly: `opentelemetry-collector-contrib` is absent locally, so F10 through F12 rest on upstream documentation at a fetch date rather than on a pinned source revision, and the processor's behavior on a string log body is unverified against code.

Vendor-claim caution on the store: F29 shows a catalog of sixteen named permission actions and a table-target-aware `PermissionChecker` trait with no in-tree implementation beyond the mode-only default and test doubles.
That is the shape of a seam reserved for a closed implementation, and it is consistent with W7's unverified open and enterprise boundary; whether upstream documentation advertises role-based access control for the open build is not verified in this artifact.

The `sso-gateway` shared-client tradeoff (F17) compounds if the telemetry dashboard joins it: one client secret and one audience would then span the knowledge base and the fleet-wide telemetry read channel.

## Questions

Q1 Should agent-session telemetry be partitioned per person at all, given that both humans work on the same repositories and the dev-loop consumer arguably wants the fleet-wide view?

Q2 If partitioned, may Janette's telemetry be readable by Cameron as fleet operator, and is the reverse also intended?

Q3 Is prompt or tool content ever wanted, even opt-in for a single named session under an explicit flag, or is content exclusion absolute so the collector allow-list can be fixed once?

Q4 Is re-enabling `sso.enable` on magnetite in scope for this design, or must the dashboard layer be designed to work with the gateway disabled?

Q5 Should the store credential be held only by a per-host collector, which requires deciding whether nix-darwin hosts run a collector as root, or may worker-adjacent processes hold a write-only credential directly?

Q6 What retention applies to the identifying attributes that survive redaction, specifically `user.email` and `session.id`, which are the fields that make a partition meaningful and also the fields that make the store a personal-activity record?

## Refresh (2026-10-15)

Revisions read for this refresh: `GreptimeTeam/greptimedb@4859e57e0` (main, 2026-10-15), its release tags `v1.1.4` (`16e9abe4a`), `v1.2.1` (`179ff8e50`, latest stable) and `v1.3.0-beta.2` (`a788cd977`); `perses/perses@4c719fc1` (`v0.54.0`, latest stable) and `perses/perses@021f2d8f` (`v0.55.0-rc.0`); `cameronraysmith/vanixiets@b62ba051a`.
nixpkgs facts are evaluated against this flake's root `nixpkgs` input, which is now the lock node `nixpkgs_10` at rev `ac1faec44836a722f7b003834f367486ff9adfd1`, not the `nixpkgs_9` node the original corpus named; nixpkgs `master` at `cbffcb102` carries the same versions for every attribute cited here.

### What changed

#### GreptimeDB authorization (RK9)

R1 The open-build user providers still authorize nothing: `StaticUserProvider::authorize` and the watch-file provider's `authorize` return `Ok(())` under the comment "default allow all" at the packaged release, at the latest stable release and at current main (`GreptimeTeam/greptimedb@16e9abe4a:src/auth/src/user_provider/static_user_provider.rs:75-77`, `GreptimeTeam/greptimedb@179ff8e50:src/auth/src/user_provider/watch_file_user_provider.rs:94-96`, `GreptimeTeam/greptimedb@4859e57e0:src/auth/src/user_provider/static_user_provider.rs:78-86`).
R2 The per-user `rw`, `ro` and `wo` mode parsed from `username:permission_mode=password` is present unchanged at all three revisions, and `DefaultPermissionChecker` remains the only non-test implementor of `PermissionChecker` in the open tree (`GreptimeTeam/greptimedb@16e9abe4a:src/auth/src/permission.rs:112-121`, `GreptimeTeam/greptimedb@4859e57e0:src/auth/src/user_provider.rs:482-498`, `GreptimeTeam/greptimedb@4859e57e0:src/auth/src/permission.rs:325-347`).
R3 Upstream documents per-database and per-table authorization as an Enterprise product: `greptime_ee_user_provider` provides RBAC roles, global privileges and table-level ACLs by exact name or regular expression, stored in the Metasrv (https://docs.greptime.com/enterprise/user, fetched 2026-10-15).
R4 That provider is absent from the open repository: no `greptime_ee_user_provider` string and no ACL entry in `licenserc-enterprise.toml` exist at `GreptimeTeam/greptimedb@4859e57e0`, so it ships in a separate Enterprise binary rather than behind the open repository's `enterprise` Cargo feature.
R5 The HTTP bearer-token path now exists in the request pipeline but remains unusable in the open build: `inner_auth` routes an `Authorization: Bearer` header to `auth_bearer_token` and returns an error on failure instead of falling back to Basic, while the trait default for `authenticate_bearer_token` still fails with `UnsupportedAuthMethod` and no in-tree provider overrides it (`GreptimeTeam/greptimedb@4859e57e0:src/servers/src/http/authorize.rs:83-110`, `GreptimeTeam/greptimedb@4859e57e0:src/auth/src/user_provider.rs:90-107`).
R6 The packaged release predates that path entirely: `v1.1.4` has no `authenticate_bearer_token` in `src/auth`, so a collector sending a bearer header to the packaged store is rejected rather than authenticated.
R7 Credential-file rotation through sops-nix symlink swaps is fixed only from `v1.3.0-beta.1` onward: the watch-file provider previously watched only the immediate parent directory, so an `ln -sfn` swap elsewhere in the path chain "never produced an event" and the new users file was not loaded until restart (`GreptimeTeam/greptimedb@d5a6a9ac0`, commit message of #9365).
R8 Decompression-amplification bounds on compressed ingest requests landed on main after the latest beta and are not in any stable release: handler-level decompression gains a 512 MiB decoded-size cap charged to the server memory limiter (`GreptimeTeam/greptimedb@3131cdbcb`, commit message of #9264; first tag `v1.4.0-alpha.0`).
R9 `greptimedb` 1.1.4 is now in the root nixpkgs pin, `asl20`, built from tag `v1.1.4` with no NixOS module (`NixOS/nixpkgs@ac1faec4:pkgs/by-name/gr/greptimedb/package.nix:15,22,84`, root node `nixpkgs_10`).

#### Perses RBAC and datasource-proxy enforcement

R10 The packaged release is `perses` 0.54.0 and the root pin now ships a NixOS module for it at `nixos/modules/services/monitoring/perses.nix`, which runs the unit with `DynamicUser = true` and materializes `_secret` file references through `LoadCredential` (`NixOS/nixpkgs@ac1faec4:pkgs/by-name/pe/perses/package.nix:31`, `NixOS/nixpkgs@ac1faec4:nixos/modules/services/monitoring/perses.nix:24-25,91,98`, root node `nixpkgs_10`).
R11 The F19 and F20 model holds at both 0.54.0 and 0.55.0-rc.0: enabling auth without the Kubernetes provider forces native authorization on, and every proxy endpoint calls `checkPermission` with the project, scope and action (`perses/perses@021f2d8f:pkg/model/api/config/security.go:204-210`, `perses/perses@021f2d8f:internal/api/impl/proxy/proxy.go:165-182`, `perses/perses@4c719fc1:pkg/model/api/config/security.go:195`).
R12 The unsaved-datasource proxy, which lets a caller supply an arbitrary target, requires `create` on the datasource scope and `read` on the secret scope when a secret is referenced, so a role holding only `read` on datasources cannot point the proxy at a new target (`perses/perses@021f2d8f:internal/api/impl/proxy/localdatasource.go:48,60,69`, `perses/perses@021f2d8f:internal/api/impl/proxy/projectdatasource.go:47,59,68`).
R13 Five security changes landed after 0.54.0 and first appear in 0.55.0 pre-releases, so none is in the packaged binary.
R14 Since 0.55.0-rc.0 the proxy no longer forwards the caller's Perses session token to the datasource when native authorization is enabled, because "anyone controlling or observing the datasource would be able to impersonate the caller" (`perses/perses@021f2d8f:internal/api/impl/proxy/proxy.go:184-191`, `perses/perses@835dc355`).
R15 Since 0.55.0-rc.0, enabling auth without `encryption_key` or `encryption_key_file` is a startup error rather than a warning plus a default key, which converts the F22 hazard into a configuration failure (`perses/perses@021f2d8f:pkg/model/api/config/security.go:174-179`, `perses/perses@e799e7cb`).
R16 Since 0.55.0-beta.4 secrets may reference files only under `security.secret_file_allowed_directories`, closing a path by which a user able to create a secret could "exfiltrate arbitrary files through the datasource proxy" (`perses/perses@bb8fd345`, commit message of #4503).
R17 Since 0.55.0-rc.0 a connect-time network guard restricts proxy targets: loopback, link-local and cloud-metadata ranges are denied by default, `allowed_hosts` when non-empty is the exhaustive list of reachable hosts, `allowed_networks` overrides denials by longest prefix, and `fc00::/7` is denied only when `deny_private_networks` is true (`perses/perses@021f2d8f:internal/api/netguard/netguard.go:14-30,99-122`, `perses/perses@021f2d8f:pkg/model/api/config/datasource.go:207-223`, `perses/perses@d5cbc44e`).
R18 Since 0.55.0-beta.4 the SQL proxy executes queries in a read-only transaction and accepts only statements beginning with a read keyword, replacing a blocklist the commit records as bypassable (`perses/perses@379673eb`, commit message of #4522).

#### Omnigent worker isolation and the prompt-content hazard (W9, RK5)

R19 The five dedicated worker accounts are unchanged in shape: separate accounts with locked passwords and `0700` homes, each supervised as `omnigent-host-<key>` with `UMask=0077` and `NoNewPrivileges` (`cameronraysmith/vanixiets@b62ba051a:modules/clan/services/omnigent/README.md:123,185`).
R20 The worker boundary is still the Unix account and nothing narrower, with `sandbox: none` accepted and "same-UID/admin access and shared-store visibility for approved projects" (`cameronraysmith/vanixiets@b62ba051a:modules/clan/services/omnigent/README.md:193-195,316`).
R21 The fleet obligations now assert that every declared worker's supervisor-level `environment` is empty (`cameronraysmith/vanixiets@b62ba051a:modules/lib/omnigent-fleet-obligations.nix:73`).
R22 The reserved-environment policy rejects names with the prefixes `CLAUDE_`, `OMNIGENT_`, `PI_`, `OMP_` and others, but reserves no `OTEL_` name, so `OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_DETAILS` and `OTEL_LOG_RAW_API_BODIES` are not covered by that policy (`cameronraysmith/vanixiets@b62ba051a:modules/lib/omnigent-environment.nix:26-39`).
R23 The repository still declares no OpenTelemetry emitter, collector, redaction rule or store credential, and the `omnigent_users` Kanidm group is still a stub with `members = [ ]`, so F13 and the original absence flag stand (`cameronraysmith/vanixiets@b62ba051a:modules/nixos/kanidm.nix:218-224`).

#### Collector redaction processor, now read at source

R24 The `redaction` processor's stability is unchanged at alpha for logs and metrics and beta for traces (`open-telemetry/opentelemetry-collector-contrib@cd37ea9:processor/redactionprocessor/metadata.yaml:12-14`).
R25 A string log body does pass through the processor, but only through value-pattern masking: the non-map, non-slice branch converts the body to a string and applies `processStringValueForLogBody`, with no key allow-list involved (`open-telemetry/opentelemetry-collector-contrib@cd37ea9:processor/redactionprocessor/processor.go:191-235`).
R26 That branch fails open: a prompt in a string body survives unless a configured blocked-value pattern happens to match it, so the fail-closed property of F10 does not extend to string bodies.

### Bearing on D8 and D3

Worker isolation does not change what an agent session emits, so it does not narrow W9 or discharge the RK5 obligation.
It changes three things about where the hazard can be contained.
First, the account boundary partitions harness configuration by person, so one person's worker cannot alter another person's emitter gates, but under R20 any code a worker runs, including prompt-injected code, can set its own `OTEL_*` variables and edit its own harness settings, so F9 still holds within each account.
Second, the supervisor-level environment assertion in R21 guarantees only that the fleet configuration does not itself turn content gates on; it is not an enforcement point against the worker, and R22 shows the reserved policy would not reject an `OTEL_` content gate added later through role settings.
Third, the account boundary makes the collector placement enforceable: a collector running under a system account outside every worker's UID, with its configuration in the Nix store, is configuration no worker can modify.
Collector-side redaction must therefore sit in a per-host collector that runs outside every worker account, with the F10 allow-list and the F3 to F6 filter stages applied before the exporter.
On magnetite the store and two worker accounts share a host, so the store's listener must require credentials even on loopback, because loopback is reachable by every local UID.
Under R20 any credential delivered to a worker account, including a write-only one at mode `0400`, is usable by code that worker runs, so this evidence strengthens the Q5 option in which only the per-host collector holds a store credential and workers reach only that collector.
Per-person read partitioning still cannot be enforced in the open store (R1, R2), and R3 and R4 show that the capability which would enforce it exists upstream only as a paid product, so the original D8 reversal condition, a usable open `PermissionChecker` implementation, should be treated as unlikely rather than pending.
Enforcement therefore stays on Perses project role bindings, and R13 through R18 make the Perses version a security decision: 0.54.0, the packaged version, forwards the caller's session token to the datasource, accepts a default encryption key with auth enabled, and has no proxy target guard.
If Perses and GreptimeDB are co-located on magnetite, R17 means the 0.55 line denies the loopback target by default, so the configuration must set `allowed_hosts` to the store host alone and allow only the specific loopback or mesh address, rather than allowing all of `127.0.0.0/8`, which would expose every loopback service on magnetite to any role with datasource `create`.

### Corrections

C1 Supersedes the Flags paragraph's statement that "whether upstream documentation advertises role-based access control for the open build is not verified": upstream advertises RBAC and table-level ACLs only for GreptimeDB Enterprise (R3), and the open build has none (R1, R2, R4).
C2 Supersedes the D8 reversal sentence "evidence that the open build's `PermissionChecker` seam has a usable in-tree or first-party open implementation (F29) would move partition enforcement down into the store": the first-party implementation exists and is closed (R3, R4), so that reversal now requires either buying the Enterprise build or writing a provider ourselves.
C3 Qualifies F42: watch-file reload survives a sops-nix symlink swap only from `v1.3.0-beta.1`, and the packaged 1.1.4 and the stable 1.2.1 need the `restartUnits` pattern of F41 for rotation to take effect (R7).
C4 Qualifies F22 and the D2 sentence calling `encryption_key_file` "a requirement, not a hardening option": that requirement is enforced by Perses itself only from 0.55.0-rc.0 (R15), and at the packaged 0.54.0 it remains a requirement the configuration must impose.
C5 Qualifies F20: the per-project gate holds at 0.54.0, but at that version the proxy also forwards the caller's Perses session token to the datasource (R14), so the store, or anyone observing traffic to it, receives a replayable Perses credential.
C6 Corrects F11's "a log record with a plain string body has no documented redaction path": a code path exists but masks only by value pattern and fails open (R25, R26), so the conclusion that string bodies need a `filter` or `transform` stage stands, now on source evidence rather than documentation.

### Questions

Q7 Is buying or trialing GreptimeDB Enterprise in scope, given that its user provider is the only first-party route to per-database read partitioning in the store (R3)?
Q8 Should the dashboard layer wait for Perses 0.55.0, which carries R14 through R18, or deploy the packaged 0.54.0 with a compensating configuration and a recorded upgrade obligation?
Q9 Should `OTEL_` be added to the reserved worker-environment prefixes so that no role setting can enable a content gate, accepting that this constrains the supervisor and not the worker's own code (R22)?
Q10 Should the store's ingest endpoint on magnetite be reachable only from the local collector over loopback, with remote hosts' collectors authenticating over the mesh, or should every host's collector, including magnetite's, use the mesh address?

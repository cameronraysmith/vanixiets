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

---
title: pi coding agent integration reconnaissance
---

Synthesis of ten reconnaissance passes over the pi coding agent (earendil-works/pi), its nix packaging in numtide/llm-agents.nix and nixpkgs, prior art in Mic92/dotfiles, pinpox/nixos, kunchenguid/dotfiles, and rytswd/pi-agent-extensions, and the vanixiets module surfaces a pi integration would touch.
Every claim below is anchored to a file and line in the source findings; where two passes disagree the disagreement is stated rather than resolved silently.
A subsequent verification pass — an independent source trace plus an empirical run against an earlier packaged pi binary — falsified the original skills recommendation and resolved two of the contradictions the reconnaissance left open.
Claims that pass verified are marked with the method that verified them, and claims it did not reach remain marked unverified rather than upgraded.

## What pi is

pi is an MIT-licensed TypeScript/Node monorepo whose user-facing artifact is the `pi` CLI shipped as the npm package `@earendil-works/pi-coding-agent`, requiring Node 22.19 or newer.
It deliberately ships no MCP support, no sub-agents, no hooks, no permission system, and no plan mode; TypeScript extensions loaded through jiti are the single extension mechanism, and skills follow the Agent Skills standard with `SKILL.md` frontmatter.
Configuration is two deep-merged JSON layers — global `~/.pi/agent/settings.json` and project `<cwd>/.pi/settings.json` — with no XDG support and no system layer, relocatable only through the `PI_CODING_AGENT_DIR` environment variable.
Credentials live separately in `~/.pi/agent/auth.json` at mode 0600, whose `key` values support `!command` shell-out and `$ENV_VAR` interpolation, which is the clean hook for declarative secret wiring.

## Packaging decision

The llm-agents.nix `pi` package is usable as-is at the currently locked revision and no input bump is required.
The current fleet evaluation resolves the deployed package to pi 0.84.1.
An earlier reconnaissance pass inspected `llm-agents` rev `92b4121e344b4c82f6f095c17f961762a505e4ab`; `git ls-tree` at that rev and at the then-current clone HEAD `5028d466` returned identical blob OIDs for all four files under `packages/pi/`, and `git diff --name-only 92b4121e HEAD -- packages/pi` was empty.
That earlier package used `buildNpmPackage` over an npm registry tarball pinned by a sidecar `hashes.json`, followed by a `bun build --compile` step producing a standalone binary, with a `makeWrapper` invocation that set `PI_PACKAGE_DIR`, `PI_SKIP_VERSION_CHECK=1`, and `PI_TELEMETRY=0` and prepended nixpkgs `fd` and `ripgrep` onto PATH.
vanixiets already trusts `cache.numtide.com` and declares the `llm-agents` input without a `nixpkgs.follows`, which is precisely the configuration under which the numtide binary cache substitutes rather than rebuilding.
The earlier substitution test fetched from `cache.numtide.com` with no local build; that command was not rerun as evidence for the current pi 0.84.1 package.

A local `pkgs/by-name` derivation is not needed and would be strictly worse: it would duplicate the bun-compile and darwin re-signing workarounds that llm-agents already carries, and it would forfeit cache substitution.
The competing option is nixpkgs' own `pi-coding-agent`, which was at the same then-current version during the earlier reconnaissance and was present at the locked nixpkgs revision.
Two reconnaissance passes describe that derivation differently — one reports it as `buildNpmPackage` from a GitHub source tag with a separately fetched model catalog, the other as `buildNpmPackage` over the `@earendil-works/pi-ai` npm tarball.
Either way it is a different upstream artifact from the llm-agents one, so the usual "nixpkgs lags, llm-agents leads" version rationale recorded in the tuicr module does not decide this; provenance and update cadence do.

The recommendation is to consume `flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi`, matching the herdr precedent of pointing an upstream home-manager module's `package` option at the llm-agents attribute.
Two caveats attach.
llm-agents' pi declares `platforms` from its napi target table and therefore does not support `x86_64-darwin`; every darwin machine in the fleet must be aarch64.
llm-agents' update CI runs four times daily with auto-merge enabled, so the upstream pin moves roughly daily — vanixiets is insulated by its own `flake.lock`, but a routine `nix flake update` will move pi's version without review.

Building pi from a git checkout is not viable in a nix sandbox: `packages/ai/src/providers/data/` is gitignored and the `generate-models` script fetches `models.dev/api.json` plus six provider APIs at build time.
The supported offline path is the GitHub release source archive with `scripts/build-binaries.sh --offline-model-data`, which is essentially what llm-agents already reproduces from the npm tarball.

## Config declarability

The decisive constraint is that `~/.pi/agent/` must itself be a real writable directory, not a store symlink.
Reading `settings.json` acquires a `proper-lockfile` lock that creates a `settings.json.lock` sidecar in the parent directory, on the read path rather than only on write.
Every run constructs `FileAuthStorageBackend`, which `mkdir`s the agent directory at mode 0700 and writes `auth.json` containing `{}` at mode 0600 if absent, even when all credentials come from environment variables.
The default session path performs an uncaught `mkdirSync` under `<agentDir>/sessions/`, which crashes rather than warning on a read-only parent.

Within that writable directory the inventory splits cleanly.
Must stay mutable: `settings.json`, `auth.json`, `trust.json`, `models-store.json`, `sessions/`, `bin/`, `npm/`, `git/`, `tmp/`, and `pi-debug.log`.
Safe to symlink from the store: `models.json` (loaded through an immutable snapshot loader with no writer anywhere in the source), the `skills/`, `prompts/`, `themes/`, and `extensions/` subtrees, and the `SYSTEM.md`, `APPEND_SYSTEM.md`, and `AGENTS.md` files.
`keybindings.json` is read-only in steady state but is rewritten in place by a one-shot format migration, so it is nearly-static rather than strictly static.

`settings.json` in particular cannot be a store symlink if pi is to behave normally.
On a fresh install pi writes `lastChangelogVersion`, and it does so again after any version bump — which a nix upgrade always is.
On interactive start with no `theme` set it persists the auto-detected terminal theme.
`/model` and `/theme` persist there, as do `pi install` and `pi remove` writing the `packages` array.
A failed write is caught, recorded, and surfaced as a yellow `Warning:` line rather than crashing, so a store symlink degrades to a recurring warning with silently discarded state rather than a hard failure.
The persist logic merges only session-modified fields back over the current on-disk content, so nix-seeded keys the user never touches survive a pi write.

The mechanism that fits is the one vanixiets uses for claude-code and codex: a `managedConfigs` entry that rewrites the target from the Nix-declared settings in an activation step after `writeBoundary`, with `replacesHomeFile` disabling the upstream `home.file` entry.
home-manager at the pinned revision already ships `programs.pi-coding-agent` with options `enable`, `package`, `extraPackages`, `configDir`, `settings`, `keybindings`, `models`, and `context`, and it writes `home.file` under absolute keys derived from `configDir` whose default is `${config.home.homeDirectory}/.pi/agent`.
The suppression key must therefore be the absolute `"${config.programs.pi-coding-agent.configDir}/settings.json"`, matching claude-code, not the relative `.pi/agent/settings.json`.
Targeting the relative path is a silent no-op that surfaces later as `checkLinkTargets` backup conflicts at deploy time.

By contrast `models.json` needs none of that machinery and should be a plain store symlink through `programs.pi-coding-agent.models`, on exactly the criterion the tuicr module states for its own config file: pi only ever reads it.
This mirrors the opencode and tuicr shape, where no override is taken at all.
pinpox/nixos independently arrived at the same partition, writing `~/.pi/agent/models.json` as a read-only symlink with the option description "Pi only reads this file, never writes to it".

## Instruction files and context discovery

pi does not extend the `.agents/` convention beyond skills, so `~/.agents/AGENTS.md` is inert.
This is verified two ways: an exhaustive source grep finds only four `.agents` string literals, every one of them joining `skills`; and an empirical run with `HOME` overridden to a scratch directory read `.agents/skills/fake-control-skill/SKILL.md` from that directory while ignoring the `.agents/AGENTS.md` sitting beside it.
The global instruction destination must therefore be pi-specific, and it must be `~/.pi/agent/AGENTS.md`.
It must specifically not be `SYSTEM.md`, which replaces pi's built-in system prompt entirely rather than appending to it.

There is no `settings.json` key for instruction files.
No `context`, `instructions`, `systemPrompt`, or `appendSystemPrompt` key exists; keys planted under all four names had no effect and produced no warning on stderr.
Unknown settings keys are silently ignored, which is a debugging hazard in its own right: a typo in a supported key is indistinguishable from an unsupported one.
The home-manager module does expose a `context` option, so whatever that option produces is file delivery rather than a settings key; confirm its target path before choosing that route over the unified generator.

Context-file discovery walks from the current working directory to the filesystem root.
It carries no git-repository-root stop, unlike skills discovery, which does stop at the git root, and it is not trust-gated.
Any `AGENTS.md` in any ancestor directory up to `/` is injected into the system prompt with no trust prompt, which is a security-relevant asymmetry between the two discovery mechanisms.
There is also no size limit and no truncation on context files: a 3,360,040-byte `AGENTS.md` was inlined verbatim.

Per directory, first match wins among `AGENTS.md`, `AGENTS.MD`, `CLAUDE.md`, and `CLAUDE.MD`.
A directory contributes at most one file and the loser is silently ignored.
The earlier packaged-binary pass found `AGENTS.override.md` absent, while the changelog attributed its introduction to 0.84.0; that observation was not rerun against deployed pi 0.84.1.
The vanixiets repository root carries both `AGENTS.md` and `CLAUDE.md` as symlinks to the same planning-repo target, so pi loads the project context once through `AGENTS.md` and the `CLAUDE.md` symlink is inert there.

## Authentication options matrix

| Path | Mechanism | Declarable | Irreducibly interactive | Risk |
|---|---|---|---|---|
| ChatGPT Plus/Pro (Codex) subscription | pi's built-in `openai-codex` provider, baseUrl `https://chatgpt.com/backend-api`, PKCE OAuth against `auth.openai.com` using the Codex CLI public client id, access token used as bearer with a `chatgpt-account-id` header from a JWT claim | model overrides in `models.json` only (for example widening `contextWindow`); no credential is declarable | the full `/login` browser or device-code round trip, and the refreshable token written into `auth.json` | pi does not reuse `~/.codex/auth.json` and `CODEX_HOME` appears nowhere in pi's source, so an existing codex login does not transfer; token refresh rewrites `auth.json`, which must stay writable and out of the store |
| Anthropic Claude Pro/Max subscription | same `lazyOAuth` subscription shape as the Codex path, `/login` in interactive mode, tokens stored as `{"type":"oauth","access","refresh","expires"}` in `auth.json` | nothing beyond provider and model selection in settings | the OAuth flow and the stored refreshable token | same as above; a nix-managed `auth.json` would be both wrong (pi rewrites it) and unsafe (credential material in a world-readable store) |
| API key via sops-nix | `auth.json` `key` values resolve `!command` by executing the whole value and taking stdout (10s timeout, cached for process lifetime) or `$VAR`/`${VAR}` by env interpolation; alternatively the provider's env var from the 36-entry `getApiKeyEnvVars` map | fully declarable: a sops template can render an `auth.json` fragment, or a `!cat /run/secrets/...` indirection can be nix-generated while the plaintext never enters the store | none | the vanixiets idiom is either a build-time `sops.templates` render with `sops.placeholder`, or a runtime `cat ${config.sops.secrets.<n>.path}` inside a wrapper; the latter keeps plaintext out of the store and is the shape used for the glm and cerebras claude-code wrappers |

Mic92's clan deployment contributes a fourth shape worth noting: a `clan.core.vars` generator exposed as a systemd credential, resolved at agent runtime by a generated mock `rbw` shim so the same `!rbw get <name>` string works on a workstation and inside a container.
That indirection is only relevant if pi is ever deployed server-side; for the darwin workstation fleet, sops-nix is the established path and no clan-vars route into home-manager scope exists on darwin at all.

## Extensions

rytswd/pi-agent-extensions is a flat, buildless collection of eight self-contained TypeScript extensions, MIT-licensed, declared through a single `pi.extensions` array in the root `package.json`.
There is no build step because pi loads TypeScript through jiti, and every `@mariozechner/*` and `@earendil-works/*` import the extensions use is injected by pi as a virtual module or jiti alias rather than resolved from `node_modules`.
Registering the repo as a local-path package in `settings.json` is a pure read-only file reference: pi stats the path, reads the manifest, and registers the resolved file paths, running no npm and touching no network.
Only `pi install git:...` is imperative, cloning the repo and running `npm install` inside the clone.

The cheapest viable approach is therefore a `pkgs/by-name/pi-agent-extensions` `fetchFromGitHub` pinned by rev, delivered either as a single `packages` entry in the nix-generated `settings.json` pointing at the store path, or as per-extension `home.file` symlinks into `~/.pi/agent/extensions/`.
The `packages` entry is cheaper (one settings key rather than eight file entries) but writes a store path into a file pi also rewrites; the per-extension symlinks are more in keeping with how vanixiets fans skills out and keep the store path out of mutable JSON.
Only the `fetch` extension has a real npm dependency (`@mozilla/readability` plus `jsdom`), lazily imported inside a try/catch with a documented regex fallback, so if Readability mode is not required the whole repo is a pure file copy with nothing to vendor.
Note the repo's own README contradicts its code in three places (slow-mode's `diff` dependency, statusline's config directory, direnv's mechanism), so the code is the authority.

A different extension has since been packaged and enabled: `pi-openai-server-compaction` from github.com/algal/pi-openai-server-compaction, MIT-licensed, pinned at rev `8a3de2f3b0c178fdd6f73f2f94172dfc3943e466` dated 2026-07-23.
It is packaged at `pkgs/by-name/pi-openai-server-compaction/package.nix` as a bare `fetchFromGitHub` source and registered through `programs.pi-coding-agent.settings.packages` in the pi module.
It declares `"pi": {"extensions": ["./src/index.ts"]}`, and registration by local path is the same pure read-only file reference described above: no npm install, no network, and no build step.

Its capability matrix differs by provider, and that difference is the central fact about it.
For `openai/*` models reached with an api.openai.com key it offers remote compaction, `previous_response_id` continuity, and a custom WebSocket stream.
For `openai-codex/*` models on a ChatGPT subscription it offers remote compaction only; `previous_response_id` continuity and the custom WebSocket stream are both deliberately excluded, and pi's built-in transport is retained.
The upstream README states this at `README.md:47-51`.

The mechanism on the Codex path runs in two steps.
At a compaction boundary `session_before_compact` triggers an out-of-band POST to `https://chatgpt.com/backend-api/codex/responses` carrying `store: false`, an `x-codex-beta-features: remote_compaction_v2` header, codex identity headers, and a `{type: "compaction_trigger"}` input item, which returns an opaque compaction artifact.
`before_provider_request` then replaces the replayed conversation with the reconstructed history via `applyRemoteHistoryPayloadPatch`.

`applyPayloadPatch`, which sets `store = true` and `context_management`, is never reached on the Codex path, because `src/index.ts` returns early inside an `isOpenAICodexResponsesModel` branch.
That matters because pi hardcodes `store: false` for codex, and upstream's own comment records that the ChatGPT backend rejects `store: true` with "Store must be set to false".
The guard is structural rather than semantic: it is an early return, and `supportsStore()` itself would return `true` for codex models, since pi's codex model definitions carry no `compat` block.
A refactor removing the early return would not be caught by anything else.

`ws` is deliberately not vendored.
It is imported lazily, and the WebSocket path is unreachable on the Codex provider, gated at `src/custom-stream.ts:26` and `src/openai-ws-stream.ts:786`.
Were it ever reached, a failed import is caught and degrades to SSE unless the transport is explicitly `"websocket"`.

The extension declares a pi peer range of `>=0.80.9 <0.81.0`, while the fleet evaluates and deploys pi 0.84.1 outside that declared range.
The source anchor is `peerDependencies` in Algal's `package.json` at audited revision `8a3de2f3b0c178fdd6f73f2f94172dfc3943e466`, which applies that range to `@earendil-works/pi-coding-agent`, `pi-ai`, and `pi-agent-core`.
At the same Algal revision, `generateBestEffortLocalSummary` in `src/remote-compaction.ts` catches failure from `generatePortableSummary` and calls `compact` with `preparation`, `model`, `apiKey`, `headers`, `customInstructions`, `signal`, and `thinkingLevel`, in that order.
The audited `@earendil-works/pi-coding-agent` package identifies itself as version 0.84.1 in `package.json`; its exported `compact` declaration in `dist/core/compaction/compaction.d.ts` retains those same first seven parameters in the same order.
The fallback can therefore execute when portable summarization throws, but matching argument order does not establish broader live compatibility, so API drift outside the declared peer range remains a calibrated risk.

This analysis is a source trace only, and one claim is unverified in consequence.
No live request was made to either backend, so the ChatGPT backend's acceptance of the `compaction_trigger` input item and the `remote_compaction_v2` beta header is inferred from code intent plus the author's `VALIDATION.md` claim of a passing live suite against `openai-codex/gpt-5.6-sol`.
That flag is undocumented and server-gated; if it is withdrawn, the extension warns and falls back to pi's built-in compaction rather than failing hard.

The kunchenguid `-axi` repos are not pi extensions at all.
`gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `quota-axi`, and `tasks-axi` are standalone Node CLIs built to an "Agent eXperience Interface" convention (TOON-encoded output, contextual next-step suggestions, idempotent mutations), each depending on `axi-sdk-js` and each shipping an Agent Skills `SKILL.md` alongside the binary.
`no-mistakes` and `treehouse` are Go binaries, and only `treehouse` carries a flake exposing a `buildGoModule` package for four systems.
The right decomposition for these is to deliver the skill files through the existing apm pipeline and, if the binaries are wanted, package them individually — `treehouse` as a flake input, `no-mistakes` as a `buildGoModule` derivation, the `-axi` CLIs as `buildNpmPackage`.
Their `<tool> setup hooks` subcommand mutates the user's agent `settings.json` out of band and must never be run; vanixiets should emit any wanted hook entries declaratively instead.

## Skills integration

pi needs no new skills sink, and the earlier recommendation to make it the sixth delivery target of the apm pipeline is withdrawn.
pi already scans `~/.agents/skills` as a global discovery root, registered at `package-manager.ts:2375` and deliberately placed outside the project-trust gate, and it follows symlinks.
The nix cost is therefore zero: the existing home-manager delivery to `~/.agents/skills` already reaches pi with no module change at all.
Verified in the earlier packaged-binary pass: pi run from cwd `/tmp` with `--no-approve` enumerated 127 skills, every one of them reporting a location under `/Users/crs58/.agents/skills/`; this probe was not rerun against pi 0.84.1.
Nothing upstream changes either: the compose derivation, `apmTargets`, the plugin layout, each `apm.yml` and `plugin.json`, and `.github/plugin/marketplace.json` are all harness-agnostic, and apm 0.27.0 has no `pi` target.

Do not add `~/.pi/agent/skills` as a second sink.
Discovery roots carry a precedence rank — project-local 0, project-auto 1, user-local 2, user-auto 3, package 4 — and on a name collision the `.pi` copy wins, so a second sink would shadow the `.agents` tree and dedupe silently, serving the same content from a path the rest of the fleet does not share.

The `settings.json` `skills` array adds to the discovered defaults rather than replacing them, verified empirically.
No settings entry is required to pick up `~/.agents/skills`, so the array is available for adding roots rather than serving as a cheaper substitute for the existing delivery.

The `SKILL.md` format is compatible — pi implements the same Agent Skills standard the tree already targets — but pi imposes validation the other harnesses do not.
Skill names must match `^[a-z0-9-]+$`, be at most 64 characters, and carry no leading, trailing, or consecutive hyphens; a skill with an empty or missing `description` is silently dropped rather than warned about; descriptions over 1024 characters warn.
pi also honours `.gitignore`, `.ignore`, and `.fdignore` files found inside the scanned tree and skips any entry whose name starts with a dot, so a per-skill ignore file would silently drop content.
Unlike codex, pi explicitly follows symlinks for both directory entries and `SKILL.md` leaves, so it is indifferent to whether the `~/.agents/skills` tree is delivered as symlinks or as the real-file activation copy that sink already requires for other consumers.

That validation surfaces a latent defect in this repository's own skill sources.
Of 168 delivered skill directories, pi surfaces 127.
Thirty-nine of the remaining 41 carry `disable-model-invocation: true`, which is intended behaviour and not a defect.
The other two have malformed YAML frontmatter that strict parsers reject: `meta-orchestrator-checkpoint` has a bare colon-space inside an unquoted plain scalar in its description, and `meta-session-resume` has two juxtaposed flow sequences in `argument-hint: [session-uuid] [nohist]`.
Claude Code's parser tolerates both and lists them normally, while pi drops them silently.
This is a portability defect affecting any strict-parsing harness rather than a pi-specific quirk, and it is worth fixing independently of whether pi is adopted.
All 128 first-party `SKILL.md` files do carry a non-empty description, so nothing is lost to pi's empty-description drop rule.

## Proposed module layering

Create `modules/home/ai/pi/default.nix` as a home-manager module writing `flake.modules.homeManager.ai`, enabling `programs.pi-coding-agent`, pointing `package` at the llm-agents attribute, setting `models`, and declaring a `managedConfigs` entry for `settings.json`.
This is the only strictly required new file; the `ai` aggregate is auto-discovered by import-tree and already listed in crs58's `aggregates`, so no registration step exists.

Modify `modules/home/modules/agents-md.nix` to add a `.pi/agent/AGENTS.md` destination, if the decision is to route pi's global instructions through the unified generator rather than `programs.pi-coding-agent.context`; the two are mutually exclusive because the absolute and relative keys normalize to the same target and trip home-manager's duplicate-target assertion.
That file holds the destination map, and it currently carries seven destinations rather than the five CLAUDE.md claims: `.claude/CLAUDE.md`, `.codex/AGENTS.md`, `.factory/AGENTS.md`, `.gemini/GEMINI.md`, `.hermes/SOUL.md`, `crush/CRUSH.md`, and `opencode/AGENTS.md`.

Modify `modules/home/modules/agents-md.test.nix` in the same change, because the nix-unit check asserts the exact sorted attribute-name lists of both `home.file` and `xdg.configFile` and therefore fails on addition, not only on removal.

Optionally create `pkgs/by-name/pi-agent-extensions/package.nix` as a `fetchFromGitHub` pin if the rytswd extensions are wanted, following the `agent-plugins/*` precedent of a bare source fetch consumed by store path.

Optionally modify `modules/home/users/crs58/default.nix` to declare any new sops secret pi needs, and `.sops.yaml` if a new path regex is required; note that every `config.sops.secrets.<n>` reference in the `ai` aggregate is unguarded and the aggregate is currently crs58-only.

No change is needed to `modules/home/ai/skills/default.nix`, because pi reads `~/.agents/skills` directly and the skills pipeline is untouched by this integration.
Nor is any change needed to `pkgs/by-name/apm-skills-compose/package.nix`, `modules/home/ai/skills/compose.nix`, any plugin `apm.yml` or `plugin.json`, `.github/plugin/marketplace.json`, `modules/home/tools/agents-md.nix` (content only), or any user `meta.nix`.

## Verification methods and environment state

Two methods produced the verified claims above.
The first is an independent source trace that follows each call chain from the CLI entry point down to the layer that supplies the value, rather than reading a default list at the layer that declares it.
The second was an empirical run of an earlier packaged pi binary: enumerating discovered skills from a neutral cwd, planting control files under an overridden `HOME`, planting unknown settings keys to observe whether they take effect or warn, and inlining an oversized context file to test for truncation.
Those empirical observations were not rerun against the currently evaluated and deployed pi 0.84.1 package.

That empirical work left one artifact on the machine.
An empty `/Users/crs58/.pi/agent/auth.json` exists, created 2026-08-06 as a byproduct of the investigation.
It is inert: pi creates exactly that file on its first run, so the state is indistinguishable from what any first invocation would produce.

## Risks, gotchas, and contradictions

Two reconnaissance passes disagree about what nixpkgs' `pi-coding-agent` builds from: one reports `fetchFromGitHub` at the version tag with a separately fetched model catalog, the other reports the `@earendil-works/pi-ai` npm tarball.
Both agree it is a different artifact from llm-agents' `pi`, and both reported the same then-current version, so the disagreement does not change the recommendation but should be resolved before anyone cites the nixpkgs derivation's provenance.

The contradiction over whether pi reads `~/.agents/skills` is resolved: it does.
The negative claim rested on `skills.ts`, whose `loadSkills()` carries an `includeDefaults: true` branch hardcoding only `<agentDir>/skills` and `<cwd>/.pi/skills` — a branch the CLI never takes.
The sole production caller, `ResourceLoader.updateSkillsFromPaths()`, passes `includeDefaults: false` at `resource-loader.ts:680` and supplies its paths from the package manager, which registers `~/.agents/skills` at `package-manager.ts:2375`.
The hardcoded default list is reachable only by SDK consumers.
The reusable lesson is that a default list read at the layer that declares it can be dead code at the layer that runs; trace the call chain to the caller that actually supplies the value before treating a declared default as behaviour.

The related asymmetry between the two discovery mechanisms is a standing gotcha rather than an open question: skills discovery stops at the git root and is trust-gated, while context-file discovery walks to the filesystem root and is not.

A firstmate document asserts that pi's `openai-codex` family "authenticates through the Codex store that the `codex` provider already lists"; pi's source at 0.84.0 contradicts this, with its own `auth.json` and no `CODEX_HOME` reference anywhere in `packages/`.
Treat the firstmate claim as an upstream documentation error unless 0.82.0-era behaviour is shown to differ.

Version skew runs through the whole corpus.
The source clone used by the earlier reconnaissance was at HEAD `4e64de6`, after the 0.84.0 tag with an `[Unreleased]` changelog section while `package.json` still read 0.84.0; the fleet now evaluates and deploys pi 0.84.1; the kunchenguid and firstmate documentation pins its claims to 0.82.0.
The behavioural claims exercised empirically are confirmed only against the earlier packaged binary and are marked as such where they appear; they were not rerun against pi 0.84.1.
Claims resting on changelog entries alone remain unconfirmed by source diff, because the `~/ghq` clones used for the reconnaissance were shallow and blobless, so history and blame were unavailable.
The `AGENTS.override.md` verdict is the concrete instance: its absence was observed in the earlier packaged-binary pass, while its 0.84.0 introduction rests on the changelog.

The jiti transpile cache is no longer an open hazard.
pi's extension loader calls `createJiti` with `moduleCache: false` and does not pass `fsCache: false`, but the on-disk cache directory derives from pi's own `import.meta.url` rather than from the path of the loaded extension.
Vendoring `node_modules` anywhere inside an extension therefore has no effect on caching, and the earlier concern recorded here — that vendoring beside the entry point would silently disable the cache — was wrong.

Relatedly, the CLAUDE.md sentence describing beads as "overriding the llm-agents version" is mechanically imprecise: llm-agents is never overlaid into `pkgs`, and the override is positional precedence against nixpkgs from the right-biased merge in `modules/nixpkgs/compose.nix`.
CLAUDE.md's counts are also stale — it says 17 apm packages and roughly 115 skills where the tree holds 18 package directories and 128 first-party `SKILL.md` files.

Separately, `modules/apps/apm-marketplace-validate.sh:118` reads `${repo_root}/.claude-plugin/marketplace.json`, a path that does not exist; the manifest is at `.github/plugin/marketplace.json`.
That app is not run by `nix flake check`, so the defect is currently latent.

Finally, pi has no MCP and no hooks, and the vanixiets claude-code module carries fifteen MCP server definitions and a hook suite.
Adopting pi means those do not transfer, and bridging MCP would require writing and maintaining a pi extension.

## Decisions taken and questions remaining

Five of the questions this note originally posed are settled by the landed implementation in `modules/home/ai/pi/default.nix`, and are recorded here as decisions rather than as choices.

Package source: the llm-agents attribute, `flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi`, rather than nixpkgs' `pi-coding-agent`.

Settings delivery: nix-seeded-then-mutable, through `managedConfigs.pi-settings`.
Its `replacesHomeFile` disables the upstream `home.file` entry on the absolute `"${cfg.configDir}/settings.json"` key, and its activation step rewrites the file from `programs.pi-coding-agent.settings`, so the seeded keys — `theme`, `enableInstallTelemetry = false`, and the `packages` array — are refreshed on every activation.
The fork is scoped to `settings.json`, since pi has no writer for `keybindings.json` or `models.json`.

Instruction file: the upstream `programs.pi-coding-agent.context` option, fed from `config.programs.agents-md.settings.text`, which writes `AGENTS.md` into `configDir`.
`modules/home/modules/agents-md.nix` therefore gains no `.pi/agent/AGENTS.md` destination and its pinned nix-unit expectation is unchanged.

Skills delivery: unchanged, as this note already concluded.
pi reads `~/.agents/skills` directly, the existing delivery already reaches it, and no second sink is declared.

Module scope: self-enabling.
The module sets `enable = true` unconditionally inside `flake.modules.homeManager.ai`, so every user carrying the `ai` aggregate gets pi; the aggregate is currently crs58-only.

Extensions are settled for `pi-openai-server-compaction` and open for the rest.
That extension is delivered as a `pkgs/by-name` source pin registered through the `packages` settings key, the cheaper of the two routes weighed above.
Whether to bring in rytswd/pi-agent-extensions at all, and whether any of the kunchenguid `-axi` tools are in scope, remain open.

Drive-by cleanup: fix the stale beads overlay references, the CLAUDE.md counts and override wording, the CLAUDE.md claim of five agents-md destinations, and the `apm-marketplace-validate.sh` manifest path as part of this change, or file them separately?
The same question applies to the two malformed `SKILL.md` frontmatter blocks in `meta-orchestrator-checkpoint` and `meta-session-resume`, which are a portability defect independent of pi adoption.

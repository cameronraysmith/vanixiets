# Pin apm dependencies in apm.yml Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write each remote apm dependency's commit only in the declaring plugin's `apm.yml`, download all of them in one guarded fixed-output derivation, compose offline from it, consume superpowers and agency per skill directory, and align every CLI with its agent skill by commit.

**Architecture:** A pure evaluation-time guard parses the committed plugin manifests, enforces full-SHA and same-ref rules, and digests the remote entries plus apm's version into the name of `apm-deps-<digest>`, a fixed-output derivation that runs `apm lock`. `apm-skills-compose` becomes a plain offline `apm install` over that output. A structural check module compares each aligned CLI's recorded release commit with the guard's parsed ref.

**Tech Stack:** Nix (flake-parts, import-tree), apm 0.36.x from `llm-agents` (`modules/nixpkgs/overlays/apm.nix`), nix-unit via `flake.lib.mkEvalCheck`, `flake.lib.mkStructuralCheck`.

**Spec:** `openspec/changes/pin-apm-dependencies-in-apm-yml/specs/third-party-plugin-dependency/spec.md`, with `design.md` (D1-D8) and `tasks.md` in the same directory.

## Global Constraints

- Every remote `ref` is a 40-character lowercase hex SHA (`^[0-9a-f]{40}$`).
- superpowers commit `22f0b463e7a5e579904dd6211a520321035526f7` (v7.0.2), 15 skills: `brainstorming`, `diagnosing-superpowers`, `dispatching-parallel-agents`, `executing-plans`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`, `writing-skills`.
- agency commit `81455051ccca654c57ad6088838c85e7248ac159`, skills `hickey`, `lowy`, `fact-check` under `.apm/skills/`.
- Release commits: mergify-cli `e7c1ebbc281361f0b2b7827cf583f57339c97ebc` (`2026.9.16.1`), linear-cli `02571d34be662e5487204841fb80bf23ed79b4f0` (`v3.1.0`), worktrunk `e42f0f6fef2fdbd98fc92e5cd6c3cbea55b65b38` (`v0.81.0`), gh-stack `2a49e6751238633db504655d8a8eba3e433e827d` (`v0.3.0`), playwright-cli `playwright-cli.src.rev` (unchanged).
- apm targets for both the download and the compose: `agent-skills,claude`.
- The download needs `cacert`, full `git` and a writable `HOME`; the compose needs no git and no network.
- No import-from-derivation in the guard: only `builtins.readDir`, `builtins.readFile`, `builtins.pathExists` on source paths and `apm.version`.
- Structural checks exist on `x86_64-linux` only and have static key sets.
- jj development join: edit through the shared `@`, route finished hunks into the change's chain with `jj squash --into <chain> --use-destination-message --keep-emptied <paths>`; never `jj edit`, never move `@`.
- Verification is by `nix eval`, `nix build` or the activated path, never by reading source.

## File Structure

| Path | Responsibility |
|---|---|
| `pkgs/by-name/apm-skills-compose/guard.nix` (create) | Parse plugin manifests, enforce SHA and same-ref rules, return `remoteDeps`, `refsByRepo`, `digest` |
| `pkgs/by-name/apm-skills-compose/guard.test.nix` (create) | nix-unit cases for the guard over fixture manifests |
| `pkgs/by-name/apm-skills-compose/deps.nix` (create) | The `apm-deps-<digest>` fixed-output derivation |
| `pkgs/by-name/apm-skills-compose/package.nix` (modify) | Offline consumer; superpowers list rule; `passthru.{deps,guard}` |
| `modules/checks/apm-guard.nix` (create) | Wires `guard.test.nix` through `mkEvalCheck` |
| `modules/checks/structure/cli-skill-release-alignment.nix` (create, replaces `mergify-release-alignment.nix`) | Five pair checks, the gh-stack content-equality fetch, the negative control, playwright parity |
| `modules/nixpkgs/overlays/gh-stack.nix` (create) | `passthru.sourceRev` on nixpkgs' `gh-stack` |
| `pkgs/by-name/{mergify-cli-bin,worktrunk-bin}/{package.nix,update.sh}` (modify) | `passthru.sourceRev`; updater rewrites it and the `apm.yml` ref |
| `modules/home/ai/plugins/*/apm.yml` (modify) | Per-skill lines, moved refs, rewritten comments |
| `modules/home/ai/skills/compose.nix`, `default.nix`, `modules/home/ai/claude-code/default.nix` (modify) | Remove source options and stale comments |
| `pkgs/by-name/agent-plugins/{8 dirs}` (delete) | Retired fetchers |
| `modules/home/ai/plugins/README.md` (modify) | Marketplace and bump documentation |

---

### Task 0: Probe the two unverified premises (tasks 1.1, 4.1)

Both premises are external facts the later tasks build on; each probe fails visibly, and a failure stops the dependent work and is reported rather than worked around.

- [ ] **Step 1: GitHub blobless fetch by SHA inside a fixed-output sandbox** (world assumption A141). Build, on magnetite and on stibnite:

```bash
nix build --impure --no-link --print-out-paths -L --expr '
  let p = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.${builtins.currentSystem}; in
  p.runCommand "probe-blobless-fetch" {
    nativeBuildInputs = [ p.git p.cacert ];
    outputHashMode = "recursive"; outputHashAlgo = "sha256"; outputHash = p.lib.fakeHash;
  } "export HOME=$TMPDIR; git init -q r; git -C r fetch -q --depth 1 --filter=blob:none https://github.com/obra/superpowers 22f0b463e7a5e579904dd6211a520321035526f7; git -C r ls-tree --name-only 22f0b463e7a5e579904dd6211a520321035526f7 skills/ > $out"'
```

Expected: the build fails only with `hash mismatch … got: sha256-…`; set `outputHash` to that value, rebuild, and `cat` the output: the 15 `skills/<name>` lines from Global Constraints. Any other failure (a fetch error) stops Task 3 Step 1's superpowers-list block; report it.
- [ ] **Step 2: gh-stack tag fetch and commit fetch share one NAR hash** (design D6).
Run: `nix build --impure --no-link --expr 'let p = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.${builtins.currentSystem}; in p.fetchFromGitHub { owner = "github"; repo = "gh-stack"; rev = "2a49e6751238633db504655d8a8eba3e433e827d"; hash = p.gh-stack.src.outputHash; }'`
Expected: PASS. A hash mismatch stops the gh-stack half of Tasks 5 and 6; report it.
- [ ] **Step 3:** Save both outputs to `logs/apm-deps-probes-<date>.log`. Nothing is committed.

### Task 1: Guard (tasks 1.2)

**Files:**
- Create: `pkgs/by-name/apm-skills-compose/guard.nix`
- Create: `pkgs/by-name/apm-skills-compose/guard.test.nix`
- Create: `modules/checks/apm-guard.nix`

**Interfaces:**
- Produces: `import ./guard.nix { inherit lib; } { manifests; apmVersion; }`, where `manifests` maps a plugin name to its `apm.yml` text, returns `{ remoteDeps; refsByRepo; digest; }`. `remoteDeps` is a list of `{ plugin; repo; path; ref; <other keys verbatim>; }` where `repo` is `owner/name` and `path` is the virtual subdirectory or `null`. `refsByRepo` is an attrset `"owner/name" -> [ ref ... ]` (deduplicated, sorted). `digest` is 32 hex characters. Discovery and `readFile` happen in the caller (Task 3), so the guard is a pure function of strings and its tests need no fixture trees.

- [ ] **Step 1: Write the failing tests.** Each case passes manifest texts directly.

```nix
# pkgs/by-name/apm-skills-compose/guard.test.nix — evaluated by nix-unit through mkEvalCheck
{ lib }:
let
  guardFor = manifests: import ./guard.nix { inherit lib; } { apmVersion = "0.36.0"; inherit manifests; };
  sha = "22f0b463e7a5e579904dd6211a520321035526f7";
  sha2 = "b36e0829c6d0140e93cfef2ca599b1b07d4a7797";
  wrap = body: "name: p\nversion: 0.0.0\ndependencies:\n  apm:\n${body}devDependencies:\n  apm:\n    - x/y#main\n";
in
{
  testStringAndObjectForms = {
    expr = map (d: { inherit (d) repo path ref; }) (guardFor { p = wrap ''
      # comment
          - obra/superpowers/skills/brainstorming#${sha}  # trailing
          - git: srid/agency
            path: .apm/skills/hickey
            ref: ${sha}
          - ./local
    ''; }).remoteDeps;
    expected = [
      { repo = "obra/superpowers"; path = "skills/brainstorming"; ref = sha; }
      { repo = "srid/agency"; path = ".apm/skills/hickey"; ref = sha; }
    ];
  };
  testBranchRefThrows = {
    expr = (guardFor { p = wrap "    - theclaymethod/unslop#main\n"; }).digest;
    expectedError = { type = "ThrownError"; msg = "is not a full 40-char commit SHA"; };
  };
  testFlowMappingThrows = {
    expr = (guardFor { p = wrap "    - {git: a/b, ref: ${sha}}\n"; }).digest;
    expectedError = { type = "ThrownError"; msg = "unrecognised"; };
  };
  testMixedSuperpowersRefsThrow = {
    expr = (guardFor { p = wrap "    - obra/superpowers/skills/a#${sha}\n    - obra/superpowers/skills/b#${sha2}\n"; }).digest;
    expectedError = { type = "ThrownError"; msg = "more than one ref"; };
  };
  testWholeSuperpowersThrows = {
    expr = (guardFor { p = wrap "    - obra/superpowers#${sha}\n"; }).digest;
    expectedError = { type = "ThrownError"; msg = "skill-directory path"; };
  };
  testAgencyPathShapeThrows = {
    expr = (guardFor { p = wrap "    - srid/agency/skills/hickey#${sha}\n"; }).digest;
    expectedError = { type = "ThrownError"; msg = "not exactly one skill directory"; };
  };
  testCommentsAndOrderDoNotChangeDigest = {
    expr = (guardFor { p = wrap "    - a/b#${sha}\n    - c/d#${sha}\n"; }).digest
      == (guardFor { p = wrap "    # x\n    - c/d#${sha}\n    - a/b#${sha}  # y\n"; }).digest;
    expected = true;
  };
  testSkillsKeyChangesDigest = {
    expr = (guardFor { p = wrap "    - git: a/b\n      ref: ${sha}\n      skills: [x]\n"; }).digest
      == (guardFor { p = wrap "    - git: a/b\n      ref: ${sha}\n      skills: [x, y]\n"; }).digest;
    expected = false;
  };
}
```

```nix
# modules/checks/apm-guard.nix
{ self, lib, ... }:
{
  perSystem = { pkgs, system, ... }: {
    checks = lib.optionalAttrs (system == "x86_64-linux") {
      apm-guard = self.lib.mkEvalCheck pkgs {
        name = "apm-guard";
        testFile = pkgs.writeText "apm-guard.tests.nix" ''
          import ${../../pkgs/by-name/apm-skills-compose/guard.test.nix} {
            lib = import ${pkgs.path}/lib;
          }
        '';
      };
    };
  };
}
```

- [ ] **Step 2: Run the tests to verify they fail.**
Run: `nix build .#checks.x86_64-linux.apm-guard --no-link -L`
Expected: FAIL, `guard.nix` does not exist.

- [ ] **Step 3: Write the guard.** Start from the verified prototype (`/tmp/apm-verify.mG6t/guard.nix`, 98 lines, proved in `logs/apm-verify-guard-*-20261118-*.log`) and add the repo/path split and the same-ref rules:

```nix
# pkgs/by-name/apm-skills-compose/guard.nix
# Evaluation-time guard for the apm-deps fixed-output derivation (design D2, D3).
# Pure over manifest texts; callers read the committed files with readDir/readFile, so no IFD.
{ lib }:
{ manifests, apmVersion }:
let
  fail = plugin: msg: throw "apm-deps guard: ${plugin}/apm.yml: ${msg}";

  depLines = text:
    let
      meaningful = builtins.filter (l: builtins.match " *(#.*)?" l == null) (lib.splitString "\n" text);
      go = s: l:
        if builtins.match "[^ ].*" l != null then s // { inDeps = l == "dependencies:"; inApm = false; }
        else if s.inDeps && builtins.match "  [^ ].*" l != null then s // { inApm = l == "  apm:"; }
        else if s.inDeps && s.inApm then s // { acc = s.acc ++ [ l ]; }
        else s;
    in (lib.foldl' go { inDeps = false; inApm = false; acc = [ ]; } meaningful).acc;

  uncomment = l: let m = builtins.match "(.*[^ ])[ ]+#.*" l; in if m == null then l else lib.head m;

  entries = plugin: lib.foldl' (acc: raw:
    let
      l = uncomment raw;
      item = builtins.match "    - (.*)" l;
      kv = builtins.match "      ([a-z_]+): (.*)" l;
      firstKv = if item == null then null else builtins.match "([a-z_]+): (.*)" (lib.head item);
    in
    if item != null && firstKv != null then acc ++ [ { ${lib.elemAt firstKv 0} = lib.elemAt firstKv 1; } ]
    else if item != null && builtins.match "[{\\[\"'].*" (lib.head item) != null
    then fail plugin "unrecognised dependencies.apm line: '${raw}'"
    else if item != null then acc ++ [ { spec = lib.head item; } ]
    else if kv != null && acc != [ ] then lib.init acc ++ [ (lib.last acc // { ${lib.elemAt kv 0} = lib.elemAt kv 1; }) ]
    else fail plugin "unrecognised dependencies.apm line: '${raw}'") [ ];

  isLocal = e: e ? spec && builtins.match "\\.{1,2}/.*" e.spec != null;

  # "owner/name[/path...]" -> { repo; path; }
  splitRepo = s: let p = builtins.match "([^/]+/[^/]+)(/(.+))?" s; in
    { repo = lib.elemAt p 0; path = lib.elemAt p 2; };

  normalise = plugin: e:
    let
      sh = if e ? spec then builtins.match "([^#]+)#(.+)" e.spec else null;
      n =
        if e ? spec then (if sh == null then fail plugin "remote dep '${e.spec}' has no #ref"
                          else splitRepo (lib.elemAt sh 0) // { ref = lib.elemAt sh 1; })
        else if e ? git then (removeAttrs e [ "git" ]) // splitRepo e.git
                             // { path = e.path or null; ref = e.ref or (fail plugin "remote dep '${e.git}' has no ref:"); }
        else fail plugin "unrecognised remote dep entry ${builtins.toJSON e}";
    in
    if builtins.match "[0-9a-f]{40}" n.ref == null
    then fail plugin "remote dep '${n.repo}' ref '${n.ref}' is not a full 40-char commit SHA"
    else n // { inherit plugin; };

  remoteDeps = lib.concatLists (lib.mapAttrsToList (plugin: text:
    map (normalise plugin) (builtins.filter (e: !isLocal e) (entries plugin (depLines text)))) manifests);

  refsByRepo = lib.mapAttrs (_: ds: lib.unique (lib.sort lib.lessThan (map (d: d.ref) ds)))
    (lib.groupBy (d: d.repo) remoteDeps);

  # Same-ref rules 1-4 (design D3) for the per-skill repositories.
  perSkill = { "obra/superpowers" = "skills/[a-z0-9-]+"; "srid/agency" = "\\.apm/skills/[a-z0-9-]+"; };
  sameRef = lib.all (d:
    if !(perSkill ? ${d.repo}) then true
    else if d.path == null then fail d.plugin "'${d.repo}' must be declared per skill-directory path"
    else if builtins.match perSkill.${d.repo} d.path == null
    then fail d.plugin "'${d.repo}/${d.path}' is not exactly one skill directory"
    else if builtins.length refsByRepo.${d.repo} > 1
    then fail d.plugin "'${d.repo}' has more than one ref: ${toString refsByRepo.${d.repo}}"
    else true) remoteDeps;

  key = { apm = apmVersion; deps = lib.sort (a: b: builtins.toJSON a < builtins.toJSON b) remoteDeps; };
in
assert sameRef;
{
  inherit remoteDeps refsByRepo;
  digest = builtins.substring 0 32 (builtins.hashString "sha256" (builtins.toJSON key));
}
```

- [ ] **Step 4: Run the tests to verify they pass.**
Run: `nix build .#checks.x86_64-linux.apm-guard --no-link -L`
Expected: PASS, all eight cases.

- [ ] **Step 5: Confirm no import-from-derivation over the real tree.**
Run: `nix eval --option allow-import-from-derivation false --raw --impure --expr 'let lib = (builtins.getFlake (toString ./.)).inputs.nixpkgs.lib; d = ./modules/home/ai/plugins; ps = builtins.filter (p: builtins.pathExists (d + "/${p}/apm.yml") && builtins.pathExists (d + "/${p}/.apm/skills")) (builtins.attrNames (builtins.readDir d)); in (import ./pkgs/by-name/apm-skills-compose/guard.nix { inherit lib; } { apmVersion = "0.36.0"; manifests = lib.genAttrs ps (p: builtins.readFile (d + "/${p}/apm.yml")); }).digest'`
Expected before Task 2: a thrown error naming `planning-and-development/apm.yml` and `obra/superpowers` (whole-repository entry), which confirms the same-ref rule bites on today's manifest. After Task 2: a 32-hex digest.

- [ ] **Step 6: Commit.** Route `pkgs/by-name/apm-skills-compose/guard.nix`, `guard.test.nix` and `modules/checks/apm-guard.nix` into the chain with `jj squash --into <chain> --use-destination-message --keep-emptied <paths>`.

### Task 2: Per-skill manifests and moved refs (tasks 3.1, and the manifest halves of 4.3 and 4.4)

**Files:**
- Modify: `modules/home/ai/plugins/planning-and-development/apm.yml`
- Modify: `modules/home/ai/plugins/version-control-and-forge/apm.yml`
- Modify: `modules/home/ai/plugins/preferences-code-and-collaboration-conventions/apm.yml`
- Modify: `modules/home/ai/plugins/preferences-operations-and-reliability/apm.yml`

**Interfaces:**
- Consumes: Task 1's guard.
- Produces: manifests the guard accepts; later tasks read their refs through `guard.refsByRepo`.

- [ ] **Step 1: Replace the superpowers line and the agency block** in `planning-and-development/apm.yml` with:

```yaml
    # superpowers and agency are consumed one skill directory at a time
    # (virtual-subdirectory dependencies), so apm never sees either
    # repository's hooks: apm >=0.36 refuses superpowers' hook pair, and
    # agency's Stop hook would land in consumers' settings. Every line of a
    # repository shares one full 40-char SHA; the apm-deps guard fails
    # evaluation otherwise, and the compose fails if the superpowers list
    # differs from upstream skills/ at that commit.
    - obra/superpowers/skills/brainstorming#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/diagnosing-superpowers#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/dispatching-parallel-agents#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/executing-plans#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/finishing-a-development-branch#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/receiving-code-review#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/requesting-code-review#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/subagent-driven-development#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/systematic-debugging#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/test-driven-development#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/using-git-worktrees#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/using-superpowers#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/verification-before-completion#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/writing-plans#22f0b463e7a5e579904dd6211a520321035526f7
    - obra/superpowers/skills/writing-skills#22f0b463e7a5e579904dd6211a520321035526f7
    - srid/agency/.apm/skills/hickey#81455051ccca654c57ad6088838c85e7248ac159
    - srid/agency/.apm/skills/lowy#81455051ccca654c57ad6088838c85e7248ac159
    - srid/agency/.apm/skills/fact-check#81455051ccca654c57ad6088838c85e7248ac159
```

- [ ] **Step 2: Move the worktrunk ref** in `version-control-and-forge/apm.yml` to `e42f0f6fef2fdbd98fc92e5cd6c3cbea55b65b38` and the gh-stack ref to `2a49e6751238633db504655d8a8eba3e433e827d`.
- [ ] **Step 3: Rewrite every remote-entry comment** in the four manifests that mentions the pre-seed, `fetchFromGitHub`, a drift guard or `D11` to one sentence: the commit is pinned here only; Nix downloads it in `apm-deps`; aligned tools' refs must equal the tool package's recorded release commit (name the check). Keep the worktrunk tag-ancestry note, updated to v0.81.0.
- [ ] **Step 4: Verify the guard accepts the manifests.** Re-run Task 1 Step 5. Expected: a 32-hex digest. Then `nix eval --json --impure --expr '…refsByRepo'` (same expression, `.refsByRepo`) lists exactly one ref for `obra/superpowers` and `srid/agency`.
- [ ] **Step 5: Commit** the four manifests into the chain.

### Task 3: The fixed-output download (tasks 1.3-1.5)

**Files:**
- Create: `pkgs/by-name/apm-skills-compose/deps.nix`
- Modify: `pkgs/by-name/apm-skills-compose/package.nix` (call `deps.nix`, expose `passthru.deps`)

**Interfaces:**
- Consumes: `guard.digest`.
- Produces: `apm-skills-compose.passthru.deps`, a store path with `apm_modules/` and `apm.lock.yaml`; `apmDepsHash` lives in `package.nix` as a function argument default.

- [ ] **Step 1: Write the derivation with an empty hash** (adapted from the verified prototype `/tmp/apm-verify.mG6t/verify2.nix`; ablations S1-S4 in `logs/apm-sandboxlinux-fod-ablate-*`). It always discovers every package, independent of `firstPartyPackages`, so a narrowed home-manager package list cannot change the download's content under an unchanged name.

```nix
# pkgs/by-name/apm-skills-compose/deps.nix
{ lib, runCommand, apm, git, cacert, yq, pluginsDir, apmDepsHash }:
let
  # Same discovery as the compose (every directory with .apm/skills), independent of
  # firstPartyPackages, so a narrowed package list cannot change content under an unchanged name.
  discovered = lib.attrNames (lib.filterAttrs
    (n: t: t == "directory" && builtins.pathExists (pluginsDir + "/${n}/.apm/skills"))
    (builtins.readDir pluginsDir));
  manifests = lib.genAttrs
    (builtins.filter (p: builtins.pathExists (pluginsDir + "/${p}/apm.yml")) discovered)
    (p: builtins.readFile (pluginsDir + "/${p}/apm.yml"));
  guard = import ./guard.nix { inherit lib; } { inherit manifests; apmVersion = apm.version; };
  plugins = builtins.path { path = pluginsDir; name = "apm-plugins"; };
in
runCommand "apm-deps-${guard.digest}" {
  nativeBuildInputs = [ apm git cacert yq ];
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = apmDepsHash;
  passthru = { inherit guard; };
} ''
  export HOME=$TMPDIR/home APM_CACHE_DIR=$TMPDIR/apm-cache APM_E2E_TESTS=1
  mkdir -p "$HOME" w && cd w
  for d in ${plugins}/*/; do
    n=$(basename "$d")
    if [ -d "$d/.apm/skills" ]; then cp -RL "$d" "./$n"; chmod -R u+w "./$n"; fi
  done
  { printf 'name: apm-skills-consumer\nversion: 0.0.0\ntype: skill\ndependencies:\n  apm:\n'
    for d in */; do printf '    - ./%s\n' "''${d%/}"; done
    printf '  mcp: []\n'; } > apm.yml
  apm lock -t agent-skills,claude

  # Design D3, rule 5: the declared superpowers skills equal upstream skills/
  # at the declared commit. Needs network, so it runs here; nothing from this
  # step reaches $out, so the output hash is unaffected.
  sp_ref=${lib.escapeShellArg (lib.head (guard.refsByRepo."obra/superpowers"))}
  declared=${lib.escapeShellArg (lib.concatStringsSep "\n" (lib.sort lib.lessThan (map (d: lib.removePrefix "skills/" d.path)
    (builtins.filter (d: d.repo == "obra/superpowers") guard.remoteDeps))))}
  git init -q "$TMPDIR/sp"
  git -C "$TMPDIR/sp" fetch -q --depth 1 --filter=blob:none https://github.com/obra/superpowers "$sp_ref"
  upstream=$(git -C "$TMPDIR/sp" ls-tree --name-only "$sp_ref" skills/ | sed 's|^skills/||' | LC_ALL=C sort)
  if [ "$declared" != "$upstream" ]; then
    echo "apm-deps: superpowers skills declared in planning-and-development/apm.yml differ from upstream skills/ at $sp_ref:" >&2
    diff <(printf '%s\n' "$declared") <(printf '%s\n' "$upstream") >&2 || true
    exit 1
  fi

  rm -rf apm_modules/_local
  mkdir "$out"
  cp -R apm_modules "$out/apm_modules"
  yq -y 'del(.generated_at, .apm_version) | .dependencies |= map(select(.source != "local"))' \
    apm.lock.yaml > "$out/apm.lock.yaml"
''
```

In `package.nix`, add arguments `git`, `cacert`, `yq`, `apmDepsHash ? lib.fakeHash`, and `deps = callPackage ./deps.nix { pluginsDir = ../../../modules/home/ai/plugins; inherit apmDepsHash; };` (replace `callPackage` with the explicit arguments if `package.nix` is not given `callPackage`).

- [ ] **Step 2: Build to obtain the hash.**
Run: `nix build .#apm-skills-compose.deps --no-link 2>&1 | grep 'got:'`
Expected: FAIL with `hash mismatch … got: sha256-…`. Set `apmDepsHash` to that value.
- [ ] **Step 3: Build and rebuild on both systems.**
Run on stibnite and on magnetite: `nix build .#apm-skills-compose.deps --no-link --print-out-paths && nix build .#apm-skills-compose.deps --no-link --rebuild`
Expected: PASS on both; the same output path name and hash.
- [ ] **Step 4: Prove the guard properties** (tasks 1.5), each mutant reverted after its run, logging to `logs/apm-deps-guard-<date>.log`:
  - ref bump: change the unslop ref to `0f4a07f5…` (any real later commit) without updating `apmDepsHash`; `nix build .#apm-skills-compose.deps` FAILS with `hash mismatch` and a `got:` line, and the derivation name differs from Step 3's.
  - apm version: `nix build --impure --expr 'let f = builtins.getFlake (toString ./.); old = (builtins.getFlake "github:numtide/llm-agents.nix/aca6bfb2440503d090003b1064a44df8a8a54b5f").packages.${builtins.currentSystem}.apm; in (f.packages.${builtins.currentSystem}.apm-skills-compose.override { apm = old; }).deps'` (apm 0.35.1, the llm-agents pin at commit `3b4ee48b6`): the derivation name differs from Step 3's and the build FAILS with `got: sha256-17mz…`.
  - unrelated edits: append a line to a first-party `SKILL.md`, edit a `description:`, add comments, swap two remote entries; `nix eval --raw .#apm-skills-compose.deps.name` is unchanged and `nix build .#apm-skills-compose.deps --dry-run` lists nothing to build.
- [ ] **Step 5: Run the superpowers-list mutant** (tasks 1.4). Delete the `diagnosing-superpowers` line from `planning-and-development/apm.yml`.
Run: `nix build .#apm-skills-compose.deps --no-link -L 2>&1 | tail`
Expected: FAIL with the `apm-deps: superpowers skills declared … differ` message and a diff line `> diagnosing-superpowers`. Restore the line; `nix eval --raw .#apm-skills-compose.deps.name` returns to Step 3's name.
- [ ] **Step 6: Commit** `deps.nix` and `package.nix`.

### Task 4: Offline consumer (tasks 2.1)

**Files:**
- Modify: `pkgs/by-name/apm-skills-compose/package.nix`

**Interfaces:**
- Consumes: `deps` from Task 3.
- Produces: `apm-skills-compose` output with `.claude/skills` and `.agents/skills`; `passthru = { inherit skillNames deps; }`.

- [ ] **Step 1: Record the comparison base.** `BASE=$(nix build "git+file://$PWD?rev=$(jj log -r 'main@origin' --no-graph -T commit_id)#apm-skills-compose" --no-link --print-out-paths)`.
- [ ] **Step 2: Remove** the arguments `superpowersSrc`…`playwrightCli`, `gitMinimal`, `ripgrep`, and the build-script lines from `# Pre-seed apm's git checkout cache` through the replace-ref loop, the playwright drift and parity lines, and the `diff -r -x LICENSE` playwright loop (moved to Task 6).
- [ ] **Step 3: Replace them with:**

```nix
    # Remote apm dependencies come only from the apm-deps fixed-output
    # download (design D1); no git on PATH, so a missing dependency fails
    # instead of fetching. apm reads apm_modules/ and apm.lock.yaml under
    # the install root, not beside the generated manifest.
    cp -R ${deps}/apm_modules "$out/apm_modules"
    cp ${deps}/apm.lock.yaml "$out/apm.lock.yaml"
    chmod -R u+w "$out/apm_modules" "$out/apm.lock.yaml"
```


- [ ] **Step 4: Keep** the `cp ${rootConsumerManifest} ./apm.yml`, the `apm install --root "$out" -t …`, the lock stripping, the expected-files loop and `skillIndexGuard`; drop `gitMinimal` from `nativeBuildInputs` and update `meta.description` to "offline consumer of the apm-deps download". Make the download an argument, `apmDeps ? deps`, used as `${apmDeps}` in Step 3's lines, and expose `passthru.deps = apmDeps`, so a test can substitute it.
- [ ] **Step 5: Build the compose.**
Run: `COMPOSE=$(nix build .#apm-skills-compose --no-link --print-out-paths -L 2>&1 | tee logs/apm-compose-$(date +%Y%m%d-%H%M%S).log | tail -1)`
Expected: PASS once Task 7 Step 5 has regenerated `skills.json` (until then the index guard fails, printing the corrected index, and nothing else fails); the log shows every remote dependency `(cached)`.
- [ ] **Step 6: Withheld-download negative control.**
Run: `nix build --impure --expr 'let f = builtins.getFlake (toString ./.); s = builtins.currentSystem; p = f.packages.${s}; d = p.apm-skills-compose.deps; in p.apm-skills-compose.override { apmDeps = f.inputs.nixpkgs.legacyPackages.${s}.runCommand "deps-without-obra" { } "cp -R ${d} $out; chmod -R u+w $out; rm -rf $out/apm_modules/obra"; }'`
Expected: FAIL with `git executable not found` for the 15 superpowers entries.
- [ ] **Step 7: Commit.**

### Task 5: Release commits and updaters (tasks 4.2-4.4)

**Files:**
- Modify: `pkgs/by-name/mergify-cli-bin/package.nix`, `pkgs/by-name/mergify-cli-bin/update.sh`
- Modify: `pkgs/by-name/worktrunk-bin/package.nix`, `pkgs/by-name/worktrunk-bin/update.sh`
- Create: `modules/nixpkgs/overlays/gh-stack.nix`

**Interfaces:**
- Produces: `pkgs.mergify-cli-bin.sourceRev`, `pkgs.worktrunk-bin.sourceRev`, `pkgs.gh-stack.sourceRev` (40-hex strings).

- [ ] **Step 1:** In both release-binary packages add to `passthru`: `sourceRev = "<commit>";` with a comment "commit the release tag points at; the cli-skill-release-alignment check requires the skill's apm.yml ref to equal it" (mergify `e7c1ebbc281361f0b2b7827cf583f57339c97ebc`, worktrunk `e42f0f6fef2fdbd98fc92e5cd6c3cbea55b65b38`).
- [ ] **Step 2:** In each `update.sh`, after the version is chosen, resolve and rewrite:

```bash
APM_YML="${REPO_ROOT}/modules/home/ai/plugins/version-control-and-forge/apm.yml"
tag_commit="$(git ls-remote "https://github.com/${OWNER_REPO}" "refs/tags/${TAG}^{}" "refs/tags/${TAG}" \
  | awk 'NR==1 || /\^\{\}$/ { c=$1 } END { print c }')"
[[ "$tag_commit" =~ ^[0-9a-f]{40}$ ]] || { echo "error: no commit for tag ${TAG}" >&2; exit 1; }
sed -i'' -e "s/sourceRev = \"[0-9a-f]\{40\}\"/sourceRev = \"${tag_commit}\"/" "$PKG_NIX"
awk -v repo="${OWNER_REPO}" -v sha="${tag_commit}" '
  $1 == "-" && $2 == "git:" { sel = ($3 == repo) }
  sel && $1 == "ref:" { sub(/[0-9a-f]{40}/, sha) }
  { print }' "$APM_YML" > "$APM_YML.tmp" && mv "$APM_YML.tmp" "$APM_YML"
echo "apm.yml ref for ${OWNER_REPO} moved to ${tag_commit}; update apmDepsHash in pkgs/by-name/apm-skills-compose/package.nix from the next build's hash mismatch."
```

with `OWNER_REPO=Mergifyio/mergify-cli`, `TAG=${latest_version}` for mergify and `OWNER_REPO=max-sixty/worktrunk`, `TAG=v${latest_version}` for worktrunk. The awk prefers the peeled `^{}` line when the tag is annotated.
- [ ] **Step 3:** Create the overlay:

```nix
# modules/nixpkgs/overlays/gh-stack.nix
# nixpkgs fetches gh-stack by tag only; record the commit the tag names so the
# cli-skill-release-alignment check can compare the skill's apm.yml ref with it.
# The check refetches github/gh-stack at this commit with nixpkgs' source hash,
# so a nixpkgs bump fails there until this and the apm.yml ref move together.
{ ... }:
{
  nixpkgsOverlays = [
    (_final: prev: {
      gh-stack = prev.gh-stack.overrideAttrs (old: {
        passthru = (old.passthru or { }) // { sourceRev = "2a49e6751238633db504655d8a8eba3e433e827d"; };
      });
    })
  ];
}
```

- [ ] **Step 4: Verify.**
Run: `for p in mergify-cli-bin worktrunk-bin gh-stack; do nix eval --raw .#$p.sourceRev; echo; done`
Expected: the three commits. Run each updater on a scratch copy of the repository at the current release; expected: `jj diff` of the scratch copy is empty for `package.nix` and `apm.yml`.
- [ ] **Step 5: Commit.**

### Task 6: Release-alignment and parity checks (tasks 4.5, 4.6)

**Files:**
- Delete: `modules/checks/structure/mergify-release-alignment.nix`
- Create: `modules/checks/structure/cli-skill-release-alignment.nix`
- Modify: `pkgs/by-name/linear-cli/update.sh` (comment naming the check)

**Interfaces:**
- Consumes: `guard.refsByRepo` via `self'.packages.apm-skills-compose.deps.guard`, the three `sourceRev`s, `linear-cli.skillSrc.rev`, `playwright-cli.src.rev`.

- [ ] **Step 1: Write the module.** The key set is a literal list; values are lazy.

```nix
# modules/checks/structure/cli-skill-release-alignment.nix
# Design D6: for each CLI whose agent skill ships in the same upstream release,
# the skill's apm.yml ref must equal the commit the CLI package records.
{ self, lib, ... }:
{
  perSystem = { pkgs, self', system, ... }:
    let
      refs = self'.packages.apm-skills-compose.deps.guard.refsByRepo;
      refOf = repo: lib.concatStringsSep "," (refs.${repo} or [ "<undeclared>" ]);
      pairs = {
        mergify-cli = { repo = "Mergifyio/mergify-cli"; rev = self'.packages.mergify-cli-bin.sourceRev; };
        linear-cli = { repo = "schpet/linear-cli"; rev = self'.packages.linear-cli.skillSrc.rev; };
        playwright-cli = { repo = "microsoft/playwright-cli"; rev = self'.packages.playwright-cli.src.rev; };
        worktrunk = { repo = "max-sixty/worktrunk"; rev = self'.packages.worktrunk-bin.sourceRev; };
        gh-stack = { repo = "github/gh-stack"; rev = pkgs.gh-stack.sourceRev; };
      };
      # One comparison, shared by the five pair checks and the negative control,
      # so the control exercises exactly the logic the pairs rely on.
      compare = pkgs.writeShellScript "release-alignment-compare" ''
        # usage: compare <label> <declared apm.yml ref> <recorded release commit>
        if [ "$2" != "$3" ]; then
          echo "release alignment: $1: apm.yml ref $2 != recorded release commit $3" >&2
          exit 1
        fi
      '';
      align = name: { repo, rev }: pkgs.runCommand "structure-release-alignment-${name}" { } ''
        ${compare} ${lib.escapeShellArgs [ repo (refOf repo) rev ]}
        touch $out
      '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") (
        lib.mapAttrs' (n: p: lib.nameValuePair "structure-release-alignment-${n}" (align n p)) pairs
        // {
          structure-release-alignment-negative-control = pkgs.runCommand "release-alignment-negative-control" { } ''
            a=1111111111111111111111111111111111111111
            b=2222222222222222222222222222222222222222
            if ${compare} fixture/repo "$a" "$b" 2> err; then
              echo "negative control: comparison accepted unequal fixtures" >&2; exit 1
            fi
            grep -q "$a" err && grep -q "$b" err || { echo "negative control: diagnostic does not name both fixtures" >&2; cat err >&2; exit 1; }
            touch $out
          '';
          structure-release-alignment-gh-stack-tag = pkgs.fetchFromGitHub {
            owner = "github"; repo = "gh-stack";
            rev = pkgs.gh-stack.sourceRev;
            hash = pkgs.gh-stack.src.outputHash;
          };
          structure-playwright-skill-parity = pkgs.runCommand "playwright-skill-parity" { } ''
            for t in .claude .agents; do
              diff -r -x LICENSE ${self'.packages.playwright-cli.src}/skills/playwright-cli \
                ${self'.packages.apm-skills-compose}/$t/skills/playwright-cli
            done
            touch $out
          '';
        }
      );
    };
}
```

The module replaces `mkStructuralCheck` for these pairs because the negative control must invoke the same comparison as a command, which a derivation-producing helper cannot provide.

- [ ] **Step 2: Verify the checks pass.**
Run: `nix build .#checks.x86_64-linux.structure-release-alignment-{mergify-cli,linear-cli,playwright-cli,worktrunk,gh-stack,negative-control,gh-stack-tag} .#checks.x86_64-linux.structure-playwright-skill-parity --no-link`
Expected: PASS.
- [ ] **Step 3: Verify they fail on mutants.** (a) set the worktrunk ref in `version-control-and-forge/apm.yml` back to `b49ca7ee…`: `structure-release-alignment-worktrunk` FAILS with a diff naming both commits; (b) set the overlay's `sourceRev` to `14fc42ed9b6c376a53b2f999f138d3bd26dac546`: `structure-release-alignment-gh-stack-tag` FAILS with a hash mismatch; (c) make the shared comparison always exit 0: the negative control FAILS; (d) override the compose to append a line to `playwright-cli/SKILL.md`: parity FAILS. Revert each.
- [ ] **Step 4: Commit.**

### Task 7: Remove retired fetchers, options, stray locks; regenerate the index (tasks 2.2, 5.1, 6.1, 6.2)

**Files:**
- Delete: `pkgs/by-name/agent-plugins/{superpowers,agency,worktrunk,mattpocock-skills,unslop,gh-stack,greptimedb-dashboard,mergify-cli}/`
- Delete: `modules/home/ai/plugins/planning-and-development/apm.lock.yaml`, `modules/home/ai/plugins/preferences-code-and-collaboration-conventions/apm.lock.yaml`
- Modify: `modules/home/ai/skills/compose.nix`, `modules/home/ai/skills/default.nix`, `modules/home/ai/claude-code/default.nix:146`, `pkgs/by-name/apm-skills-compose/skills.json`

- [ ] **Step 1:** Record `nix eval --raw .#apm-skills-compose.deps.name` and the NAR hash of `COMPOSE` (`nix path-info --json $COMPOSE | jq -r '.[].narHash'`).
- [ ] **Step 2:** Delete the stray locks; repeat Step 1. Expected: both values unchanged (task 6.1).
- [ ] **Step 3:** Delete the eight fetcher directories and the six options with their `override` wiring in `compose.nix`; rewrite the D11/cache-warm comments in `skills/default.nix` and `claude-code/default.nix:146` to say superpowers ships per skill through the apm compose.
- [ ] **Step 4: Verify.**
Run: `nix eval --json .#packages.aarch64-darwin --apply builtins.attrNames | jq -r '.[]' | grep agent-plugins`
Expected: exactly `agent-plugins-cloudflare`, `-cognee`, `-dagster-skills`, `-duckdb-skills`, `-huggingface-skills`, `-ouroboros`.
Run: `nix eval --raw .#darwinConfigurations.stibnite.system.drvPath && nix eval --raw .#nixosConfigurations.pyrite.config.system.build.toplevel.drvPath`
Expected: both print drv paths.
Run: `rg -n 'pre-seed|pre-warm|cache-warm|D11|agent-plugins-(superpowers|agency|worktrunk|mattpocock-skills|unslop|gh-stack|greptimedb-dashboard|mergify-cli)' modules pkgs justfile`
Expected: no output.
- [ ] **Step 5:** `just agents-skills-index`; then `nix build .#apm-skills-compose --no-link`. Expected: PASS; `jq length pkgs/by-name/apm-skills-compose/skills.json` is the composed count; the only new name versus `main@origin` is `diagnosing-superpowers`.
- [ ] **Step 6: Commit.**

### Task 8: Marketplace verification and README (tasks 3.2, 7.1)

- [ ] **Step 1:** After the chain is pushed, in an isolated environment run, for each target `t` in `claude agent-skills cursor codex copilot opencode gemini`:

```bash
W=$(mktemp -d); cd "$W"
printf 'name: m\nversion: 0.0.0\ndependencies:\n  apm:\n    - cameronraysmith/vanixiets/modules/home/ai/plugins/planning-and-development#<pushed-commit>\n' > apm.yml
env -i HOME="$W/h" APM_CACHE_DIR="$W/c" PATH="$(dirname $(command -v apm)):$(dirname $(command -v git)):/usr/bin:/bin" apm install -t "$t"; echo "rc=$?"
find . -path ./apm_modules -prune -o \( -name 'hooks*' -o -name settings.json \) -print
```

Expected: `rc=0` for every target; the 15 superpowers and 3 agency skill names in the target's skills directory; the `find` prints nothing originating from `obra/superpowers` or `srid/agency`. Save the output to `logs/apm-marketplace-<date>.log`.
- [ ] **Step 2:** Edit `modules/home/ai/plugins/README.md` per tasks 7.1, citing the manifest, `deps.nix`, the check module and the Step 1 log.
- [ ] **Step 3:** `direnv exec . prek run --files modules/home/ai/plugins/README.md`. Expected: no `Failed`.
- [ ] **Step 4: Commit.**

### Task 9: Integration verification (tasks 8.1-8.5)

- [ ] **Step 1:** `BASE=$(nix build "git+file://$PWD?rev=$(jj log -r 'main@origin' --no-graph -T commit_id)#apm-skills-compose" --no-link --print-out-paths)`; `diff -r $BASE/.claude/skills $COMPOSE/.claude/skills > logs/apm-compose-diff-<date>.log`, same for `.agents/skills`. Expected: differences only under the superpowers skills (v6.3.0 → v7.0.2, `diagnosing-superpowers` added, the `apm_modules` links gone), `worktrunk`, `wt-switch-create` and `gh-stack`.
- [ ] **Step 2:** `nix build .#darwinConfigurations.stibnite.system .#nixosConfigurations.pyrite.config.system.build.toplevel --no-link`. Expected: PASS.
- [ ] **Step 3:** With the operator's authorization, activate stibnite; dereference `~/.claude/skills` before and after into `logs/` and diff; read every alert or notice posted since activation started and record each with its cause.
- [ ] **Step 4:** Same on pyrite, with the operator's authorization.
- [ ] **Step 5:** After merge: `just agents-relock`; review the root `apm.lock.yaml` diff (per-skill superpowers and agency entries, worktrunk `e42f0f6f…`, gh-stack `2a49e675…`); commit; `just agents-install` exits 0.

## Self-Review

- Spec coverage: commits written once (Tasks 1, 2); guarded download and superpowers-list rule (Tasks 1, 3); offline composition and withheld download (Task 4); per-skill consumption (Tasks 2, 4, 8); same-ref check (Task 1); additive extension (unchanged behavior, covered by Task 9 Step 1's diff); release alignment and negative control (Tasks 5, 6); unmodified upstream skills and playwright parity (Task 6, Task 9 Step 1); bump workflow (Task 5 Step 2, Task 3 Step 4); root lock after merge (Task 9 Step 5).
- The two unverified external premises (GitHub's blobless fetch by SHA in the sandbox; the gh-stack tag and commit fetches sharing a hash) are Task 0, run before anything depends on them. One assumption remains for first run: the remote-entry lines the guard parses today include no shape outside its two forms (Task 2 Step 4 fails visibly if one does).

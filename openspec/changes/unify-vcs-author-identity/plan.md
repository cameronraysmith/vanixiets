# Unify VCS author identity implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Derive every git and jj author in the fleet from the one person record, so no home or Omnigent worker records an empty author and git and jj always agree.

**Architecture:** `flake.lib.vcsAuthor` projects `meta` to `{ name; email; }`; a home-manager module `vcs-author` holds that pair as `vcs.author` (non-empty strings) and sets git and jj `user` from it, defaulting from the home's own profile for human homes.
Worker owners become typed `flake.users` keys, and the NixOS and Darwin adapters set each worker home's `vcs.author` at system level, so worker home-manager never reads `flake.users`.
One fleet obligation, `authorBinding`, regulates every Linux worker's author inside the existing machine checks, and its mutants run once in the `x86_64-linux` inventory check.

**Tech Stack:** Nix (flake-parts, import-tree, home-manager, nix-darwin, clan-core), jj 0.47.1 colocated with git.

**Spec:** `openspec/changes/unify-vcs-author-identity/specs/commit-author-identity/spec.md`, `openspec/changes/unify-vcs-author-identity/specs/commit-author-identity-interface/spec.md`, `openspec/changes/unify-vcs-author-identity/specs/world-assumptions/spec.md`, with `design.md` and `tasks.md` in the same directory.

## Global constraints

- Work in `/home/omnigent-cameron/projects/vanixiets`; it is jj-colocated, so a detached git `HEAD` is normal and must not be reattached.
- One pull request of three commits on the bookmark `unify-vcs-author-identity`: step 1 (D1′ and D2′), step 2 (D3′), step 3 (D4′); it is rebase-merged, so each commit lands on `main` separately while CI builds only the head, and each must leave `main` correct and regulated on its own.
- Janette's `extraHomeModules` author binding and its `identityBinding` obligation stay through step 2 and are removed only in step 3, in the same commit that adds `authorBinding` and its mutants.
- jj commits run no git hooks: run `just lint` before each commit.
- `@` stays an empty working-copy commit atop the chain tip: each step's change is created first with `jj new --no-edit <previous tip> -m "<message>"`, the bookmark moved to it, `@` re-parented with `jj rebase -s @ -d <step change>`, and the step's edits routed into it with `jj squash --into <step change> -u -k -- <paths>`; never `jj commit`, which moves `@`.
- Do not run `nix flake check`, `just check` or `just check-fast`; build only the named checks.
- Workers receive only `vcs.author.name` and `vcs.author.email`; no human module, `contentPrivate`, sops material or age key reaches a worker home, and the `users = throw "worker imported a whole-user alias"` guard in `modules/checks/omnigent-workers.nix` stays.
- `expected.omnigentEmail` stays `meta.email`; signing options, token selection and `defaultOwner` are unchanged.
- No check attribute is added or renamed: `nix eval --json '.#.checks.x86_64-linux' --apply builtins.attrNames` and `nix eval --json '.#.checks.aarch64-darwin' --apply builtins.attrNames` must each be identical before and after.
- `extraHomeModules` stays out of the clan interface.
- Out of scope: the `git.sign-on-push` deprecation in `modules/home/development/jujutsu.nix` and `modules/home/ai/omnigent/worker.nix`; the ubuntu meta duplication.
- Markdown: one sentence per line, sentence-case headings.

## Grounding

These facts were read or evaluated on 2026-11-08 and the steps below depend on them.

- `modules/home/users/aliases-fold.nix` materializes `flake.users.cameron` from crs58's record with only `meta.username` changed; `nix eval --json '.#.users' --apply builtins.attrNames` returns `["cameron","christophersmith","crs58","janettesmith","raquel","tara","ubuntu"]`.
- Every `home-manager.users` name on every NixOS and nix-darwin host is one of those keys or an `omnigent-*` worker account.
- Human homes receive `flake` as `config.flake // { inherit inputs; }` (`modules/home/mk-home.nix:17-20`) or `inputs.self // { inherit inputs; }` (`modules/clan/inventory/services/users/cameron.nix:78-82`), both carrying `lib` and `users`.
- `flake.modules.homeManager.omnigent-worker` (`modules/home/ai/omnigent/worker.nix:90-110`) imports `git` and `jujutsu`, the `content false` variants of `modules/home/development/{git,jujutsu}.nix`, not `development`.
- The NixOS adapter builds worker homes in `home-manager.users` (`modules/nixos/omnigent-host.nix:287-296`); the Darwin adapter builds standalone `homeManagerConfiguration`s with `flake = inputs.self` (`modules/darwin/omnigent-host.nix:103-151`); both bind `flakeConfig` to the flake-parts `config`.
- `modules/checks/machines.nix` names machine checks `nixos-<machine>` and `darwin-<machine>` from the clan inventory and asserts `flake.lib.omnigentFleetObligations.failures` on the configuration each already forces.
- `omnigent-worker-inventory` is `lib.optionalAttrs (system == "x86_64-linux")` and built by `mkStructuralCheck` with every case expected `true` (`modules/checks/omnigent-workers.nix:734-739`).
- `homeConfigurations.<entry>` exposes `extendModules`.
- jj 0.47.1 supports `jj metaedit --update-author`, the `author_name(exact:"")` revset and `jj git push --dry-run`.

## File structure

- Create `modules/home/development/vcs-author.nix`: the `vcs-author` home-manager module and its import into `development`.
- Modify `modules/home/users/lib.nix`: add `flake.lib.vcsAuthor`.
- Modify `modules/home/development/jujutsu.nix`: drop the empty author default.
- Modify `modules/home/users/{crs58,janettesmith,christophersmith,raquel,tara,ubuntu}/default.nix`: drop hand-written author blocks; principal from `config.vcs.author.email`.
- Modify `modules/system/omnigent-worker-options.nix` and `modules/clan/services/omnigent/flake-module.nix`: owner type.
- Modify `modules/home/ai/omnigent/worker.nix`, `modules/nixos/omnigent-host.nix`, `modules/darwin/omnigent-host.nix`: worker author.
- Modify `modules/home/ai/omnigent/credentials.nix`: drop `user.email`.
- Modify `modules/clan/inventory/services/omnigent.nix`: owner-derived credentials, no `janetteAuthor`.
- Modify `modules/lib/omnigent-fleet-obligations.nix`: drop Janette binding and `ownerMeta`; add `authorBound` and `authorBinding`.
- Modify `modules/checks/omnigent-workers.nix`: fixture author; inventory cases.
- Modify `modules/clan/services/omnigent/README.md`, `docs/notes/development/omnigent/deployment-plan.md`.

---

## Task 1: Record the before-state projections

**Files:** none in the repository; output under `$XDG_STATE_HOME/agent-logs/vanixiets/`.

**Interfaces:**
- Produces: `authors-before.json`, `nixos-<host>-before.json`, `darwin-<host>-before.json`, `checks-x86_64-linux-before.json` and `checks-aarch64-darwin-before.json`, compared in Tasks 4, 7 and 10.

- [ ] **Step 1: Create the scratch directory**

```bash
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/agent-logs/vanixiets"
OUT="${XDG_STATE_HOME:-$HOME/.local/state}/agent-logs/vanixiets"
```

- [ ] **Step 2: Project every standalone home's author and signer text**

```bash
nix eval --json '.#.homeConfigurations' --apply 'cs: builtins.mapAttrs (_: c: {
  git = c.config.programs.git.settings.user or null;
  jj = c.config.programs.jujutsu.settings.user or null;
  signers = c.config.sops.templates.allowed_signers.content or c.config.xdg.configFile."git/allowed_signers".text or null;
}) cs' > "$OUT/authors-before.json"
```

Expected: jj `{"email":"","name":""}` for `christophersmith@*`, `raquel@*`, `tara@*` and `ubuntu@x86_64-linux`, and `{"email":"125711642+janetteasmith@users.noreply.github.com","name":""}` for `janettesmith@*`.

- [ ] **Step 3: Project every host-embedded home's author, signer text and signing key, and every worker's expected identity**

```bash
for h in magnetite pyrite galena scheelite cinnabar electrum; do
  nix eval --json ".#.nixosConfigurations.$h.config" --apply 'c: {
    homes = builtins.mapAttrs (_: u: {
      git = u.programs.git.settings.user or null;
      jj = u.programs.jujutsu.settings.user or null;
      signingKey = u.programs.git.signing.key or null;
      signers = u.sops.templates.allowed_signers.content or u.xdg.configFile."git/allowed_signers".text or null;
    }) c.home-manager.users;
    expected = builtins.mapAttrs (_: w: w.credentials.expected) (c.services.omnigent-host.workers or { });
  }' > "$OUT/nixos-$h-before.json"
done
for h in argentum blackphos rosegold stibnite; do
  nix eval --json ".#.darwinConfigurations.$h.config" --apply 'c: {
    homes = builtins.mapAttrs (_: u: {
      git = u.programs.git.settings.user or null;
      jj = u.programs.jujutsu.settings.user or null;
      signingKey = u.programs.git.signing.key or null;
      signers = u.sops.templates.allowed_signers.content or u.xdg.configFile."git/allowed_signers".text or null;
    }) c.home-manager.users;
    expected = builtins.mapAttrs (_: w: w.credentials.expected) (c.services.omnigent-host.workers or { });
  }' > "$OUT/darwin-$h-before.json"
done
```

Expected: magnetite `omnigent-cameron` git `{"email":"cameron.ray.smith@gmail.com"}` and jj `{"email":"cameron.ray.smith@gmail.com","name":""}`.
The host-embedded human homes `tara` on galena and scheelite, `christophersmith` on argentum and `raquel` on blackphos show jj `{"email":"","name":""}`, and `janettesmith` on rosegold shows jj `{"email":"125711642+janetteasmith@users.noreply.github.com","name":""}`.
Darwin worker homes are standalone generations and do not appear in `home-manager.users`.

- [ ] **Step 4: Record the check key sets**

```bash
nix eval --json '.#.checks.x86_64-linux' --apply builtins.attrNames > "$OUT/checks-x86_64-linux-before.json"
nix eval --json '.#.checks.aarch64-darwin' --apply builtins.attrNames > "$OUT/checks-aarch64-darwin-before.json"
```

No commit.

## Task 2: Add the derivation rule

**Files:**
- Modify: `modules/home/users/lib.nix:33`

**Interfaces:**
- Produces: `flake.lib.vcsAuthor :: meta -> { name :: str; email :: str; }`.

- [ ] **Step 1: Confirm the function is absent**

Run: `nix eval --impure --json --expr "let f = builtins.getFlake \"git+file://$PWD\"; in f.lib.vcsAuthor f.users.janettesmith.meta"`
Expected: error `attribute 'vcsAuthor' missing`.

- [ ] **Step 2: Add it beside `mkUserIdentity`**

In `modules/home/users/lib.nix`, after `config.flake.lib.mkUserIdentity = mkUserIdentity;` add:

```nix
  config.flake.lib.vcsAuthor = meta: {
    name = meta.fullname;
    email = meta.gitEmail;
  };
```

- [ ] **Step 3: Evaluate it**

Run the Step 1 command, then the same with `f.users.cameron.meta`.
Expected: `{"email":"125711642+janetteasmith@users.noreply.github.com","name":"Janette Smith"}` and `{"email":"cameron.ray.smith@gmail.com","name":"Cameron Smith"}`.

## Task 3: Add the `vcs-author` module and drop the empty jj default

**Files:**
- Create: `modules/home/development/vcs-author.nix`
- Modify: `modules/home/development/jujutsu.nix:174-177`

**Interfaces:**
- Consumes: `flake.lib.vcsAuthor` (Task 2).
- Produces: `flake.modules.homeManager.vcs-author`, options `vcs.author.name :: nonEmptyStr` and `vcs.author.email :: nonEmptyStr`.

- [ ] **Step 1: Observe the current empty author**

Run: `nix eval --json '.#.homeConfigurations."raquel@x86_64-linux".config.programs.jujutsu.settings.user'`
Expected: `{"email":"","name":""}`.

- [ ] **Step 2: Create the module**

`modules/home/development/vcs-author.nix`:

```nix
{ config, ... }:
{
  flake.modules.homeManager.vcs-author =
    {
      config,
      lib,
      flake,
      ...
    }:
    let
      profile = flake.lib.vcsAuthor flake.users.${config.home.username}.meta;
    in
    {
      key = "vanixiets/vcs-author-home-module";

      options.vcs.author = {
        name = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = profile.name;
          defaultText = lib.literalExpression "(flake.lib.vcsAuthor flake.users.\${config.home.username}.meta).name";
          description = "Author name git and jj record on new commits.";
        };
        email = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = profile.email;
          defaultText = lib.literalExpression "(flake.lib.vcsAuthor flake.users.\${config.home.username}.meta).email";
          description = "Author address git and jj record on new commits, and the allowed_signers principal.";
        };
      };

      config = {
        programs.git.settings.user = { inherit (config.vcs.author) name email; };
        programs.jujutsu.settings.user = { inherit (config.vcs.author) name email; };
      };
    };

  flake.modules.homeManager.development.imports = [ config.flake.modules.homeManager.vcs-author ];
}
```

`flake.users` is read through the home-manager `flake` argument on purpose: the worker fixture replaces it with a throw, and a closure over the flake-parts `config.flake.users` would bypass that guard.

- [ ] **Step 3: Remove the empty jj default**

In `modules/home/development/jujutsu.nix`, delete:

```nix
          user = {
            name = lib.mkDefault "";
            email = lib.mkDefault "";
          };

```

- [ ] **Step 4: Evaluate a previously empty profile**

Run the Step 1 command.
Expected: `{"email":"raquel@example.com","name":"Raquel"}`.

- [ ] **Step 5: Confirm worker homes are untouched apart from the empty name**

Run: `nix eval --json '.#.nixosConfigurations.magnetite.config.home-manager.users.omnigent-cameron.programs.jujutsu.settings.user'`
Expected: `{"email":"cameron.ray.smith@gmail.com"}` (worker homes import `jujutsu`, not `development`, until Task 6).

## Task 4: Remove the hand-written author blocks from the human profiles and commit step 1

**Files:**
- Modify: `modules/home/users/crs58/default.nix:197,357-359,386-389`
- Modify: `modules/home/users/janettesmith/default.nix:39,46-50`
- Modify: `modules/home/users/christophersmith/default.nix:39,46-49`
- Modify: `modules/home/users/raquel/default.nix:44,49-52`
- Modify: `modules/home/users/tara/default.nix:28,33-36`
- Modify: `modules/home/users/ubuntu/default.nix:90,93-96`

**Interfaces:**
- Consumes: `config.vcs.author.email` (Task 3).

- [ ] **Step 1: crs58**

Replace `${flake.users.crs58.meta.email} namespaces="git" ${config.sops.placeholder."ssh-public-key"}` with `${config.vcs.author.email} namespaces="git" ${config.sops.placeholder."ssh-public-key"}`.
Delete `user.name = flake.users.crs58.meta.fullname;` and `user.email = flake.users.crs58.meta.email;` and the blank line after them from `programs.git.settings`, keeping the rest of that block.
Delete the whole block:

```nix
      programs.jujutsu.settings.user = {
        name = flake.users.crs58.meta.fullname;
        email = flake.users.crs58.meta.email;
      };
```

The radicle key comment at `:350` keeps `meta.email`; it is not an author.

- [ ] **Step 2: janettesmith**

Replace `${flake.users.janettesmith.meta.gitEmail} namespaces="git" ${` with `${config.vcs.author.email} namespaces="git" ${`, and delete:

```nix
      programs.git.settings = {
        user.name = flake.users.janettesmith.meta.fullname;
        user.email = flake.users.janettesmith.meta.gitEmail;
      };
      programs.jujutsu.settings.user.email = flake.users.janettesmith.meta.gitEmail;
```

- [ ] **Step 3: christophersmith, raquel, tara**

In each, replace `${flake.users.<user>.meta.email} namespaces="git"` with `${config.vcs.author.email} namespaces="git"`, and delete the block:

```nix
      programs.git.settings = {
        user.name = flake.users.<user>.meta.fullname;
        user.email = flake.users.<user>.meta.email;
      };
```

with `<user>` being `christophersmith`, `raquel` and `tara` respectively.

- [ ] **Step 4: ubuntu**

Replace `${flake.users.ubuntu.meta.email} namespaces="git" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBTeBMUfte7k9yugPtmVLJONiwxZtyoNotfwBOMAEHGz` with `${config.vcs.author.email} namespaces="git" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBTeBMUfte7k9yugPtmVLJONiwxZtyoNotfwBOMAEHGz`, and delete the `programs.git.settings = { user.name = …; user.email = …; };` block and the blank line after it.

- [ ] **Step 5: Compare against the before-state**

```bash
nix eval --json '.#.homeConfigurations' --apply 'cs: builtins.mapAttrs (_: c: {
  git = c.config.programs.git.settings.user or null;
  jj = c.config.programs.jujutsu.settings.user or null;
  signers = c.config.sops.templates.allowed_signers.content or c.config.xdg.configFile."git/allowed_signers".text or null;
}) cs' > "$OUT/authors-step1.json"
jaq -n --slurpfile a "$OUT/authors-before.json" --slurpfile b "$OUT/authors-step1.json" \
  '$a[0] | to_entries | map(select(.value != $b[0][.key]) | {key, before: .value, after: $b[0][.key]})'
```

Expected: only the `jj` field differs, only for `christophersmith@*`, `raquel@*`, `tara@*`, `ubuntu@x86_64-linux` and `janettesmith@*`, and in each the new `jj` equals that entry's `git`.
`git` and `signers` are unchanged everywhere.

- [ ] **Step 6: Compare the host-embedded homes against the before-state**

Rerun Task 1 Step 3 with `-before.json` replaced by `-step1.json` in both output paths, then diff each pair:

```bash
for before in "$OUT"/nixos-*-before.json "$OUT"/darwin-*-before.json; do
  after="${before%-before.json}-step1.json"
  echo "${before##*/}"
  jaq -n --slurpfile a "$before" --slurpfile b "$after" '{
    homes: ($a[0].homes | to_entries | map(select(.value != $b[0].homes[.key]) | {key, before: .value, after: $b[0].homes[.key]})),
    expectedUnchanged: ($a[0].expected == $b[0].expected)
  }'
done
```

Expected: `expectedUnchanged` is `true` for every host, and only the `jj` field differs, only in these homes:

- `tara` on galena and scheelite, `christophersmith` on argentum and `raquel` on blackphos: jj changes from `{"email":"","name":""}` to that home's `git`.
- `janettesmith` on rosegold: jj `name` changes from `""` to `"Janette Smith"`, so jj now equals that home's `git`.
- `omnigent-cameron` on magnetite and pyrite: jj changes from `{"email":"cameron.ray.smith@gmail.com","name":""}` to `{"email":"cameron.ray.smith@gmail.com"}`, the empty name dropped by Task 3 Step 3 (task 1.4), because worker homes do not import `vcs-author` until step 2.

Every `cameron` and `crs58` home (cameron on magnetite, pyrite, galena, scheelite, cinnabar, electrum, argentum and rosegold; crs58 on blackphos and stibnite) and `omnigent-janettesmith` on magnetite and pyrite are unchanged, and `git`, `signers` and `signingKey` are unchanged in every home.

- [ ] **Step 7: Show the type rejects an empty name**

Run: `nix eval '.#.homeConfigurations."raquel@x86_64-linux"' --apply 'c: (c.extendModules { modules = [ { vcs.author.name = ""; } ]; }).config.programs.jujutsu.settings.user.name'`
Expected: an error stating that `vcs.author.name` is not of type `non-empty string`.

- [ ] **Step 8: Build the human home checks**

```bash
nix build --no-link .#checks.x86_64-linux.home-manager-crs58 .#checks.x86_64-linux.home-manager-christophersmith \
  .#checks.x86_64-linux.home-manager-janettesmith .#checks.x86_64-linux.home-manager-raquel .#checks.x86_64-linux.home-manager-ubuntu
nix eval --raw '.#.checks.aarch64-darwin.home-manager-tara.drvPath'
nix eval --raw '.#.checks.aarch64-darwin.home-manager-crs58.drvPath'
```

Expected: all builds succeed; both darwin evaluations print a store path.

- [ ] **Step 9: Lint, confirm the check key sets, commit**

```bash
just lint
nix eval --json '.#.checks.x86_64-linux' --apply builtins.attrNames | diff - "$OUT/checks-x86_64-linux-before.json"
nix eval --json '.#.checks.aarch64-darwin' --apply builtins.attrNames | diff - "$OUT/checks-aarch64-darwin-before.json"
jj squash --into <step-1 change> -u -k -- <step-1 paths>   # change described "home: derive git and jj author from the person record through one vcs.author option"
```

If `just lint` (deadnix) reports `flake` as an unused argument in a profile whose only use was the author block, remove that argument and rerun.
Expected: both `diff`s print nothing.

## Task 5: Type the worker owner as a profile key

**Files:**
- Modify: `modules/system/omnigent-worker-options.nix:1,109-112`
- Modify: `modules/clan/services/omnigent/flake-module.nix:1-6,82-85`

**Interfaces:**
- Produces: `owner :: enum (attrNames config.flake.users)` in both interfaces.

- [ ] **Step 1: Show a non-profile owner is accepted today**

```bash
nix eval --impure --expr "let f = builtins.getFlake \"git+file://$PWD\"; lib = f.inputs.nixpkgs.lib;
  i = ((import ./modules/clan/services/omnigent/flake-module.nix { config.flake = f; }).flake.clan.modules.omnigent { inherit lib; }).roles.host.interface;
  in (lib.evalModules { modules = [ i { workers.x = { owner = \"nobody\"; user = \"omnigent-nobody\"; }; } ]; }).config.workers.x.owner"
```

Expected: `"nobody"`.

- [ ] **Step 2: Worker options**

Change the header of `modules/system/omnigent-worker-options.nix` from `{ lib, ... }:` to `{ config, lib, ... }:`, add `profileKeys = lib.attrNames config.flake.users;` as the first binding of its `let`, and replace the `owner` option with:

```nix
                owner = lib.mkOption {
                  type = lib.types.enum profileKeys;
                  description = "Person this worker runs for, as a flake.users key; its author and expected identities derive from that profile. Enrollment must verify application ownership separately.";
                };
```

- [ ] **Step 3: Clan interface**

In `modules/clan/services/omnigent/flake-module.nix`, add `profileKeys = builtins.attrNames config.flake.users;` to the top-level `let`, and replace the host role's `owner` option with:

```nix
                    owner = lib.mkOption {
                      type = lib.types.enum profileKeys;
                      description = "Person this worker runs for, as a flake.users key, verified separately during enrollment.";
                    };
```

- [ ] **Step 4: Re-run Step 1**

Expected: an error that `"nobody"` is not one of the enum values; the same expression with `owner = \"cameron\"` prints `"cameron"`.

## Task 6: Set the worker author at system level and drop the hand-passed identity

**Files:**
- Modify: `modules/home/ai/omnigent/worker.nix:90-110`
- Modify: `modules/nixos/omnigent-host.nix:292-296`
- Modify: `modules/darwin/omnigent-host.nix:111-113`
- Modify: `modules/home/ai/omnigent/credentials.nix:297-299,303-304`
- Modify: `modules/clan/inventory/services/omnigent.nix:7-40,55-110`
- Modify: `modules/lib/omnigent-fleet-obligations.nix:49,190`
- Modify: `modules/checks/omnigent-workers.nix:35-70`

**Interfaces:**
- Consumes: `flake.lib.vcsAuthor`, `flake.modules.homeManager.vcs-author`, the owner type (Tasks 2, 3, 5).
- Produces: worker homes with `vcs.author` set; `workerCredentials :: owner -> user -> labels -> credentials`.

- [ ] **Step 1: Import `vcs-author` in the worker module**

In the `imports = map (name: modules.${name}) [ … ]` list of `modules/home/ai/omnigent/worker.nix`, add `"vcs-author"` after `"jujutsu"`.

- [ ] **Step 2: Set the author in the NixOS adapter**

In `modules/nixos/omnigent-host.nix`, change the worker home imports to:

```nix
                  imports = [
                    flakeConfig.flake.modules.homeManager.omnigent-worker
                    deliveries.${name}.homeModule
                    { vcs.author = flakeConfig.flake.lib.vcsAuthor flakeConfig.flake.users.${worker.owner}.meta; }
                  ]
                  ++ worker.extraHomeModules;
```

- [ ] **Step 3: Set the author in the Darwin adapter**

In `modules/darwin/omnigent-host.nix`, change the start of the worker home `modules` list to:

```nix
          modules = [
            flakeConfig.flake.modules.homeManager.omnigent-worker
            deliveries.${name}.homeModule
            { vcs.author = flakeConfig.flake.lib.vcsAuthor flakeConfig.flake.users.${worker.owner}.meta; }
```

- [ ] **Step 4: Drop `user.email` from the credential module**

In `modules/home/ai/omnigent/credentials.nix`, change the signing branch's git `settings` to:

```nix
            settings.gpg.ssh.allowedSignersFile = toString signers;
```

and delete `user.email = policy.expected.gitEmail;` from `programs.jujutsu.settings`.

- [ ] **Step 5: Derive worker credentials from the owner**

In `modules/clan/inventory/services/omnigent.nix`, keep the `janetteAuthor` binding and the `janettesmith.extraHomeModules` definition (removed in Task 8), and replace `workerCredentials = user: meta: labels: {` with:

```nix
  workerCredentials =
    owner: user: labels:
    let
      meta = config.flake.users.${owner}.meta;
    in
    {
```

closing the added `let … in` after the existing attribute set.
The worker account name stays an explicit argument rather than being derived from the owner, since the inventory declares `user` beside `owner` for each worker.
Replace each call: `workerCredentials "omnigent-cameron" config.flake.users.crs58.meta [ "personal" "work" ]` becomes `workerCredentials "cameron" "omnigent-cameron" [ "personal" "work" ]`, and `workerCredentials "omnigent-janettesmith" config.flake.users.janettesmith.meta [ "personal" ]` becomes `workerCredentials "janettesmith" "omnigent-janettesmith" [ "personal" ]`.
Janette's `extraHomeModules` and the adapter now define equal strings for her worker's git and jj `user`; equal definitions merge without conflict (checked on 2026-11-08 by evaluating magnetite with a duplicate equal author: `failures` returned `[]`).

- [ ] **Step 6: Replace `ownerMeta` in the obligations**

In `modules/lib/omnigent-fleet-obligations.nix`, delete `ownerMeta` and in `declaredCredentials` replace `meta = ownerMeta worker.owner;` with `meta = config.flake.users.${worker.owner}.meta;`.
Keep `janetteMeta`, `janetteAuthor`, `identityBinding`, `identityBoundHomeModules` and `identityBindingDiscriminates`; they keep regulating Janette's workers until Task 8 replaces them.

- [ ] **Step 7: Give the capability fixture an explicit author**

In `modules/checks/omnigent-workers.nix`, add to `mkHome`'s inline base module:

```nix
              vcs.author = {
                name = "Worker fixture";
                email = "worker@example.invalid";
              };
```

and delete from the `home` fixture:

```nix
          programs.git.settings = {
            user.name = "Worker fixture";
            user.email = "worker@example.invalid";
            commit.gpgSign = false;
            tag.gpgSign = "off";
          };
          programs.jujutsu.settings.user = {
            name = "Worker fixture";
            email = "worker@example.invalid";
          };
```

replacing them with:

```nix
          programs.git.settings = {
            commit.gpgSign = false;
            tag.gpgSign = "off";
          };
```

Leave `flake.users = throw "worker imported a whole-user alias";` unchanged.

- [ ] **Step 8: Evaluate the workers**

```bash
for h in magnetite pyrite; do
  nix eval --json ".#.nixosConfigurations.$h.config.home-manager.users" --apply 'us: builtins.mapAttrs (_: u: { git = { inherit (u.programs.git.settings.user) name email; }; jj = u.programs.jujutsu.settings.user; }) (builtins.removeAttrs us [ "cameron" ])'
done
nix eval --json '.#.nixosConfigurations.magnetite.config.services.omnigent-host.workers' --apply 'ws: builtins.mapAttrs (_: w: w.credentials.expected) ws'
```

Expected: `omnigent-cameron` git and jj `{"email":"cameron.ray.smith@gmail.com","name":"Cameron Smith"}`, `omnigent-janettesmith` git and jj `{"email":"125711642+janetteasmith@users.noreply.github.com","name":"Janette Smith"}`, and `expected` identical to `nixos-magnetite-before.json`.

- [ ] **Step 9: Build the fixtures and machine checks**

```bash
nix build --no-link .#checks.x86_64-linux.omnigent-worker-capabilities .#checks.x86_64-linux.omnigent-worker-linux \
  .#checks.x86_64-linux.omnigent-worker-inventory .#checks.x86_64-linux.nixos-magnetite .#checks.x86_64-linux.nixos-pyrite
nix eval --raw '.#.checks.aarch64-darwin.darwin-stibnite.drvPath'
nix eval --raw '.#.checks.aarch64-darwin.omnigent-worker-darwin.drvPath'
```

Expected: all succeed, and `for h in magnetite pyrite; do nix eval --impure --json --expr "let f = builtins.getFlake \"git+file://$PWD\"; in f.lib.omnigentFleetObligations.failures \"$h\" f.nixosConfigurations.$h.config"; done` prints `[]` twice, so Janette's `identityBoundHomeModules` still holds.

## Task 7: Compare and commit step 2

**Files:** none further.

- [ ] **Step 1: Compare host homes against the before-state**

Rerun Task 1 Step 3 with `-before.json` replaced by `-step2.json`, and diff each `*-step2.json` against its `*-step1.json` with the Task 4 Step 6 loop.
Expected: only `omnigent-cameron` on magnetite and pyrite differs, where `git` gains `name = "Cameron Smith"` and `jj` gains `name = "Cameron Smith"`; `omnigent-janettesmith`, every human home, every `signers` and `signingKey`, and every `expected` are unchanged.

- [ ] **Step 2: Lint, confirm the key sets, commit**

```bash
just lint
nix eval --json '.#.checks.x86_64-linux' --apply builtins.attrNames | diff - "$OUT/checks-x86_64-linux-before.json"
nix eval --json '.#.checks.aarch64-darwin' --apply builtins.attrNames | diff - "$OUT/checks-aarch64-darwin-before.json"
jj squash --into <step-2 change> -u -k -- <step-2 paths>   # change described "omnigent: type worker owner as a profile key and set each worker's author from it"
```

Expected: both `diff`s print nothing.

## Task 8: Replace Janette's binding with the author obligation

This task and Tasks 9 and 10 form one commit, so no state of `main` lacks an author obligation.

**Files:**
- Modify: `modules/lib/omnigent-fleet-obligations.nix:27-45,235-246,429` (remove Janette's binding; new `authorBound` binding before `accountObligations`; `authorBinding` merged into the `cases` attribute set for Linux hosts only; export at the end)
- Modify: `modules/clan/inventory/services/omnigent.nix:2-6,111-138`

**Interfaces:**
- Produces: `flake.lib.omnigentFleetObligations.authorBound :: { meta; expected; home } -> bool`; case `authorBinding`.

- [ ] **Step 1: Remove Janette's binding from the inventory and the obligations**

In `modules/clan/inventory/services/omnigent.nix`, delete the `janetteAuthor` binding, and in `extraModules` keep the `PI_CODING_AGENT_DIR` line and delete the whole `services.omnigent-host.workers = lib.mkIf (…) { janettesmith.extraHomeModules = [ … ]; };` definition; drop `lib` from that module's arguments if it becomes unused.
In `modules/lib/omnigent-fleet-obligations.nix`, delete `janetteMeta`, `janetteAuthor` and `identityBinding`, and the `identityBoundHomeModules` and `identityBindingDiscriminates` cases.
Janette's workers keep the same author, now from the adapter alone.

- [ ] **Step 2: Add the predicate**

```nix
  authorBound =
    {
      meta,
      expected,
      home,
    }:
    let
      git = home.programs.git.settings.user or { };
      jj = home.programs.jujutsu.settings.user or { };
    in
    meta.fullname != ""
    && (git.name or null) == meta.fullname
    && (git.email or null) == meta.gitEmail
    && (jj.name or null) == meta.fullname
    && (jj.email or null) == meta.gitEmail
    && expected.gitEmail == meta.gitEmail;
```

It reads `meta.fullname` and `meta.gitEmail` directly rather than calling `vcsAuthor`, so a defect in the rule fails here instead of agreeing with itself.

- [ ] **Step 3: Add the case on Linux hosts only**

`cases` returns one attribute set literal, and `failures` reports every attribute of it that is false.
Merge `authorBinding` into that set only when the host is not Darwin, so on Darwin the case is not evaluated and `failures` neither checks nor reports it.
Change the closing `};` of the attribute set after `credentialDelivery` to:

```nix
    }
    # Darwin worker homes are standalone generations absent from the host configuration;
    # the shared vcs-author module and adapter code are exercised through the Linux hosts.
    // lib.optionalAttrs (!isDarwin) {
      authorBinding = lib.all (
        worker:
        authorBound {
          meta = config.flake.users.${worker.owner}.meta;
          expected = worker.credentials.expected;
          home = hostConfig.home-manager.users.${worker.user};
        }
      ) (lib.attrValues workers);
    };
```

`credentialWiring` keeps its `isDarwin || …` form, which reports it as met on Darwin; changing that is out of scope here.

- [ ] **Step 4: Export the predicate**

Change the final attribute set to:

```nix
  flake.lib.omnigentFleetObligations = {
    inherit expectedOwners authorBound;

    failures =
```

- [ ] **Step 5: Show the case holds and can fail on a real host**

```bash
nix eval --impure --json --expr "let f = builtins.getFlake \"git+file://$PWD\"; in f.lib.omnigentFleetObligations.failures \"magnetite\" f.nixosConfigurations.magnetite.config"
nix eval --impure --json --expr "let f = builtins.getFlake \"git+file://$PWD\";
  c = f.nixosConfigurations.magnetite.extendModules { modules = [ { home-manager.users.omnigent-cameron.vcs.author.name = f.inputs.nixpkgs.lib.mkForce \"Someone Else\"; } ]; };
  in f.lib.omnigentFleetObligations.failures \"magnetite\" c.config"
```

Expected: `[]`, then `["authorBinding"]`.
Also evaluate magnetite's `home-manager.users.omnigent-janettesmith.programs.{git,jujutsu}.settings.user` and confirm both are unchanged from Task 7.

## Task 9: Add the inventory fixtures

**Files:**
- Modify: `modules/checks/omnigent-workers.nix` (`inventoryCases`, after `nixOnlyModules`)

**Interfaces:**
- Consumes: `config.flake.lib.vcsAuthor`, `config.flake.lib.omnigentFleetObligations.authorBound`, `clanHostInterface`.

- [ ] **Step 1: Add the cases**

Add to the `let` of the check, beside `metaFixture`:

```nix
      authorBound = config.flake.lib.omnigentFleetObligations.authorBound;
      authorMeta = {
        fullname = "Fixture Person";
        gitEmail = "author@example.invalid";
      };
      authorHome = gitUser: jjUser: {
        programs.git.settings.user = gitUser;
        programs.jujutsu.settings.user = jjUser;
      };
      fixtureAuthor = {
        name = "Fixture Person";
        email = "author@example.invalid";
      };
      ownerAccepted =
        owner:
        (builtins.tryEval (
          builtins.deepSeq
            (lib.evalModules {
              modules = [
                clanHostInterface
                {
                  workers.fixture = {
                    inherit owner;
                    user = "omnigent-fixture";
                  };
                }
              ];
            }).config.workers.fixture.owner
            true
        )).success;
```

and to `inventoryCases`:

```nix
        vcsAuthorFixture =
          config.flake.lib.vcsAuthor {
            fullname = "Fixture";
            email = "primary@example.invalid";
            gitEmail = "author@example.invalid";
          } == {
            name = "Fixture";
            email = "author@example.invalid";
          };
        ownerOutsideProfiles = ownerAccepted "cameron" && !ownerAccepted "nobody";
        authorBoundControl = authorBound {
          meta = authorMeta;
          expected.gitEmail = "author@example.invalid";
          home = authorHome fixtureAuthor fixtureAuthor;
        };
        authorBoundWrongName = !authorBound {
          meta = authorMeta;
          expected.gitEmail = "author@example.invalid";
          home = authorHome (fixtureAuthor // { name = "Someone Else"; }) (fixtureAuthor // { name = "Someone Else"; });
        };
        authorBoundEmptyName = !authorBound {
          meta = authorMeta // { fullname = ""; };
          expected.gitEmail = "author@example.invalid";
          home = authorHome (fixtureAuthor // { name = ""; }) (fixtureAuthor // { name = ""; });
        };
        authorBoundJjMismatch = !authorBound {
          meta = authorMeta;
          expected.gitEmail = "author@example.invalid";
          home = authorHome fixtureAuthor (fixtureAuthor // { email = "primary@example.invalid"; });
        };
        authorBoundMissingGitName = !authorBound {
          meta = authorMeta;
          expected.gitEmail = "author@example.invalid";
          home = authorHome { email = "author@example.invalid"; } fixtureAuthor;
        };
        authorBoundExpectedDrift = !authorBound {
          meta = authorMeta;
          expected.gitEmail = "primary@example.invalid";
          home = authorHome fixtureAuthor fixtureAuthor;
        };
```

`authorHome` takes the git `user` first and the jj `user` second, so `authorBoundMissingGitName` gives git an email and no name while jj stays complete.
That is the shape observed on magnetite before this change, where `omnigent-cameron` had git `user = { email = "cameron.ray.smith@gmail.com"; }`.
`authorBoundEmptyName` remains the only case that exercises the `meta.fullname != ""` guard, since its home's empty names equal the empty `meta.fullname`.
`authorBoundExpectedDrift` keeps a correct home and changes only `expected.gitEmail`, so it fails only the signer-principal conjunct.

- [ ] **Step 2: Build the check**

Run: `nix build --no-link .#checks.x86_64-linux.omnigent-worker-inventory`
Expected: success.

- [ ] **Step 3: Show each case discriminates**

For each of `vcsAuthorFixture`, `ownerOutsideProfiles` and the six `authorBound*` cases, invert its expectation locally (for example change `email = meta.gitEmail;` to `email = meta.email;` in `vcsAuthor`, or remove one `!`), rebuild, observe a failure naming that case, and revert.
Expected: eight distinct failures, then a clean `git diff` for those reverts.

## Task 10: Document and commit step 3

**Files:**
- Modify: `modules/clan/services/omnigent/README.md:135,143,146,148`
- Modify: `docs/notes/development/omnigent/deployment-plan.md` (append at the end of the file, after the `## ZeroTier MSS lifecycle recovery, 2026-09-15` section)

- [ ] **Step 1: README worker identity sentence and obligations paragraph**

In `modules/clan/services/omnigent/README.md`, replace "Only her non-secret name and Git address reach worker HM through `extraHomeModules`; neither her human modules nor `contentPrivate` are imported." with:

```markdown
Every worker's author, hers included, is the pair `flake.lib.vcsAuthor` derives from its owner's profile, which the NixOS and Darwin adapters set as `vcs.author` in the worker home; only that non-secret name and Git address reach worker HM, and neither her human modules nor `contentPrivate` are imported.
```

Replace "Janette's non-secret author binding with its discriminating negative fixture," with "every Linux worker's git and jj author against its owner's profile (`authorBinding`),".
Replace "Janette's canonical metadata and public recipient entry, and the `meta.gitEmail` fixtures." with "Janette's canonical metadata and public recipient entry, the `meta.gitEmail` fixtures, the `vcsAuthor` literal, the refusal of an owner that is not a profile key, and the `authorBound` control with its wrong-name, empty-name, git-jj-mismatch, missing-git-name and expected-drift mutants."
Replace "inventory mutation fixtures (wrong Git/jj author, denied Nix access, undeclared signer)" with "inventory mutation fixtures (denied Nix access, undeclared signer)".
Replace "the retained human profile and human author projections," with "the retained human profile and human author projections, the convention that no module other than `vcs-author` sets a human home's git or jj `user` (worker homes are regulated by `authorBinding`),".

- [ ] **Step 2: Dated amendment**

Append at the end of `docs/notes/development/omnigent/deployment-plan.md`, after the `## ZeroTier MSS lifecycle recovery, 2026-09-15` section, with the heading dated the day this commit is authored:

```markdown
## VCS author identity amendment, 2026-11-08

Every git and jj author in the fleet now derives from one rule, `flake.lib.vcsAuthor meta = { name = meta.fullname; email = meta.gitEmail; }`, held by the home-manager option `vcs.author`.
Human homes default it from their own profile; the NixOS and Darwin adapters set it in each worker home from `flake.users.${worker.owner}.meta`.
Worker `owner` is now typed as a `flake.users` key in the worker options and the clan interface.
Janette's `extraHomeModules` author binding, the hand-passed meta and the credential module's `user.email` are removed; her worker's author and `expected` values are unchanged.
Cameron's workers gain a git and jj name, and the raquel, tara, christophersmith, ubuntu and janettesmith human profiles gain a jj author; no address, signer principal, signing key or token changes.
The fleet obligations replace Janette's binding with `authorBinding` over every Linux worker, whose mutants run once in `checks.x86_64-linux.omnigent-worker-inventory`; stibnite's worker is covered through the shared module.
A controller comparing protected projections against the fixed baselines recorded above must allow `programs.git.settings.user.name`, `programs.jujutsu.settings.user.name` and `programs.jujutsu.settings.user.email` for these homes.
The Janette identity amendment above remains the record of that change.
The requirements, design and task ledger for this amendment are in the OpenSpec change `openspec/changes/unify-vcs-author-identity/`, or under `openspec/changes/archive/` once it is archived.
```

- [ ] **Step 3: Build, lint, confirm the key set, commit**

```bash
nix build --no-link .#checks.x86_64-linux.nixos-magnetite .#checks.x86_64-linux.nixos-pyrite .#checks.x86_64-linux.omnigent-worker-inventory
just lint
nix eval --json '.#.checks.x86_64-linux' --apply builtins.attrNames | diff - "$OUT/checks-x86_64-linux-before.json"
nix eval --json '.#.checks.aarch64-darwin' --apply builtins.attrNames | diff - "$OUT/checks-aarch64-darwin-before.json"
jj squash --into <step-3 change> -u -k -- <step-3 paths>   # change described "omnigent: regulate every Linux worker's author against its owner's profile, replacing Janette's binding"
```

Expected: builds succeed, both `diff`s print nothing.
Publication: `just lint`, `jj git push --bookmark unify-vcs-author-identity`, then one pull request with `gh pr create --head unify-vcs-author-identity --base main`, enqueued with `gh pr merge <PR> --auto --rebase`.
CI builds only the head commit, so each commit was built and its obligations evaluated locally at its own position in the chain.

## Task 11: Deploy, remove the workaround, verify delivered state

Operator-run after the stack lands; an agent does not activate hosts.

- [ ] **Step 1: Deploy magnetite, pyrite and stibnite**

After each deploy, read every post on the fleet's notification topics since the deploy started and attribute each to a cause.

- [ ] **Step 2: Read the delivered worker author on magnetite**

As `omnigent-cameron`, outside any repository:

```bash
cd ~ && jj config get user.name && jj config get user.email && git config --global user.name
```

Expected: `Cameron Smith`, `cameron.ray.smith@gmail.com`, `Cameron Smith`.

- [ ] **Step 3: Remove the repository-local workaround**

```bash
cd /home/omnigent-cameron/projects/vanixiets
jj config unset --repo user.name
git config --local --unset user.name
jj config list --repo user
git config --local --get user.name; echo "exit=$?"
jj config get user.name
```

Expected: no `user.name` line from `jj config list --repo user`, `exit=1`, then `Cameron Smith`.

- [ ] **Step 4: Re-author any empty-author mutable commit**

```bash
jj log -r 'mutable() & author_name(exact:"")' --no-graph -T 'change_id.short() ++ "\n"'
jj metaedit --update-author -r 'mutable() & author_name(exact:"")'
jj log -r 'mutable() & author_name(exact:"")' --no-graph -T 'change_id.short() ++ "\n"'
```

Expected: the final command prints nothing.
Skip the `metaedit` if the first command printed nothing.

- [ ] **Step 5: Repeat Steps 2 and 3 for the omnigent-cameron checkouts on pyrite and stibnite, if they carry the workaround**

- [ ] **Step 6: Push a worker commit end to end**

```bash
t=$(mktemp -d) && cd "$t" && git init -q --bare remote.git && jj git init --colocate repo >/dev/null && cd repo
jj git remote add origin ../remote.git && echo x > f && jj commit -m probe && jj bookmark create probe -r @-
jj log -r @- --no-graph -T 'author ++ "\n"'
jj git push --bookmark probe --allow-new
cd / && rm -rf "$t"
```

Expected: `Cameron Smith <cameron.ray.smith@gmail.com>` and a successful push.

- [ ] **Step 7: Read Janette's delivered worker author**

As `omnigent-janettesmith` on magnetite, `jj config get user.email` prints `125711642+janetteasmith@users.noreply.github.com`; `nix eval '.#.nixosConfigurations.magnetite.config.services.omnigent-host.workers.janettesmith.credentials.expected.omnigentEmail'` prints `"janette.a.smith@gmail.com"`.

- [ ] **Step 8: Deploy the remaining affected hosts at the operator's discretion**

argentum, blackphos, rosegold, galena and scheelite; after each, `jj config get user.name` as each affected account prints that person's `meta.fullname`.

## Self-review

Spec coverage: `One rule derives an author from a profile` (Tasks 2, 9), `Every home sets git and jj author from one non-empty pair` (Tasks 3, 4, 6), `The signer principal is the author address` (Tasks 4, 8, 9), `A worker's owner is a profile key` (Tasks 5, 9), `A worker's author is its owner's profile, set by the host` (Task 6), `The sign-in address is unchanged` (Tasks 6, 11), `Every Linux worker's author is regulated against its owner's profile` (Tasks 8, 9, 10), the trust boundary (Task 11), and the behavioral requirements through their discharging interface requirements and Task 11's delivered-state reads.
The clause that no module other than `vcs-author` sets a human home's git or jj `user` is a review convention that no task checks; Task 10 records it in the README as unchecked, and worker homes are covered by `authorBinding` (Tasks 8, 9).
Names used across tasks: `vcsAuthor`, `vcs-author`, `vcs.author.{name,email}`, `profileKeys`, `workerCredentials owner user labels`, `authorBound { meta; expected; home; }`, `authorBinding`.

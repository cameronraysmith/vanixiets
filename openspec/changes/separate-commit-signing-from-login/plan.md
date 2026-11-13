# Separate commit signing from login implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every commit, by a person or an agent, is signed without interaction by a per-person signing key that admits no login and opens no secret, and Omnigent workers hold that key instead of their owner's login key.

**Architecture:** Each profile gains `meta.signingKey` and `meta.retiredSigningKeys`; the private half is a per-person sops entry `commit-signing-key`, copied into the worker generator by the existing enrollment pipeline.
One home module, `vcs-signing`, makes git and jj sign with that file through `agentFreeSshKeygen`, which removes `SSH_AUTH_SOCK` before running nixpkgs' `ssh-keygen`, and renders `allowed_signers` from the profile.
`commitSigningObligations` rides on every machine check, and `checks.x86_64-linux.commit-signing-key` holds the profile relation, the predicates' mutants, the agent test, the `valid-before` round trip and the recipient scan.

**Tech Stack:** Nix (flake-parts, import-tree, home-manager, nix-darwin, clan-core, sops-nix), OpenSSH `ssh-keygen -Y`, git, jj 0.47.1, `ssh-to-age`.

**Spec:** `openspec/changes/separate-commit-signing-from-login/specs/commit-signing-key/spec.md`, `specs/commit-signing-key-interface/spec.md`, `specs/commit-author-identity-interface/spec.md` and `specs/world-assumptions/spec.md`, with `design.md` and `tasks.md` in the same directory.

## Global constraints

- Phase 0 (tasks group 1) is operator-run; agents never decrypt a private key, generate a key, run `clan vars set`, or call `gh ssh-key add`.
- Work on the bookmark `separate-commit-signing-from-login`: three phase A commits, rebase-merged, each leaving `main` evaluable and regulated; phase B is a later single commit.
- jj commits run no git hooks: run `just lint` before each commit.
- `@` stays an empty working-copy commit atop the chain tip; route edits with `jj squash --into <step change> -u -k -- <paths>`, never `jj commit`.
- Do not run `nix flake check`, `just check` or `just check-fast`; build only named checks; aarch64-darwin attributes are evaluated, never built locally.
- Workers receive only the signing key; the `users = throw "worker imported a whole-user alias"` guard in `modules/checks/omnigent-workers.nix` stays.
- Login authorization, `sshKeys`, the Radicle key (`ssh-signing-key`, `radicle.nix:21`) and the signer principal (`vcs.author.email`, workers `expected.gitEmail`) are unchanged.
- `checks.x86_64-linux` gains exactly `commit-signing-key`; `checks.aarch64-darwin` is unchanged.
- Markdown: one sentence per line, sentence-case headings.

## Grounding

Read on 2026-11-13.

- This change is the next step of the hardening order in `docs/notes/development/omnigent/deployment-plan.md:199` and `:335` (dedicated worker accounts, taken in d20ae8599 and a28464344, then `enforce_sandbox`); it makes `:856` ("no personal age identity") hold for worker accounts, which `:854` and the delivered `ssh-signing-key` (`:974`) currently contradict.
- git signs with `<gpg.ssh.program> -Y sign -n git -f <user.signingkey> [-U] <buffer file>` and verifies with `-Y find-principals -f <signers> -s <sig> -Overify-time=<payload time>` then `-Y verify … -I <principal> -Overify-time=…` (git `gpg-interface.c`, `master`, lines 499-501 and 1104-1112).
- jj signs with `<signing.backends.ssh.program> -Y sign -f <signing.key> -n git`, data on stdin, and verifies with `-Y find-principals -f <signers> -s <sig>` then `-Y verify -s <sig> -I <principal> -f <signers> -n git`, with no verify time (jj `lib/src/ssh_signing.rs`, `main`).
- `ssh-keygen -Y sign` asks the agent at `SSH_AUTH_SOCK` for the key before reading the file (openssh-portable `ssh-keygen.c` `sig_sign`, lines 2820-2845).
- `modules/home/development/git.nix:27-38` holds git's `signing` with the darwin branch; `jujutsu.nix:175-194` holds jj's personal `signing`; both files expose `content true` as `development` and `content false` as `git`/`jujutsu`.
- `modules/home/development/vcs-author.nix` is the template for a home module that reads `flake.users.${config.home.username}.meta` through the `flake` special argument and imports itself into `development`.
- `modules/checks/machines.nix:31-47` asserts `omnigentFleetObligations.failures` and `deployRecordObligations.failures` per machine.
- `nixosConfigurations.cinnabar.config.services.openssh`: `authorizedKeysCommand = "none"`, `authorizedKeysFiles = [ "/etc/ssh/authorized_keys.d/%u" ]`, `authorizedKeysInHomedir = true`, `extraConfig` with one `AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u` line; every account's `keyFiles` empty; `boot.initrd.network.ssh.authorizedKeyFiles = [ ]`.
- `darwinConfigurations.stibnite.config.services.openssh.extraConfig` is `MaxAuthTries 20`, and its `home-manager.users` is `[ "crs58" ]`.
- `cameronraysmith` signing registrations: 663212, 670975 (the login key), 1156413 (`devin-ubuntu-ssh`).

## File structure

- Modify `modules/home/users/lib.nix`: `signingKey`, `retiredSigningKeys`.
- Modify `modules/home/users/{crs58,janettesmith,christophersmith,raquel,tara,ubuntu}/meta.nix` and `default.nix`.
- Create `modules/lib/commit-signing.nix`: `allowedSigners`, `agentFreeSshKeygen`, `commitSigningObligations`.
- Create `modules/home/development/vcs-signing.nix`.
- Modify `modules/home/development/{git,jujutsu}.nix`, `modules/home/core/bitwarden.nix`.
- Modify `modules/clan/inventory/services/omnigent.nix`, `modules/lib/omnigent-fleet-obligations.nix`, `modules/checks/omnigent-workers.nix`, `modules/checks/machines.nix`.
- Create `modules/checks/commit-signing-key.nix`.
- Modify `modules/clan/services/omnigent/README.md`, `docs/notes/development/omnigent/deployment-plan.md`.
- Operator-modified secrets: `secrets/home-manager/users/<user>/secrets.yaml`, `vars/shared/omnigent-{cameron,janettesmith}-signing-key/key/secret`.

---

## Task 1: Phase 0 (operator)

Tasks 1.1 to 1.5.
The agent runs only 1.1; the operator runs 1.2 to 1.5 and hands back the public keys.

- [ ] **Step 1: Record the before-state (1.1)**

```bash
nix eval --json --impure --expr '
  let f = builtins.getFlake "git+file://${toString ./.}";
      proj = h: {
        gitKey = h.programs.git.signing.key or null;
        gitProgram = h.programs.git.settings.gpg.ssh.program or null;
        jjKey = h.programs.jujutsu.settings.signing.key or null;
        jjProgram = h.programs.jujutsu.settings.signing.backends.ssh.program or null;
        signers = h.sops.templates.allowed_signers.content or h.xdg.configFile."git/allowed_signers".text or null;
      };
  in {
    homes = builtins.mapAttrs (_: c: proj c.config) f.homeConfigurations;
    hosts = builtins.mapAttrs (_: c: builtins.mapAttrs (_: proj) c.config.home-manager.users)
      (f.nixosConfigurations // f.darwinConfigurations);
  }' | tee "$XDG_STATE_HOME/agent-logs/vanixiets/signing-before-$(date +%Y%m%d-%H%M%S).json"
nix eval --json '.#.checks.x86_64-linux' --apply builtins.attrNames > "$XDG_STATE_HOME/agent-logs/vanixiets/checks-x86_64-linux-before.json"
nix eval --json '.#.checks.aarch64-darwin' --apply builtins.attrNames > "$XDG_STATE_HOME/agent-logs/vanixiets/checks-aarch64-darwin-before.json"
```

Expected: stibnite `crs58.gitKey` ends in `secrets/ssh-public-key`; every `jjKey` on a human home ends in `.radicle/keys/radicle`; every program is `null`.

- [ ] **Step 2: Operator discovery and generation (1.2, 1.3)**

```bash
for u in christophersmith raquel tara janettesmith; do
  printf '%s ' "$u"; sops -d --extract '["ssh-public-key"]' "secrets/home-manager/users/$u/secrets.yaml" | cut -d' ' -f1-2
done
```

Compare each with `nix eval --raw .#users.<u>.meta.sshKeys --apply 'k: builtins.head k'`.
For each profile needing a key:

```bash
(set +x; umask 077; d=$(mktemp -d /dev/shm/sign.XXXXXX 2>/dev/null || mktemp -d)
 ssh-keygen -q -t ed25519 -N '' -C '<meta.gitEmail> commit signing' -f "$d/key"
 sops set secrets/home-manager/users/<u>/secrets.yaml '["commit-signing-key"]' "$(jq -Rs . < "$d/key")"
 sops unset secrets/home-manager/users/<u>/secrets.yaml '["ssh-public-key"]'
 cat "$d/key.pub"; shred -u "$d/key" "$d/key.pub"; rmdir "$d")
```

Expected: the printed public line is what Task 2 records as `signingKey`; `ssh-to-age` of it is absent from `.sops.yaml`.

- [ ] **Step 3: Operator forge registration (1.4)**

```bash
gh auth refresh -h github.com -s admin:ssh_signing_key
gh ssh-key add <cameron-signing.pub> --type signing --title "commit signing 2026-11"
curl -s https://api.github.com/users/cameronraysmith/ssh_signing_keys | jq -r '.[].key'
```

Expected: the new key and `…INdO9…sqSGyUH+` are both listed. Janette's is registered on `janetteasmith` by the user or by Janette and checked the same way.

- [ ] **Step 4: Operator worker vars (1.5)**

```bash
(set +x; set -o pipefail; sops -d --extract '["commit-signing-key"]' secrets/home-manager/users/crs58/secrets.yaml | CLAN_NO_COMMIT=1 clan vars set magnetite omnigent-cameron-signing-key/key)
(set +x; set -o pipefail; sops -d --extract '["commit-signing-key"]' secrets/home-manager/users/janettesmith/secrets.yaml | CLAN_NO_COMMIT=1 clan vars set magnetite omnigent-janettesmith-signing-key/key)
git status --short vars/shared/omnigent-*-signing-key
```

Expected: only the two `key/secret` files are modified.

## Task 2: Profile fields (2.1, 2.2)

**Files:**
- Modify: `modules/home/users/lib.nix` (meta submodule, after `sshKeys`)
- Modify: `modules/home/users/*/meta.nix`

**Interfaces:**
- Produces: `flake.users.<u>.meta.signingKey : str`, `flake.users.<u>.meta.retiredSigningKeys : [ { key : str; validBefore : null | str; } ]`.

- [ ] **Step 1: Add the options**

```nix
signingKey = lib.mkOption {
  type = lib.types.strMatching "ssh-ed25519 [A-Za-z0-9+/]+=*( .*)?";
  description = ''
    Public half of the key this person signs commits with. No host may
    authorize it for login and no secret may be encrypted to it; the
    private half is the home secret `commit-signing-key`.
  '';
};
retiredSigningKeys = lib.mkOption {
  type = lib.types.listOf (
    lib.types.submodule {
      options = {
        key = lib.mkOption { type = lib.types.strMatching "ssh-ed25519 [A-Za-z0-9+/]+=*( .*)?"; };
        validBefore = lib.mkOption {
          type = lib.types.nullOr (lib.types.strMatching "[0-9]{14}Z");
          description = "Cutover as YYYYMMDDhhmmssZ; null keeps the key accepted without a bound.";
        };
      };
    }
  );
  default = [ ];
  description = "Keys that signed this person's earlier commits, kept in allowed_signers.";
};
```

- [ ] **Step 2: Show RED**

Run: `nix eval .#users.raquel.meta.signingKey`
Expected: FAIL, "The option `…signingKey' was accessed but has no value defined".

- [ ] **Step 3: Set the values in each `meta.nix`**

```nix
signingKey = "ssh-ed25519 <new key from Task 1> <gitEmail> commit signing";
retiredSigningKeys = [
  {
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+";
    validBefore = null;
  }
];
```

Only profiles that received a new key carry a retired entry.

- [ ] **Step 4: Verify**

Run: `nix eval --json .#users --apply 'u: builtins.mapAttrs (_: v: v.meta.signingKey) u'`
Expected: seven entries, `cameron` equal to `crs58`, none equal in its first two fields to any `sshKeys` entry.

## Task 3: Library and home module (2.3, 2.4)

**Files:**
- Create: `modules/lib/commit-signing.nix`
- Create: `modules/home/development/vcs-signing.nix`
- Modify: `modules/home/development/git.nix:27-38`, `jujutsu.nix:175-194`, the five profiles' `sops` blocks, `ubuntu/default.nix:84-91`, `core/bitwarden.nix:34`

**Interfaces:**
- Produces: `flake.lib.allowedSigners { principal, signingKey, retiredSigningKeys } -> str`, `flake.lib.agentFreeSshKeygen pkgs -> derivation` with `meta.mainProgram = "ssh-keygen"`, `flake.modules.homeManager.vcs-signing`.

- [ ] **Step 1: The library**

```nix
{ lib, ... }:
let
  signerLine =
    principal: options: key: ''${principal} namespaces="git"${options} ${key}'';
in
{
  flake.lib.allowedSigners =
    { principal, signingKey, retiredSigningKeys }:
    lib.concatMapStrings (line: line + "\n") (
      [ (signerLine principal "" signingKey) ]
      ++ map (
        retired:
        signerLine principal (lib.optionalString (retired.validBefore != null)
          '',valid-before="${retired.validBefore}"'') retired.key
      ) retiredSigningKeys
    );

  flake.lib.agentFreeSshKeygen =
    pkgs:
    pkgs.writeShellScriptBin "ssh-keygen" ''
      unset SSH_AUTH_SOCK
      exec ${lib.getExe' pkgs.openssh "ssh-keygen"} "$@"
    '';
}
```

Run: `nix eval --raw --impure --expr 'let f = builtins.getFlake "git+file://'$PWD'"; in f.lib.allowedSigners { principal = "a@example.invalid"; signingKey = "ssh-ed25519 AAAAnew"; retiredSigningKeys = [ { key = "ssh-ed25519 AAAAold"; validBefore = null; } { key = "ssh-ed25519 AAAAolder"; validBefore = "20261201000000Z"; } ]; }'`
Expected:

```text
a@example.invalid namespaces="git" ssh-ed25519 AAAAnew
a@example.invalid namespaces="git" ssh-ed25519 AAAAold
a@example.invalid namespaces="git",valid-before="20261201000000Z" ssh-ed25519 AAAAolder
```

- [ ] **Step 2: The home module**

```nix
{ config, ... }:
{
  flake.modules.homeManager.vcs-signing =
    { config, lib, pkgs, flake, ... }:
    let
      meta = flake.users.${config.home.username}.meta;
      key = config.sops.secrets.commit-signing-key.path;
      program = lib.getExe (flake.lib.agentFreeSshKeygen pkgs);
      signers = "${config.xdg.configHome}/git/allowed_signers";
    in
    {
      key = "vanixiets/vcs-signing-home-module";
      sops.secrets.commit-signing-key.mode = "0400";
      xdg.configFile."git/allowed_signers".text = flake.lib.allowedSigners {
        principal = config.vcs.author.email;
        inherit (meta) signingKey retiredSigningKeys;
      };
      programs.git = {
        signing = { inherit key; format = "ssh"; signByDefault = true; };
        settings.gpg.ssh = { inherit program; allowedSignersFile = signers; };
      };
      programs.jujutsu.settings.signing = {
        inherit key;
        backends.ssh = { inherit program; allowed-signers = signers; };
      };
    };

  flake.modules.homeManager.development.imports = [ config.flake.modules.homeManager.vcs-signing ];
}
```

- [ ] **Step 3: Remove the old sources**

In `git.nix` delete the `signing = lib.mkIf personal (…)` block and the `gpg.ssh.allowedSignersFile` line.
In `jujutsu.nix` keep `behavior = "own"` and `backend = "ssh"` in the personal branch and delete `backends.ssh.allowed-signers` and `key`.
In crs58, janettesmith, christophersmith, raquel and tara `default.nix` delete `ssh-public-key = { };` and `templates."allowed_signers"`; in ubuntu delete `xdg.configFile."git/allowed_signers"` and its comment.
In `bitwarden.nix` delete the `ssh-add …ssh-signing-key` comment line.

- [ ] **Step 4: Verify**

Run: `nix eval --raw .#darwinConfigurations.stibnite.config.home-manager.users.crs58.programs.git.signing.key`
Expected: ends in `sops-nix/secrets/commit-signing-key`.
Run: `nix eval --raw .#darwinConfigurations.stibnite.config.home-manager.users.crs58.programs.git.settings.gpg.ssh.program`
Expected: `/nix/store/…-ssh-keygen/bin/ssh-keygen`.
Rerun Task 1 Step 1 and diff: only `gitKey`, `gitProgram`, `jjKey`, `jjProgram` and `signers` differ, on human homes only.

- [ ] **Step 5: Build and commit (2.6)**

```bash
nix build .#checks.x86_64-linux.home-manager-{crs58,christophersmith,janettesmith,raquel,ubuntu}
nix eval .#.checks.aarch64-darwin.home-manager-tara.drvPath
just lint
jj new --no-edit main -m "feat(signing): sign every commit with a dedicated key file, never through an agent"
```

Route `modules/home secrets/home-manager modules/lib/commit-signing.nix` into it with `jj squash --into <change> -u -k -- <paths>`.

## Task 4: Worker contract (3.1 to 3.3)

**Files:**
- Modify: `modules/clan/inventory/services/omnigent.nix:37`, `modules/lib/omnigent-fleet-obligations.nix:212`, `modules/checks/omnigent-workers.nix` (`inventoryCases`)

- [ ] **Step 1: Switch both sides**

```nix
signingPublicKey = meta.signingKey;
```

in `omnigent.nix:37` and, read directly from `meta`, in `declaredCredentials` at `omnigent-fleet-obligations.nix:212`.

- [ ] **Step 2: Verify and commit**

```bash
nix eval --json .#nixosConfigurations.magnetite.config.services.omnigent-host.workers --apply 'w: builtins.mapAttrs (_: x: x.credentials.expected.signingPublicKey) w'
nix build .#checks.x86_64-linux.nixos-magnetite .#checks.x86_64-linux.nixos-pyrite
nix eval .#.checks.aarch64-darwin.darwin-stibnite.drvPath
just lint
```

Expected: each value equals its owner's `signingKey`.
Commit with the `vars/shared/omnigent-*-signing-key/key/secret` files: "feat(omnigent): give workers their owner's signing key, not the login key".

## Task 5: Obligations (4.1)

**Files:**
- Modify: `modules/lib/commit-signing.nix`, `modules/checks/machines.nix:31-47`

**Interfaces:**
- Produces: `flake.lib.commitSigningObligations.{ keyMaterial, loginSources, unauthorized, homeSigningBound, workerSigningKey, failures }`.

- [ ] **Step 1: Add the obligations**

```nix
commitSigningObligations = rec {
  keyMaterial = line: lib.concatStringsSep " " (lib.take 2 (lib.splitString " " line));
  allowedFiles = [ "/etc/ssh/authorized_keys.d/%u" "%h/.ssh/authorized_keys" ];

  loginSources =
    { isDarwin, hostConfig }:
    let
      users = hostConfig.users.users;
      sshd = hostConfig.services.openssh;
      initrd = hostConfig.boot.initrd.network.ssh or { enable = false; };
      directive = line: builtins.match "[[:space:]]*(AuthorizedKeysFile|AuthorizedKeysCommand)[[:space:]]+(.*)" line;
      directives = lib.filter (d: d != null) (map directive (lib.splitString "\n" (sshd.extraConfig or "")));
    in
    {
      keys =
        lib.concatLists (lib.mapAttrsToList (name: u:
          map (key: { source = "users.users.${name}"; inherit key; }) (u.openssh.authorizedKeys.keys or [ ])) users)
        ++ lib.optionals (!isDarwin && initrd.enable) (map (key: { source = "initrd"; inherit key; }) initrd.authorizedKeys);
      unjudgeable =
        lib.concatLists (lib.mapAttrsToList (name: u:
          lib.optional ((u.openssh.authorizedKeys.keyFiles or [ ]) != [ ]) "users.users.${name}.openssh.authorizedKeys.keyFiles") users)
        ++ lib.optionals (!isDarwin) (
          lib.optional ((initrd.authorizedKeyFiles or [ ]) != [ ]) "boot.initrd.network.ssh.authorizedKeyFiles"
          ++ lib.optional (sshd.authorizedKeysCommand != "none") "services.openssh.authorizedKeysCommand"
          ++ lib.optional (lib.any (f: !lib.elem f allowedFiles) sshd.authorizedKeysFiles) "services.openssh.authorizedKeysFiles")
        ++ lib.optional (lib.any (d: lib.elemAt d 0 == "AuthorizedKeysCommand"
            || lib.any (f: f != "" && !lib.elem f allowedFiles) (lib.splitString " " (lib.elemAt d 1))) directives)
          "services.openssh.extraConfig";
    };

  unauthorized =
    { isDarwin, hostConfig, signingKeys }:
    let
      sources = loginSources { inherit isDarwin hostConfig; };
      banned = map keyMaterial signingKeys;
    in
    sources.unjudgeable == [ ] && !lib.any (s: lib.elem (keyMaterial s.key) banned) sources.keys;

  homeSigningBound =
    { home, meta, program }:
    let
      key = home.sops.secrets.commit-signing-key.path or null;
      jj = home.programs.jujutsu.settings.signing or { };
      line = options: k: "${meta.gitEmail} namespaces=\"git\"${options} ${k}\n";
      expectedSigners =
        line "" meta.signingKey
        + lib.concatMapStrings (r: line (if r.validBefore == null then "" else ",valid-before=\"${r.validBefore}\"") r.key) meta.retiredSigningKeys;
    in
    key != null
    && home.programs.git.signing.key == key
    && home.programs.git.signing.format == "ssh"
    && (jj.key or null) == key
    && (home.programs.git.settings.gpg.ssh.program or null) == program
    && (jj.backends.ssh.program or null) == program
    && (home.xdg.configFile."git/allowed_signers".text or null) == expectedSigners;

  workerSigningKey =
    { expected, ownerMeta, loginKeys }:
    expected.signingPublicKey == ownerMeta.signingKey
    && !lib.elem (keyMaterial expected.signingPublicKey) (map keyMaterial loginKeys);

  failures =
    name: hostConfig:
    let
      isDarwin = lib.hasSuffix "-darwin" config.flake.lib.machineSystems.${name};
      users = config.flake.users;
      workers = lib.attrValues (hostConfig.services.omnigent-host.workers or { });
      signing = lib.filter (w: w.credentials.signingKey.enable) workers;
      homes = lib.filterAttrs (n: _: users ? ${n}) (hostConfig.home-manager.users or { });
      program = lib.getExe (config.flake.lib.agentFreeSshKeygen hostConfig._module.args.pkgs);
      loginKeys = lib.concatMap (u: u.meta.sshKeys) (lib.attrValues users);
    in
    lib.optional (!unauthorized {
      inherit isDarwin hostConfig;
      signingKeys = lib.mapAttrsToList (_: u: u.meta.signingKey) users
        ++ map (w: w.credentials.expected.signingPublicKey) signing;
    }) "signingKeyUnauthorized"
    ++ lib.optional (!lib.all (n: homeSigningBound { home = homes.${n}; meta = users.${n}.meta; inherit program; }) (lib.attrNames homes)) "homeSigningBound"
    ++ lib.optional (!lib.all (w: workerSigningKey { inherit (w.credentials) expected; ownerMeta = users.${w.owner}.meta; inherit loginKeys; }) signing) "workerSigningKey";
};
```

`homeSigningBound` assembles its expected signers text itself rather than calling `allowedSigners`, so a renderer defect is not reproduced in its expectation; `program` is compared by identity, and its behaviour is tested in Task 6.

- [ ] **Step 2: Show RED**

Run: `nix eval --impure --expr 'let f = builtins.getFlake "git+file://'$PWD'"; c = f.nixosConfigurations.cinnabar.config; in f.lib.commitSigningObligations.unauthorized { isDarwin = false; hostConfig = c // { users = c.users // { users = c.users.users // { root = c.users.users.root // { openssh.authorizedKeys = c.users.users.root.openssh.authorizedKeys // { keys = [ f.users.crs58.meta.signingKey ]; }; }; }; }; }; signingKeys = [ f.users.crs58.meta.signingKey ]; }'`
Expected: `false`.

- [ ] **Step 3: Assert per machine**

In `machines.nix`, beside `unmetDeployRecord`:

```nix
unmetSigning = self.lib.commitSigningObligations.failures name machineConfig;
```

and extend the `assertMsg` condition with `&& unmetSigning == [ ]` and its message with `; commitSigningObligations [${lib.concatStringsSep ", " unmetSigning}]`.

- [ ] **Step 4: Verify**

Run: `nix build .#checks.x86_64-linux.nixos-{cinnabar,electrum,galena,magnetite,pyrite}` and `nix eval .#.checks.aarch64-darwin.darwin-{argentum,blackphos,rosegold,stibnite}.drvPath`
Expected: success.

- [ ] **Step 5: Add the worker mutant to `omnigent-worker-inventory`**

In `modules/checks/omnigent-workers.nix` `inventoryCases`:

```nix
expectedLoginKey =
  !config.flake.lib.commitSigningObligations.workerSigningKey {
    expected.signingPublicKey = lib.head config.flake.users.cameron.meta.sshKeys;
    ownerMeta = config.flake.users.cameron.meta;
    loginKeys = lib.concatMap (u: u.meta.sshKeys) (lib.attrValues config.flake.users);
  };
```

Run: `nix build .#checks.x86_64-linux.omnigent-worker-inventory`
Expected: success; with the leading `!` removed locally, FAIL naming `expectedLoginKey`.

## Task 6: The check (4.2)

**Files:**
- Create: `modules/checks/commit-signing-key.nix`

- [ ] **Step 1: Write the check**

```nix
{ config, lib, self, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      o = config.flake.lib.commitSigningObligations;
      users = config.flake.users;
      keyMaterial = o.keyMaterial;
      loginKeys = lib.concatMap (u: u.meta.sshKeys) (lib.attrValues users);
      apart = meta: allLogin:
        !lib.elem (keyMaterial meta.signingKey) (map keyMaterial (allLogin ++ map (r: r.key) meta.retiredSigningKeys));
      fixtureKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureSigningKeyFixtureSigningKeyFixture0 fixture";
      host = { root ? [ ], user ? [ ], initrd ? [ ], keyFiles ? [ ], command ? "none", extra ? "AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u" }: {
        users.users = {
          root.openssh.authorizedKeys = { keys = root; keyFiles = [ ]; };
          person.openssh.authorizedKeys = { keys = user; inherit keyFiles; };
        };
        boot.initrd.network.ssh = { enable = true; authorizedKeys = initrd; authorizedKeyFiles = [ ]; };
        services.openssh = { authorizedKeysCommand = command; authorizedKeysFiles = [ "/etc/ssh/authorized_keys.d/%u" ]; extraConfig = extra; };
      };
      denies = h: !o.unauthorized { isDarwin = false; hostConfig = h; signingKeys = [ fixtureKey ]; };
      cases = {
        profilesApart = lib.all (u: apart u.meta loginKeys) (lib.attrValues users);
        signingKeyIsLoginKey = !apart (users.crs58.meta // { signingKey = lib.head users.crs58.meta.sshKeys; }) loginKeys;
        signingKeyIsRecommentedLoginKey = !apart (users.crs58.meta // { signingKey = "${keyMaterial (lib.head users.crs58.meta.sshKeys)} other"; }) loginKeys;
        signingKeyIsOthersLoginKey = !apart (users.crs58.meta // { signingKey = lib.head users.janettesmith.meta.sshKeys; }) loginKeys;
        unauthorizedControl = !denies (host { user = [ (lib.head users.crs58.meta.sshKeys) ]; });
        keyInAccount = denies (host { user = [ fixtureKey ]; });
        keyInRoot = denies (host { root = [ fixtureKey ]; });
        keyInInitrd = denies (host { initrd = [ fixtureKey ]; });
        keyRecommented = denies (host { user = [ "${keyMaterial fixtureKey} other" ]; });
        keyFilesPresent = denies (host { keyFiles = [ "/etc/extra" ]; });
        commandPresent = denies (host { command = "/bin/true"; });
        extraFilePresent = denies (host { extra = "AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u /etc/extra"; });
      } // homeCases;
      failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) cases);
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.commit-signing-key =
        assert lib.assertMsg (failed == [ ]) "commit-signing-key cases failed: ${lib.concatStringsSep ", " failed}";
        pkgs.runCommand "commit-signing-key" {
          nativeBuildInputs = [ pkgs.openssh pkgs.ssh-to-age pkgs.jq pkgs.yq-go ];
          signingKeys = lib.concatMapStrings (u: u.meta.signingKey + "\n") (lib.attrValues users);
          passAsFile = [ "signingKeys" ];
          tree = lib.fileset.toSource {
            root = ../..;
            fileset = lib.fileset.unions [ ../../.sops.yaml ../../sops ../../secrets ../../vars ];
          };
        } ''
          ${agentTest}
          ${validBeforeTest}
          ${recipientScan}
          touch $out
        '';
    };
}
```

`homeCases` holds `ubuntuHomeBound` (`o.homeSigningBound` over `self.homeConfigurations."ubuntu@x86_64-linux".config` with ubuntu's meta and `lib.getExe (config.flake.lib.agentFreeSshKeygen pkgs)`), `homeControl`, and the mutants `homeDarwinBranch`, `homeNoProgram`, `homeJjRadicleKey` and `homeMissingRetired`, each a synthetic `{ sops.secrets.commit-signing-key.path; programs.git.signing; programs.git.settings.gpg.ssh.program; programs.jujutsu.settings.signing; xdg.configFile."git/allowed_signers".text; }` attrset differing from the control in one field.

- [ ] **Step 2: The runtime parts**

```bash
# agentTest
export HOME=$TMPDIR; cd $TMPDIR
ssh-keygen -q -t ed25519 -N '' -C test -f key
ssh-agent -d -a "$TMPDIR/agent.sock" 2> agent.log & agent=$!
for _ in $(seq 50); do test -S agent.sock && break; sleep 0.1; done
SSH_AUTH_SOCK=$TMPDIR/agent.sock ssh-add -c key
echo payload > msg
before=$(wc -l < agent.log)
SSH_AUTH_SOCK=$TMPDIR/agent.sock ${lib.getExe (config.flake.lib.agentFreeSshKeygen pkgs)} -Y sign -f key -n git msg
test "$(wc -l < agent.log)" -eq "$before" || { echo "agent-free program contacted the agent"; exit 1; }
rm msg.sig; before=$(wc -l < agent.log)
SSH_AUTH_SOCK=$TMPDIR/agent.sock ssh-keygen -Y sign -f key -n git msg || true
test "$(wc -l < agent.log)" -gt "$before" || { echo "mutant: plain ssh-keygen did not contact the agent"; exit 1; }
kill $agent

# validBeforeTest
ssh-keygen -q -t ed25519 -N '' -f old; ssh-keygen -Y sign -f old -n git msg
printf 'a@example.invalid namespaces="git",valid-before="20260101000000Z" %s\n' "$(cut -d' ' -f1-2 old.pub)" > signers
P=${lib.getExe (config.flake.lib.agentFreeSshKeygen pkgs)}
$P -Y verify -f signers -I a@example.invalid -n git -s msg.sig -Overify-time=20251231000000Z < msg
! $P -Y verify -f signers -I a@example.invalid -n git -s msg.sig -Overify-time=20260102000000Z < msg

# recipientScan
ssh-to-age < "$signingKeysPath" | sort -u > signing.age
test -s signing.age
{
  grep -oE 'age1[0-9a-z]{58}' "$tree/.sops.yaml"
  jq -r '.[].publickey' "$tree"/sops/users/*/key.json "$tree"/sops/machines/*/key.json
  find "$tree/secrets" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | xargs -0 -n1 yq -e '.sops.age[].recipient'
  find "$tree/vars" -type f -name secret -print0 | xargs -0 -n1 jq -er '.sops.age[].recipient'
} | sort -u > recipients
test -s recipients
if comm -12 signing.age recipients | grep .; then echo "a signing key is a sops recipient"; exit 1; fi
{ cat recipients; head -n1 signing.age; } | sort -u > fixture
comm -12 signing.age fixture | grep -q . || { echo "mutant: recipient scan missed a planted recipient"; exit 1; }
```

`xargs`, `yq -e` and `jq -e` exit non-zero on a file they cannot parse, which fails the build (fail closed).
`ssh-to-age` reads one key per line; if the pinned version reads only one, loop over lines instead.

- [ ] **Step 3: Verify the check and each mutant**

Run: `nix build .#checks.x86_64-linux.commit-signing-key`
Expected: success.
For each case, locally negate its expression and rebuild; Expected: FAIL naming that case.
For the runtime parts, locally replace the agent-free program with plain `ssh-keygen` in the first invocation; Expected: FAIL "agent-free program contacted the agent".

## Task 7: Documentation and commit 3 (4.3, 4.4)

- [ ] **Step 1: README and amendment**

In `modules/clan/services/omnigent/README.md`, state that a worker's signing key is its owner's `meta.signingKey`, filled from the owner's `commit-signing-key`, and that `commitSigningObligations.workerSigningKey` regulates it.
Append to `docs/notes/development/omnigent/deployment-plan.md`:

```markdown
## Commit signing key amendment, <date>

Worker signing generators are filled from the owner's `commit-signing-key`, a key no host authorizes for login, instead of `ssh-signing-key`.
The signing pipelines in the enrollment sequence above now read `sops -d --extract '["commit-signing-key"]'` from the owner's file.
See `openspec/changes/separate-commit-signing-from-login/`.
```

- [ ] **Step 2: Verify and commit**

```bash
just lint
nix eval --json '.#.checks.x86_64-linux' --apply builtins.attrNames | jq -r '.[]' | sort > /tmp/after
jq -r '.[]' "$XDG_STATE_HOME/agent-logs/vanixiets/checks-x86_64-linux-before.json" | sort | comm -13 - /tmp/after
openspec validate separate-commit-signing-from-login --strict
```

Expected: the `comm` output is exactly `commit-signing-key`; validate reports the change valid.
Commit: "feat(checks): regulate that no signing key admits a login or opens a secret".

## Task 8: Deploy, cutover and integration (groups 5 to 7)

Operator-run; follow tasks.md 5.1 to 7.3 in order.
The phase B commit changes each `validBefore = null;` to the authored UTC time and narrows the option type:

```nix
validBefore = lib.mkOption { type = lib.types.strMatching "[0-9]{14}Z"; };
```

Expected after phase B: `nix eval` of Cameron's signers text shows `valid-before="<cutover>"`, and `nix build .#checks.x86_64-linux.commit-signing-key` succeeds.

## Self-review

- Spec coverage: behavioral requirements map to Tasks 2 to 6 and tasks 5.x to 7.x; the forge requirement has no automated check by design.
- Placeholders: `<new key from Task 1>`, `<date>` and `<cutover>` are operator-supplied values, not missing design.
- Names: `commitSigningObligations`, `agentFreeSshKeygen`, `allowedSigners`, `homeSigningBound`, `workerSigningKey`, `signingKeyUnauthorized` and `commit-signing-key` match the interface spec.

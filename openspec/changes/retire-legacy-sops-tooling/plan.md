# Retire legacy sops tooling implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

<!--
Procedural note: the interactive `superpowers:writing-plans` handoff was not run; this plan was
written by the session that wrote tasks.md, following that skill's structure, and stops for
operator review before any apply. It decomposes tasks.md group by group with the same numbering:
tasks.md task 2.3 is Task 2 Step 3 here where the mapping is one to one.
-->

**Goal:** Narrow operator-credential readers, delete the pre-clan `sops-*` tooling and the random-key `setup-user` path, add a public-data correspondence check, a bridge-recipient assertion and a darwin machine-key guard, and bring the docs to the current arrangement.

**Architecture:** `.sops.yaml` loses the retired anchors and narrows the operator-credential rule; `update-all-keys` plus `sops rotate` apply it. `flake.lib.darwinHostKeys` becomes the one source of darwin host keys for known-hosts and the new `checks.x86_64-linux.sops-correspondence`. `hm-sops-bridge` asserts bridge recipients per NixOS host. The `.#darwin` app compares the host's installed machine key with the repository's before `nh` runs.

**Tech Stack:** nix flakes with flake-parts and import-tree; clan-core vars; sops 3.13.3; sops-nix; ssh-to-age 1.3.0; age; yq-go and jq; just; nh.

**Spec:** `openspec/changes/retire-legacy-sops-tooling/` — `design.md` (D1–D11), `specs/secret-custody`, `specs/secret-custody-interface`, `specs/world-assumptions` (A116–A121).

## Global Constraints

- Group 1 lands first and alone in its commit (D15/D16 first).
- Never print a private key, a decrypted value or a key-store item; compare decryptions by exit status or digest in one shell; temporary key files only under `umask 077` in `$TMPDIR`, removed in the same command.
- Do not touch `~/.config/sops/age/keys.txt` (D21); reading it to select a line by its public key (task 1.6) writes nothing back.
- Do not rotate credential values (D16).
- No Bitwarden client choice or self-hosting (D18).
- nix-managed outputs are verified by `nix eval`, `nix build` or instantiation; never by reading source.
- Vendored-consumer grounding: `sops encrypt` reading stdin needs `--filename-override` ("Required when reading from stdin", `sops encrypt --help` line 29, sops 3.13.3); `--input-type binary --output-type binary` as the current recipe uses; `age-keygen -y <file>` prints one public key per identity line.
- Long or output-heavy commands: `<command> 2>&1 | tee logs/<identifier>-$(date +%Y%m%d-%H%M%S).log`.

## Task 1: Readers of operator credentials

**Files:** `.sops.yaml`, `secrets/shared.yaml`, `secrets/test.yaml` (re-encrypted only).

- [ ] **Step 1:** Record recipients: `fd -t f . secrets -E '.*' -x sh -c 'printf "%s " "$1"; case "$1" in *.yaml) yq -r ".sops.age[].recipient" "$1";; *) jq -r ".sops.age[].recipient" "$1";; esac | sort | tr "\n" " "; echo' _ {} | sort | tee logs/sops-recipients-before-$(date +%Y%m%d-%H%M%S).log`; record `sops -d <f> | sha256sum` and `yq .sops.mac <f>` for the two files in verify.md.
- [ ] **Step 2:** Edit `.sops.yaml`: remove lines 17–20's `&stibnite` and `&orb-nixos` entries and rewrite the block comment; rewrite line 9's comment; delete the `secrets/hosts/stibnite/` and `secrets/hosts/orb-nixos/` rules; in the operator-credential rule keep only `*admin` and `*admin-user`; in the fallback rule remove `*stibnite` and `*orb-nixos`; on the raquel, janettesmith, christophersmith, tara and ubuntu home-manager rules replace `*dev` with `*admin-user`; delete the `&dev` anchor (line 3) and every remaining `*dev`; rewrite the bridge-rule comment to name `admin-user` alone. Run the three `rg`/`yq` checks of task 1.2.
- [ ] **Step 3:** `just update-all-keys 2>&1 | tee logs/update-all-keys-$(date +%Y%m%d-%H%M%S).log` (it decrypts each file's data key through the operator's keys.txt, which still holds the `&dev` line, so the five home files re-wrap before `&dev` is gone from them); then `git diff --stat -- secrets/` and re-run Step 1 into an "after" log; diff the two logs.
- [ ] **Step 4:** `sops rotate --in-place secrets/shared.yaml` and the same for `secrets/test.yaml`; compare MAC and plaintext digest with Step 1.
- [ ] **Step 5:** Consumer checks of task 1.5: `sops -d … >/dev/null; echo $?`, `just check-secrets`, `sops exec-env secrets/shared.yaml true`, the recipient comparison for the six home files and two bridge files, and the two `nix eval … toplevel.drvPath`.
- [ ] **Step 6:** Negative control of task 1.6 in one shell: `umask 077; d=$(mktemp -d); while IFS= read -r l; do case "$l" in AGE-SECRET-KEY-*) p=$(printf '%s\n' "$l" | age-keygen -y); [ "$p" = "$DEV" ] && printf '%s\n' "$l" > "$d/dev"; [ "$p" = "$ADMIN_USER" ] && printf '%s\n' "$l" > "$d/au";; esac; done < ~/.config/sops/age/keys.txt; for f in $(git ls-files secrets | rg -v '/\.'); do case "$f" in *.enc) t="--input-type binary --output-type binary";; *) t="";; esac; SOPS_AGE_KEY_FILE=$d/dev sops -d $t "$f" >/dev/null 2>&1; a=$?; SOPS_AGE_KEY_FILE=$d/au sops -d $t "$f" >/dev/null 2>&1; echo "$f dev=$a admin-user=$?"; done; rm -rf "$d"`, with `DEV=age1js028xag70wpwpp47elpq50mjjv7zn7sxuwuhk8yltkjzqzdvq5qq8w8cy` (the former anchor) and `ADMIN_USER` the `&admin-user` key. Expect every line `dev=` non-zero and `admin-user=0`.
- [ ] **Step 7:** Confirm `secrets/clusters/local/*` recipients equal Step 1's minus `&dev`, including `&ci`.
- [ ] **Step 8:** Commit group 1 on its own: `jj` path-scoped to `.sops.yaml secrets/`, message `sops: narrow operator-credential readers, retire dev and retired host keys`.

## Task 2: Correspondence check and bridge assertion

**Files:** create `modules/lib/darwin-host-keys.nix`, `modules/checks/sops-correspondence.nix`; modify `modules/system/ssh-known-hosts.nix`, `modules/nixos/hm-sops-bridge.nix`.

- [ ] **Step 1:** Capture the known-hosts JSON of task 2.1 for stibnite and magnetite into a log.
- [ ] **Step 2:** Create `modules/lib/darwin-host-keys.nix` with `flake.lib.darwinHostKeys = { blackphos = "ssh-ed25519 …"; stibnite = …; argentum = …; rosegold = …; };` copied from `ssh-known-hosts.nix`; replace the four literals there with `config.flake.lib.darwinHostKeys.<host>` (thread `config` into the module's arguments). Re-run Step 1 and diff: identical.
- [ ] **Step 3:** Write `modules/checks/sops-correspondence.nix` following `commit-signing-key.nix`'s shape: `perSystem` with `lib.optionalAttrs (system == "x86_64-linux")`; the static classification table of design D4 as a Nix attrset; `passAsFile` for a TSV of `<anchor>\t<ssh pubkey>` for user anchors, `<clan user>\t<ssh pubkey>` for clan users, `<anchor>\t<ssh pubkey>` for host keys, and lists of machine, runner and recovery names; `tree = lib.fileset.toSource { root = ../..; fileset = unions [ ../../.sops.yaml ../../sops/users ../../sops/machines ../../secrets ]; }`; a shell function `verify_tree <dir>` that (a) maps anchors with `yq '.keys[] | anchor + " " + .'`, (b) compares each class, (c) for each rule in order builds the alias list with `yq '.creation_rules[i].key_groups[0].age[] | alias'`, (d) for each file under `secrets/` except dotfiles picks the first rule whose `path_regex` matches under `jq -e --arg p "$rel" '$p | test($re)'` and compares sorted recipient sets, (e) fails on unclassified anchors, classified names without anchors and empty scans, and (f) prints counts.
- [ ] **Step 4:** In the same derivation, `verify_tree "$tree"` must succeed; then for each of the seven mutants (including `&dev` reintroduced) copy `$tree` to `$TMPDIR/m<i>`, apply one defect with `yq -i` or `rm`, and require `! verify_tree "$TMPDIR/m<i>"`, printing "mutant <name> failed as expected". Build: `nix build .#checks.x86_64-linux.sops-correspondence -L`.
- [ ] **Step 5:** Real-tree negative control of task 2.3 in a scratch copy (`cp -r` of the working tree to `$TMPDIR`, edit `&tara-user`, `nix build path:$TMPDIR/…#checks.x86_64-linux.sops-correspondence` fails naming `tara-user`); remove the scratch copy.
- [ ] **Step 6:** Task 2.4's `rg` and `nix eval`.
- [ ] **Step 7:** In `hm-sops-bridge.nix`, extend `assertions` with, per user, `lib.elem machinePub bridgeRecipients` where `machinePub = (builtins.head (builtins.fromJSON (builtins.readFile (inputs.self + "/sops/machines/${config.clan.core.settings.machine.name}/key.json")))).publickey` and `bridgeRecipients = map (r: r.recipient) (builtins.fromJSON (builtins.readFile (inputs.self + "/secrets/bridge/${userCfg.sopsIdentity}-age-key.enc"))).sops.age`; message per design D5. Confirm the machine-name option path by `nix eval .#nixosConfigurations.pyrite.config.clan.core.settings.machine.name` before relying on it.
- [ ] **Step 8:** Evaluate the six NixOS toplevels; run the scratch negative control of task 2.5.
- [ ] **Step 9:** `direnv exec . prek run --files <the four files>`; commit.

## Task 3: Darwin activation guard

**Files:** modify `modules/darwin/app.nix`.

- [ ] **Step 1:** In the `perSystem` `let`, build `machineKeys = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (host: _: let s = ../../sops/secrets + "/${host}-age.key/secret"; k = ../../sops/machines + "/${host}/key.json"; in if builtins.pathExists s then (builtins.head (builtins.fromJSON (builtins.readFile k))).publickey else null) config.flake.darwinConfigurations)` — attribute names come from `darwinConfigurations`, whose names are static; values are file reads. Confirm `nix eval` of this attrset prints stibnite, rosegold, argentum only.
- [ ] **Step 2:** Render it into the script as a `case "$hostname" in <host>) expected=<key>;; esac` block via `lib.concatStrings (lib.mapAttrsToList …)`; add `pkgs.age` to `runtimeInputs`.
- [ ] **Step 3:** After argument parsing and before the `cat <<-EOF` banner: detect `--dry` in `"$@"`; if `expected` is set, `key_file=${MACHINE_KEY_FILE:-/var/lib/sops-nix/key.txt}`; `actual=$(sudo age-keygen -y "$key_file" 2>/dev/null || true)`; if empty or different, print host, expected, actual-or-"missing", and "Install it with: clan vars upload $hostname", then `exit 1` unless dry.
- [ ] **Step 4:** Task 3.1 and 3.2 verifications on stibnite, including the throwaway mismatch: `t=$(mktemp); age-keygen -o "$t" 2>/dev/null; MACHINE_KEY_FILE=$t nix run .#darwin -- stibnite . --dry; rm -f "$t"` (prints only public keys).
- [ ] **Step 5:** `direnv exec . prek run --files modules/darwin/app.nix`; commit.
- [ ] **Step 6 [operator]:** Task 3.4 on argentum.

## Task 4: Retire the legacy tooling

**Files:** `justfile`, delete `scripts/sops/`, delete `modules/apps/bootstrap/setup-user.{nix,sh}`, modify `Makefile`, `modules/apps/bootstrap/bootstrap.sh`, `.github/workflows/cd.yaml`.

- [ ] **Step 1:** Delete `justfile:1938-2003` (from `# Extract key details from Bitwarden` through `sops-rotate`'s last line); add the `update-all-keys` comment of task 4.1; `just --summary` check.
- [ ] **Step 2:** Delete `scripts/sops/` (all five scripts); task 4.2's `rg` runs after Task 6.
- [ ] **Step 3:** Replace the `provision-bridge-key` body (`justfile:2015-2055`) per design D7: keep its argument signature and `bw`/`BW_SESSION` checks; `target=…; mkdir -p secrets/bridge; tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT; bw get item "{{bw_item}}" 2>/dev/null | jq -er '.sshKey.privateKey' | ssh-to-age -private-key | sops encrypt --filename-override "$target" --input-type binary --output-type binary /dev/stdin > "$tmp"; jq -e '.sops.age | length > 0' "$tmp" >/dev/null; mv "$tmp" "$target"`; keep the public-key echo.
- [ ] **Step 4:** Task 4.3's scratch test: scratch dir with `.sops.yaml` (`creation_rules: [{path_regex: secrets/bridge/.*, key_groups: [{age: [<throwaway age pub>]}]}]`), a `bw` shim script on `PATH` printing `{"sshKey":{"privateKey":…,"publicKey":…}}` from a throwaway `ssh-keygen -t ed25519 -N ""`, `BW_SESSION=x`; run `just --justfile <repo>/justfile --working-directory <scratch> provision-bridge-key test`; decrypt with the throwaway age key and compare digests with `ssh-to-age -private-key < throwaway`; then corrupt the scratch rule's recipient and confirm non-zero exit, unchanged target digest, and `rg -l 'AGE-SECRET-KEY-' <scratch>` empty; remove the scratch dir.
- [ ] **Step 5:** Delete `modules/apps/bootstrap/setup-user.{nix,sh}`, the Makefile `setup-user` target (`Makefile:338-359`) and lines 7 and 80, `justfile:442-447`, `bootstrap.sh:59`'s hint, and the two `cd.yaml` steps (`run make setup-user`, `verify age key generated`); rewrite `Makefile:365` to point at the secrets guide's workstation-key procedure. Run task 4.4's checks; commit.
- [ ] **Step 6:** Delete the `npmbw` line from `modules/home/shell/aliases.nix`; run task 4.5's checks; commit.

## Task 5: Orphaned user secrets

- [ ] **Step 1 [operator]:** Present task 5.1's key-name list through the `wizard` skill; record the operator's per-file decision in verify.md.
- [ ] **Step 2:** For each "migrate" decision: `sops set <dest> '["<key>"]' "$(sops -d --extract '["<key>"]' <src> | jq -Rs .)"` in one shell without echoing; compare digests (task 5.2).
- [ ] **Step 3:** Delete `secrets/users/`, the four rules and the `hash-encrypt` and `verify-hash` recipes (`justfile:1448-1512`, from `hash-encrypt`'s comment through `verify-hash`'s last line); run task 5.3's checks; commit.

## Task 6: Documentation

- [ ] **Step 1:** Re-read each passage in design.md's documentation table at its current line numbers (they may have shifted) before editing.
- [ ] **Step 2:** Rewrite `guides/secrets-management.md` around design D8 and its three procedures (task 6.1); confirm each named recipe with `just --summary` and each path with `test -e`.
- [ ] **Step 3:** Tasks 6.2–6.8 in order, one commit per page group.
- [ ] **Step 4:** Task 6.9's sweep; `just docs-build 2>&1 | tee logs/docs-build-sops-$(date +%Y%m%d-%H%M%S).log` and the link check.

## Task 7: Integration verification

- [ ] **Step 1:** Task 7.1's three checks in one `nix build`.
- [ ] **Step 2:** `clan vars check <m>` for each directory in `sops/machines/`.
- [ ] **Step 3:** Ten toplevel `drvPath` evaluations.
- [ ] **Step 4:** `just activate` on stibnite with the operator present; read the fleet notification topics since the start and attribute each post.
- [ ] **Step 5:** Open the pull request; confirm nixbot contexts on its head.
- [ ] **Step 6:** Task 7.6: deploy one bridged NixOS host with `clan machines update` and check its sops and home-manager units; read the notification topics since the deploy.
- [ ] **Step 7:** Task 7.7, at archive time only: merge the designation table with `stand-up-renovate-on-magnetite`'s rows and any added to main.

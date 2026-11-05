### Task 3: The generator, the operator's steps and pull request 1

Implements `tasks.md` 2.6–2.8 (design D5, D6, Migration Plan steps 1–2; FAI `The ping URL travels only as a credential read on stdin`; WA `A55 — The operator's mailbox is reached without the fleet`).
This is the second part of pull request 1.
Steps 1 and 3 are gated on the operator; no agent reads, prints or logs the ping URL.

**Files:**
- Modify: `modules/machines/nixos/cinnabar/fleet-alert.nix` (the module's arguments, `:8`; the generator and the option, after `services.fleet-alert.deadman`, `:24-27`)
- Create (by `clan vars generate` with `CLAN_NO_COMMIT=1`, then committed into pull request 1): `vars/per-machine/cinnabar/fleet-deadman-ping/ping-url/secret`, `vars/per-machine/cinnabar/fleet-deadman-ping/curl-config/secret`
- Create (git-ignored): `logs/cam76-evidence/2.6-check-<ts>.log`, `logs/cam76-evidence/2.7-vars-<ts>.log`, `logs/cam76-evidence/2.8-eval-<ts>.log`, `logs/cam76-evidence/2.8-cost-<ts>.log`, `logs/cam76-evidence/2.8-check-<ts>.log`, `logs/cam76-evidence/2.8-pr-<ts>.log`

**Interfaces:**
- Consumes: the option `services.fleet-alert.deadman.pingConfigFile` and its assertion (Task 2 Step 5).
- Produces: cinnabar's evaluated `fleet-deadman.service` with `FLEET_DEADMAN_PING_CONFIG` and `external-ping`, deployed by Task 4.

- [ ] **Step 1: Gated, the operator creates the check (tasks.md 2.6)**

Ask the operator to do the following in healthchecks.io's web interface, and to reply with the check's name, period, grace and the email integration's domain, never the URL:

1. Sign up at https://healthchecks.io/ on the free plan.
2. In the project's Integrations, keep or add the Email integration to an address whose mail is hosted off the fleet, and confirm it.
3. Add a check named `fleet-deadman cinnabar`, schedule "Simple", period 5 minutes, grace 10 minutes, with the email integration enabled.
4. Copy the check's ping URL in its UUID form, `https://hc-ping.com/<uuid>`, not the slug form.

Record the reply in `logs/cam76-evidence/2.6-check-$(/bin/date -u +%Y%m%dT%H%M%SZ).log`.

Expected: name `fleet-deadman cinnabar`, period 5 min, grace 10 min, one email integration on a domain hosted off the fleet; the check shows "new" until its first ping.

- [ ] **Step 2: The generator and the option on cinnabar (tasks.md 2.7)**

In `modules/machines/nixos/cinnabar/fleet-alert.nix`, change the inner module's arguments to `{ config, lib, pkgs, ... }` and add after `services.fleet-alert.deadman`:

```nix
      # The external watch's ping URL (CAM-76, design D5): a bearer
      # credential, entered once by the operator at a hidden prompt, kept as
      # a curl configuration that fleet-deadman loads as external-ping and
      # curl reads on stdin.
      clan.core.vars.generators.fleet-deadman-ping = {
        prompts.ping-url = {
          description = ''
            healthchecks.io ping URL of the check that watches fleet-deadman,
            in its UUID form https://hc-ping.com/<uuid>. Anyone holding it can
            keep the check up, so it is entered here and nowhere else.
          '';
          type = "hidden";
          persist = true;
          display = {
            group = "fleet-alert";
            label = "healthchecks.io ping URL";
          };
        };
        files.ping-url.deploy = false;
        files.curl-config = { };
        runtimeInputs = [ pkgs.gnugrep ];
        script = ''
          url=$(cat "$prompts/ping-url")
          if ! printf '%s' "$url" | grep -Eqx 'https://hc-ping\.com/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}'; then
            echo "fleet-deadman-ping: the value is not a healthchecks.io ping URL of the form https://hc-ping.com/<uuid>" >&2
            exit 1
          fi
          printf 'url = "%s"\n' "$url" > "$out/curl-config"
        '';
      };

      services.fleet-alert.deadman.pingConfigFile =
        config.clan.core.vars.generators.fleet-deadman-ping.files.curl-config.path;
```

Run `jj st --no-pager >/dev/null`.
Then, gated, ask the operator to run, in `$REPO`, before pull request 1 opens:

```bash
CLAN_NO_COMMIT=1 clan vars generate cinnabar --generator fleet-deadman-ping
```

first entering `https://hc-ping.com/not-a-uuid` at the prompt and confirming that the generation fails with the generator's message, then running it again and entering the real URL.
`CLAN_NO_COMMIT=1` leaves the var files in the working copy, so they go into pull request 1 with the generator and the option.
The order matters: until the var exists, clan evaluates its path as `/no-such-path`, so a merged configuration without the var files gives `fleet-deadman` `LoadCredential=external-ping:/no-such-path`, and any cinnabar deploy from main would fail the dead-man on every run.
Then record, without printing any secret:

```bash
L=logs/cam76-evidence/2.7-vars-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ls vars/per-machine/cinnabar/fleet-deadman-ping/ping-url/secret vars/per-machine/cinnabar/fleet-deadman-ping/curl-config/secret 2>&1 | tee "$L"
jj diff --stat --no-pager vars/ | tee -a "$L"
```

Expected: both files exist; the diff names only `vars/per-machine/cinnabar/fleet-deadman-ping/`; the operator's report of the first, failed attempt is recorded in the log.

- [ ] **Step 3: Evaluate, format and open pull request 1 (tasks.md 2.8)**

```bash
L=logs/cam76-evidence/2.8-eval-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix eval --raw .#nixosConfigurations.cinnabar.config.system.build.toplevel.drvPath 2>&1 | tee "$L"
nix eval --json .#nixosConfigurations.cinnabar.config.systemd.services.fleet-deadman.serviceConfig.LoadCredential 2>&1 | tee -a "$L"
nix eval --json .#nixosConfigurations.cinnabar.config.systemd.services.fleet-deadman.environment.FLEET_DEADMAN_PING_CONFIG 2>&1 | tee -a "$L"
C=logs/cam76-evidence/2.8-cost-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
for c in fleet-alert nixos-cinnabar; do
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/$c-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.$c.drvPath >/dev/null
  jq -r --arg c "$c" '[$c, .gc.totalBytes, .cpuTime] | @tsv' /tmp/$c-stats.json | tee -a "$C"
done
nix build --option builders "$(grep 930f /etc/nix/machines | head -1)" .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee logs/cam76-evidence/2.8-check-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | grep -E '^ok:|mutant|FAIL'
P=logs/cam76-evidence/2.8-pr-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix fmt 2>&1 | tee "$P"
nix fmt -- --fail-on-change 2>&1 | tee -a "$P"
```

Expected: a `.drv` path; `LoadCredential` lists `alerter-token:…` and `external-ping:/run/secrets/vars/per-machine/cinnabar/fleet-deadman-ping/curl-config` (or the path clan evaluates for it, never a `/nix/store` path and never `/no-such-path`, which means the generation above has not run); the environment value `"%d/external-ping"`; the check's cost below 536,870,912 B; the check passes with every leg and mutant line; `nix fmt -- --fail-on-change` exits 0.
When a part of the check was already built, its leg lines come from `nix build --rebuild -L` on magnetite, recorded in the same `2.8-check` log.
Commit the generator, the option and the vars as one change, `Give cinnabar's alert dead-man the external heartbeat check's ping URL`, push Task 2's and this change as pull request 1, titled "Ping an external heartbeat check from the alert dead-man", its description stating in words the legs and mutants that passed and that the ping URL is held only in sops, and enqueue it once nixbot is green, including `fleet-alert` and `nixos-cinnabar`.

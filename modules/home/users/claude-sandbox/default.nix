{ ... }:
let
  content =
    {
      config,
      lib,
      pkgs,
      flake,
      ...
    }:
    let
      # The package the devshell's shellHook runs, so a cloud session compiles
      # with the same compiler and records the same compile key.
      apmContextCompile = flake.packages.${pkgs.stdenv.hostPlatform.system}.apm-context-compile;

      # Compiles each attached repository's context (D3). Claude Code adds a
      # SessionStart hook's stdout to the model's context, so this prints
      # nothing and records one line per repository in the bootstrap report's
      # run.log instead. It always exits 0, and it bounds each compile so the
      # hook ends well inside Claude Code's hook timeout. `--if-stale` makes a
      # resumed session, which runs SessionStart again, a no-op. `--auto` picks
      # the repository's own tier because ~/.claude/CLAUDE.md is present.
      repoContextHook = pkgs.writeShellApplication {
        name = "claude-sandbox-repo-context";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          log_dir=${lib.escapeShellArg config.vanixiets.sandbox.bootstrapReport.directory}
          compile=${lib.getExe apmContextCompile}
          deadline=$((SECONDS + 40))

          record() {
            mkdir -p "$log_dir" 2>/dev/null &&
              printf '%s repo-context %s\n' "$(date -u +%FT%TZ)" "$*" >>"$log_dir/run.log" 2>/dev/null
          }

          found=0
          for manifest in /home/user/*/apm.yml; do
            [[ -f $manifest ]] || continue
            found=1
            repo=''${manifest%/apm.yml}
            left=$((deadline - SECONDS))
            if ((left < 5)); then
              record "repo=$repo skipped=deadline" || true
              continue
            fi
            start=$SECONDS
            if out=$(cd "$repo" && timeout "$((left < 20 ? left : 20))" "$compile" --auto --if-stale 2>&1 </dev/null); then
              rc=0
            else
              rc=$?
            fi
            tier=none key=
            if [[ -r $repo/.agents/.context-compile-key ]] && read -r key <"$repo/.agents/.context-compile-key"; then
              tier=''${key##* }
            fi
            if ((rc == 0)); then
              record "repo=$repo rc=0 tier=$tier secs=$((SECONDS - start))" || true
            else
              last=''${out##*$'\n'}
              record "repo=$repo rc=$rc tier=$tier secs=$((SECONDS - start)) error=''${last:0:200}" || true
            fi
          done
          ((found)) || record "repos=0 under /home/user with apm.yml" || true
          exit 0
        '';
      };

      # Installs D5's secrets at session start, the first point at which
      # SOPS_AGE_KEY exists (A172); activation never decrypts (see
      # sopsInstallWithoutSystemd.atActivation below). The install itself is the
      # sandbox aggregate's session-env.sh, sourced by store path: it seeds the
      # key into the tmpfs sopsDir and runs sops-nix's install, and its stamp
      # makes a resumed session, which runs SessionStart again, a no-op. Claude
      # Code adds a SessionStart hook's stdout to the model's context, so this
      # prints nothing, records one line in the bootstrap report's run.log naming
      # the paths it found installed (never a value), and always exits 0.
      sopsDir = config.vanixiets.sandbox.sopsDir;
      installedPaths =
        map (template: template.path) (lib.attrValues config.sops.templates)
        ++ map (secret: secret.path) (lib.attrValues config.sops.secrets);
      sessionSecretsHook = pkgs.writeShellApplication {
        name = "claude-sandbox-session-secrets";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          log_dir=${lib.escapeShellArg config.vanixiets.sandbox.bootstrapReport.directory}

          record() {
            mkdir -p "$log_dir" 2>/dev/null &&
              printf '%s session-secrets %s\n' "$(date -u +%FT%TZ)" "$*" >>"$log_dir/run.log" 2>/dev/null
          }

          if [[ -z ''${SOPS_AGE_KEY:-} ]]; then
            record "skipped=no SOPS_AGE_KEY" || true
            exit 0
          fi

          (
            set +euo pipefail
            # shellcheck disable=SC1091
            . ${config.xdg.configFile."vanixiets/session-env.sh".source}
          ) </dev/null >/dev/null 2>&1 || true

          status=none
          if [[ -r ${sopsDir}/session-install.stamp ]]; then
            read -r status <${sopsDir}/session-install.stamp || status=unreadable
          fi
          if [[ $status == ok ]]; then
            installed=()
            for path in ${lib.escapeShellArgs installedPaths}; do
              [[ -e $path ]] && installed+=("$path")
            done
            record "status=ok rendered=$(IFS=,; printf '%s' "''${installed[*]}")" || true
          else
            record "status=$status log=${sopsDir}/session-install.log" || true
          fi
          exit 0
        '';
      };
    in
    {
      home.stateVersion = "23.11";

      # The identity default for a linux user is /home/<user>; root's is /root.
      home.username = lib.mkForce "root";
      home.homeDirectory = lib.mkForce "/root";

      vanixiets.sandbox.sopsDir = "/dev/shm/claude-sandbox-sops";

      sops = {
        defaultSopsFile = ../../../../secrets/home-manager/users/claude-sandbox/secrets.yaml;
        secrets = {
          linear-api-key-personal = { };
          linear-api-key-work = { };
          linear-workspace-personal = { };
          linear-workspace-work = { };
        };
        templates."linear-credentials.toml" = flake.lib.mkLinearCredentialsTemplate config;
      };

      # The setup step activates before the session exists, cannot read
      # SOPS_AGE_KEY (A172), and its result is snapshotted (R6), so activation
      # carries no install step; sessionSecretsHook installs at session start.
      sopsInstallWithoutSystemd.atActivation = false;

      # The cloud environment's setup script (`nix run .#claude-sandbox-setup-script`)
      # activates as root, and a controller session reads this report back.
      vanixiets.sandbox.bootstrapReport.enable = true;

      # vcs-author's default looks up flake.users.<home.username>, and root is no
      # flake user.
      vcs.author = flake.lib.vcsAuthor flake.users.claude-sandbox.meta;

      # Enabled so the skill corpus links into ~/.claude/skills and the hooks
      # land in ~/.claude/settings.json. The package is null because the cloud
      # harness installs and runs its own claude, and settings are merged into a
      # writable file rather than linked, because the harness and Claude Code
      # both write beside or into it.
      programs.claude-code = {
        enable = true;
        package = null;
        mutableSettings = true;
        settings.hooks.SessionStart = [
          {
            hooks = [
              {
                type = "command";
                command = lib.getExe sessionSecretsHook;
              }
              {
                type = "command";
                command = lib.getExe repoContextHook;
              }
            ];
          }
        ];
      };

      # Cloud sessions clone attached repositories under /home/user, so ghq
      # puts acquired ones beside them rather than in /root/ghq.
      programs.git.settings.ghq.root = "/home/user/ghq";

      programs.openspec.enable = true;
      programs.uv.enable = true;

      # Required tools with no standalone home module; each is installed for
      # other profiles by an aggregate (database, security, development,
      # publishing) that brings much more.
      home.packages = [
        pkgs.age
        pkgs.d2
        pkgs.duckdb
        pkgs.mermaid-cli
        pkgs.sops
      ];
    };
in
{
  flake.users.claude-sandbox.contentPrivate = content;
}

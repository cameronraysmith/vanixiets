{
  # OUTER: Flake-parts module signature
  ...
}:
let
  content =
    {
      # INNER: Home-manager module signature
      config,
      pkgs,
      flake, # from extraSpecialArgs
      ...
    }:
    {
      home.stateVersion = "23.11";

      home.packages =
        with pkgs;
        [
          gh # GitHub CLI (keep from baseline)
        ]
        ++ [
          flake.inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.niks3
        ];

      # Inject linear-cli's bundled skills (38 linear-*/SKILL.md subdirs) and the
      # vendored OpenSpec 1.3.1 skills (4 openspec-*/SKILL.md subdirs) into all
      # agent destinations, scoped to this user. linear-cli .src is the
      # fetchFromGitHub store path; its top-level skills/ dir is read by
      # readSkillsFrom in the ai module. The openspec assets are committed
      # generated output regenerated via modules/home/ai/openspec/regen.sh.
      aiSkills.extraSkillDirs = [
        "${pkgs.linear-cli.src}/skills"
        (flake.inputs.self + "/modules/home/ai/openspec/assets/skills")
      ];

      # Symlink the vendored OpenSpec opsx slash commands into ~/.claude/commands/opsx/.
      # The assets dir holds commands/opsx/{explore,propose,apply,archive}.md.
      programs.claude-code.commandsDir = flake.inputs.self + "/modules/home/ai/openspec/assets/commands";

      # Deliver the vendored superpowers-bridge OpenSpec schema bundle user-global so
      # `openspec schemas` lists it and `openspec new --schema superpowers-bridge` resolves it.
      # recursive = true is REQUIRED: OpenSpec's schema discovery skips directory SYMLINKS
      # (listSchemas gates on dirent.isDirectory(), false for a symlinked dir), so we use
      # home-manager's lndir (recursive) to materialize a real dir with symlinked file leaves,
      # which discovery enumerates and reads through fine. A bare `.source` symlink is invisible
      # to `openspec new --schema ...` ("Unknown schema"). See assets/schemas/README.md.
      home.file.".local/share/openspec/schemas/superpowers-bridge" = {
        source = flake.inputs.self + "/modules/home/ai/openspec/assets/schemas/superpowers-bridge";
        recursive = true;
      };

      # Declaratively manage OpenSpec's global user config so the runtime CLI uses the
      # custom profile with all 11 workflows, matching the vendored full-workflow assets.
      # OpenSpec reads $XDG_CONFIG_HOME/openspec/config.json (else ~/.config/openspec/config.json),
      # validated by GlobalConfigSchema (a .passthrough() zod object). The workflows ARRAY can
      # only be written by the interactive `openspec config profile` TUI; `openspec config set`
      # cannot set it. So we deliver the JSON directly rather than seeding via the CLI.
      #
      # Delivery: xdg.configFile = a pure, read-only symlink into the nix store. This is safe
      # because the only code path that writes config.json on ordinary (read) commands is the
      # telemetry preAction hook, which writes solely to add a missing telemetry.noticeSeen or
      # telemetry.anonymousId, and only when telemetry is enabled. Both writers are wrapped in
      # try/catch, so a failed write on a read-only file is swallowed and the command still
      # succeeds (empirically verified with @fission-ai/openspec@1.3.1). We pre-set both
      # telemetry fields here (fixed anonymousId) so no write is ever even attempted. profile,
      # delivery, and the workflows array are the user-facing settings and are read directly.
      xdg.configFile."openspec/config.json".text = builtins.toJSON {
        featureFlags = { };
        profile = "custom";
        delivery = "both";
        workflows = [
          "propose"
          "explore"
          "new"
          "continue"
          "apply"
          "ff"
          "sync"
          "archive"
          "bulk-archive"
          "verify"
          "onboard"
        ];
        telemetry = {
          noticeSeen = true;
          anonymousId = "00000000-0000-0000-0000-000000000000";
        };
      };

      # sops-nix configuration for crs58/cameron user
      # 15 secrets: development + ai + shell aggregates
      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/crs58/secrets.yaml";
        secrets = {
          github-token = { };
          ssh-signing-key = {
            mode = "0400";
          };
          ssh-public-key = { }; # For allowed_signers generation
          glm-api-key = { };
          firecrawl-api-key = { };
          huggingface-token = { };
          cerebras-api-key = { };
          linear-api-key-personal = { };
          linear-api-key-work = { };
          linear-workspace-personal = { };
          linear-workspace-work = { };
          context7-api-key = { };
          bitwarden-email = { };
          atuin-key = { };
          mcp-agent-mail-bearer-token = { };
          honcho-api-key = { };
          git-credentials = {
            mode = "0400"; # Read-only: prevent git credential-store from modifying
            path = "${config.home.homeDirectory}/.git-credentials";
          };
          aws-credentials = {
            mode = "0600"; # AWS SDK requires 600 for credentials file
            path = "${config.home.homeDirectory}/.aws/credentials";
          };
          niks3-auth-token = {
            path = "${config.xdg.configHome}/niks3/auth-token";
          };
        };

        # Generate allowed_signers file using sops.templates
        # Simpler than activation script - uses same pattern as rbw and mcp-servers
        templates."allowed_signers" = {
          mode = "0400";
          path = "${config.xdg.configHome}/git/allowed_signers";
          content = ''
            ${flake.users.crs58.meta.email} namespaces="git" ${config.sops.placeholder."ssh-public-key"}
          '';
        };

        # schpet/linear-cli inline-format credentials, rendered immutably from sops.
        # Inline format: flat `<workspace> = "<api-key>"` keys plus a top-level
        # `default = "<workspace>"` (see schpet credentials.ts hasInlineKeys /
        # parseInlineCredentials). schpet uses XDG on darwin too (Deno reads
        # XDG_CONFIG_HOME, else ~/.config), so no per-platform path conditional.
        # Read-only (0400): switch profiles via `--workspace` / a `default` change,
        # never via mutating `linear auth` commands which would clobber this file.
        templates."linear-credentials.toml" = {
          mode = "0400";
          path = "${config.xdg.configHome}/linear/credentials.toml";
          content = ''
            default = "${config.sops.placeholder."linear-workspace-personal"}"

            ${config.sops.placeholder."linear-workspace-personal"} = "${config.sops.placeholder."linear-api-key-personal"}"
            ${config.sops.placeholder."linear-workspace-work"} = "${config.sops.placeholder."linear-api-key-work"}"
          '';
        };

        # Note: Radicle keys deployed via home.file below (not sops.templates due to pure eval path issues)
      };

      # Deploy radicle public key (not secret - can be plaintext, but identity-bound)
      # This is the SSH public key used for Radicle node identity
      home.file.".radicle/keys/radicle.pub".text = ''
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+ ${flake.users.crs58.meta.email}
      '';

      # Note: Radicle signing key linked via activation script in radicle.nix
      # Cannot use home.file.source with sops.secrets.path due to pure eval mode restrictions
      # TODO: Investigate sops-nix symlink option or activation script approach

      programs.git.settings = {
        user.name = flake.users.crs58.meta.fullname;
        user.email = flake.users.crs58.meta.email;
      };

      programs.jujutsu.settings.user = {
        name = flake.users.crs58.meta.fullname;
        email = flake.users.crs58.meta.email;
      };
    };
in
{
  flake.users.crs58.contentPrivate = content;
}

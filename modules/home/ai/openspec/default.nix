# User-level install of the vendored OpenSpec 1.3.1 Claude assets:
#   - 11 skills (assets/skills/openspec-*/SKILL.md) into all agent destinations
#   - 11 opsx slash commands (assets/commands/opsx/*.md) for claude-code
#   - the superpowers-bridge schema bundle, delivered user-global
#   - the global openspec config.json pinned to the 11-workflow custom profile
#
# Opt-in member of the homeManager.ai aggregate: the config applies only to
# users who set programs.openspec.enable = true (e.g. crs58). The assets are
# committed generated output, regenerated via the openspec-refresh-vendored-artifacts
# flake app (`nix run .#openspec-refresh-vendored-artifacts`).
{ ... }:
{
  flake.modules.homeManager.ai =
    {
      config,
      pkgs,
      lib,
      flake,
      ...
    }:
    let
      cfg = config.programs.openspec;
      assetsDir = flake.inputs.self + "/modules/home/ai/openspec/assets";
    in
    {
      options.programs.openspec.enable = lib.mkEnableOption "the vendored OpenSpec user-level Claude assets (skills, opsx commands, schema bundle, and global config.json)";

      config = lib.mkIf cfg.enable {
        # Inject the vendored OpenSpec 1.3.1 skills (11 openspec-*/SKILL.md subdirs)
        # into all agent destinations. Merges with any other aiSkills.extraSkillDirs
        # contributors (e.g. crs58's linear-cli skills) via the list-merge in
        # modules/home/ai/skills/default.nix.
        aiSkills.extraSkillDirs = [ (assetsDir + "/skills") ];

        # Symlink the vendored OpenSpec opsx slash commands into ~/.claude/commands/opsx/.
        # The assets dir holds commands/opsx/*.md (11 workflows).
        programs.claude-code.commandsDir = assetsDir + "/commands";

        # Deliver the vendored superpowers-bridge OpenSpec schema bundle user-global so
        # `openspec schemas` lists it and `openspec new --schema superpowers-bridge` resolves it.
        # recursive = true is REQUIRED: OpenSpec's schema discovery skips directory SYMLINKS
        # (listSchemas gates on dirent.isDirectory(), false for a symlinked dir), so we use
        # home-manager's lndir (recursive) to materialize a real dir with symlinked file leaves,
        # which discovery enumerates and reads through fine. A bare `.source` symlink is invisible
        # to `openspec new --schema ...` ("Unknown schema"). See assets/schemas/README.md.
        home.file.".local/share/openspec/schemas/superpowers-bridge" = {
          source = assetsDir + "/schemas/superpowers-bridge";
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
        #
        # Keep the workflows list in sync with openspec-refresh-vendored-artifacts.sh's sandbox config.json (both bake the
        # same 11-workflow custom profile).
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
      };
    };
}

# The Devin CLI as a member of the ai aggregate: the packaged CLI plus its
# declaratively rendered user configuration. `services.devin-worker`, in
# worker.nix, turns a host into Outposts execution capacity and shares this
# aspect.
#
# Both parts are home-manager rather than system modules because a Devin
# session runs as a user, with that user's permissions, credentials, and --
# on macOS -- that user's desktop session. Nothing about it belongs to a
# system-wide service manager, and home-manager is the layer that reaches
# every host in this repository where the user exists.
#
# config.json is a managed copy rewritten from `settings` each activation;
# only the CLI-owned `version` key survives from the previous file.
{ config, ... }:
{
  flake.modules.homeManager.ai = {
    imports = [ config.flake.modules.homeManager.devin ];
  };

  flake.modules.homeManager.devin =
    let
      managedConfigsModule = config.flake.modules.homeManager.managedConfigs;
    in
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.devin;

      jsonFormat = pkgs.formats.json { };

      # Only documented keys from
      # https://docs.devin.ai/cli/reference/configuration/config-file
      # are emitted, and a null-valued option emits no key at all so the CLI
      # keeps its own default rather than being pinned to a value this module
      # invented.
      dropNull = lib.filterAttrs (_: v: v != null);

      agentSection = dropNull { model = cfg.model; };

      declared = dropNull {
        agent = if agentSection == { } then null else agentSection;
        auto_update = cfg.autoUpdate;
        notify = cfg.notify;
        theme_mode = cfg.themeMode;
        attribution = cfg.attribution;
      };
    in
    {
      imports = [ managedConfigsModule ];

      options.programs.devin = {
        enable = lib.mkEnableOption "the Devin CLI with a declaratively rendered user configuration";

        package = lib.mkPackageOption pkgs "devin-cli" { };

        model = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "swe-1-6-fast";
          description = ''
            Default model for local CLI sessions, rendered as `agent.model`.
            Null leaves the key unset, so the CLI applies its own default.

            Model names are not enumerated here: the available set is an
            account-level property that changes upstream, and a Nix-side enum
            would reject a newly published model until this module caught up.
          '';
        };

        autoUpdate = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether the CLI may download and activate new releases in the
            background, rendered as `auto_update`.

            Off by default because this CLI comes from the Nix store, where
            the binary is read-only and the version is a property of the
            generation. Upstream's background updater promotes a new version
            by swapping a `current` symlink in a self-managed installation it
            owns; under Nix there is no such installation to promote into, and
            a worker service silently running a different build than the one
            its generation declares is exactly the drift this repository
            exists to prevent. `nix run .#update-devin-cli` is the update
            path.
          '';
        };

        notify = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "never"
              "smart"
              "always"
            ]
          );
          default = null;
          description = ''
            Terminal notification policy when a session finishes or needs
            input, rendered as `notify`. Null leaves the key unset.
          '';
        };

        themeMode = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "light"
              "dark"
              "terminal-dark"
              "terminal-light"
              "nocolor"
            ]
          );
          default = null;
          description = ''
            Colour theme, rendered as `theme_mode`. Null leaves the key unset,
            which is upstream's auto-detect behaviour.
          '';
        };

        attribution = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = ''
            Whether commits and pull requests the agent creates carry Devin
            attribution, rendered as `attribution`. Null leaves the key unset.
          '';
        };

        settings = lib.mkOption {
          type = jsonFormat.type;
          default = { };
          example = lib.literalExpression ''
            {
              permissions.deny = [ "Exec(sudo)" ];
              keymap.global.clear_screen = "ctrl-shift-k";
            }
          '';
          description = ''
            Additional configuration merged over the keys the typed options
            above produce. This is the escape hatch for the rest of the
            documented surface -- permissions, keymap, proxy, sandbox,
            read_config_from -- without this module having to mirror every
            option upstream defines.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ cfg.package ];

        managedConfigs.devin-config = {
          target = "${config.xdg.configHome}/devin/config.json";
          format = "json";
          settings = lib.recursiveUpdate declared cfg.settings;
          appOwned = [ "version" ];
          externalPaths = [ "hooks" ];
        };
      };
    };
}

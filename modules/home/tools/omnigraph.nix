{ ... }:
{
  flake.modules.homeManager.tools =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.omnigraph;

      yaml = pkgs.formats.yaml { };
    in
    {
      options.programs.omnigraph = {
        enable = lib.mkEnableOption "the omnigraph client and its operator configuration";

        package = lib.mkPackageOption pkgs "omnigraph" { };

        settings = lib.mkOption {
          inherit (yaml) type;
          default = { };
          example = lib.literalExpression ''
            {
              version = 1;
              targets.prod = {
                kind = "server";
                endpoint = "https://graph.example.com";
                default_graph = "knowledge";
                auth = {
                  provider = "token";
                  source.store = { };
                };
              };
              defaults = {
                target = "prod";
                output = "table";
              };
              aliases.triage = {
                target = "prod";
                graph = "knowledge";
                query = "weekly_triage";
                params.limit = 20;
              };
            }
          '';
          description = ''
            Contents of the operator configuration at
            {file}`~/.omnigraph/config.yaml` — the per-person surface naming
            destinations and ergonomics, as against the team-owned
            `cluster.yaml` that declares what the system is. The keys are
            `version` (always `1`), `targets` (named destinations selected with
            `--target`, each owning its endpoint and `auth` source), `profiles`
            (managed-service identities), `defaults` (`target`, `profile`,
            `output`), and `aliases` (personal short names bound to a target,
            a graph and a stored read query). See
            <https://github.com/ModernRelay/omnigraph/blob/main/docs/user/cli/targets.md>.

            Freeform rather than typed per key: no logic in this module reads a
            key, and upstream publishes the schema
            (`docs/user/cli/operator-config.schema.json`) and checks it with
            `omnigraph config validate`. Omnigraph refuses the whole file on any
            unknown field, so a configuration written for an older CLI must be
            migrated with the package.

            Rendered to a read-only symlink into the Nix store, which omnigraph
            accepts: it keeps authentication state in the writable
            {file}`~/.omnigraph`, and only explicit configuration edits such as
            `omnigraph target add` need a writable file. A `store` token source
            lives in the OS secure store, installed with
            `omnigraph credentials set --target <name> --stdin`, which this
            module deliberately leaves unmanaged so the bearer token stays out
            of Nix.
          '';
        };

        studio = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Whether to set up OmniGraph Studio, the desktop client, which
              reads its servers from this configuration's targets and each
              bearer token from `omnigraph credentials export` at run time.
              The client also gets a link at {file}`~/.local/bin/omnigraph`:
              Studio started from the Dock, Finder or a desktop launcher does
              not inherit the login shell's {env}`PATH`, and
              {file}`~/.local/bin` is one of the fixed places it looks for the
              CLI.

              On Linux this installs the package. On macOS it does not: the
              app belongs in {file}`/Applications`, where LaunchServices
              registers its bundle identifier so that `omnigraph studio` can
              open a graph in it, and nix-darwin's `environment.casks` copies
              it there.
            '';
          };

          package = lib.mkPackageOption pkgs "omnigraph-studio" { };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          home.packages = [ cfg.package ];

          # No token may be added here. Omnigraph resolves a bearer token only
          # from the source a target's `auth` names (the secure store, a named
          # environment variable, a file or a helper command), and upstream
          # forbids tokens in this YAML. That is what makes a world-readable
          # store path an acceptable target.
          home.file.".omnigraph/config.yaml".source = yaml.generate "omnigraph-config.yaml" cfg.settings;
        })

        # Studio writes its own settings.json from its settings view, so that
        # file stays unmanaged; so does the omnigraph-studio:// link handler on
        # Linux, which would make home-manager own ~/.config/mimeapps.list.
        (lib.mkIf cfg.studio.enable {
          assertions = [
            {
              assertion = cfg.enable;
              message = "programs.omnigraph.studio.enable needs programs.omnigraph.enable: Studio reads its servers and tokens through the omnigraph CLI and its configuration.";
            }
          ];

          home.file.".local/bin/omnigraph".source = lib.getExe cfg.package;

          home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ cfg.studio.package ];
        })
      ];
    };

  # The upstream omnigraph skill, from the source tree tagged with the release
  # the client binaries come from, so it describes the deployed CLI and server.
  # This lives on the ai aggregate because aiSkills is declared there; tools
  # reaches users (christophersmith) who do not import ai, and an aiSkills
  # definition in the tools module would fail to evaluate for them.
  # Marketplace consumers install it directly from upstream instead (see the
  # companion skills in the consuming-marketplace-plugins guide).
  flake.modules.homeManager.ai-omnigraph =
    {
      config,
      options,
      lib,
      ...
    }:
    {
      aiSkills.extraSkills =
        lib.mkIf ((options.programs ? omnigraph) && config.programs.omnigraph.enable)
          {
            omnigraph = "${config.programs.omnigraph.package.skillSrc}/skills/omnigraph";
          };
    };
}

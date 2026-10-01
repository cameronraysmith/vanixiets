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
              operator.actor = "act-cameron";
              servers.prod.url = "https://graph.example.com";
              defaults = {
                server = "prod";
                default_graph = "knowledge";
                output = "table";
              };
              clusters.brain.root = "s3://acme/clusters/brain";
              profiles.staging = {
                server = "staging";
                default_graph = "knowledge";
              };
              aliases.triage = {
                server = "prod";
                graph = "knowledge";
                query = "weekly_triage";
                args = [ "since" ];
              };
            }
          '';
          description = ''
            Contents of the operator configuration at
            {file}`~/.omnigraph/config.yaml` — the per-person surface declaring
            identity and ergonomics, as against the team-owned `cluster.yaml`
            that declares what the system is. Documented keys are
            `operator.actor` (the default `--as` identity), `servers` (named
            endpoints, whose names key the stored credentials), `defaults` (the
            flat no-flag scope), `clusters` (admin-only storage roots),
            `profiles` (named scope bundles selected with `--profile`), and
            `aliases` (personal short names bound to stored queries). See
            <https://github.com/ModernRelay/omnigraph/blob/main/docs/user/cli/reference.md>.

            Freeform rather than typed per key: no logic in this module reads a
            key, and omnigraph loads unknown keys with a warning so that a file
            written for a newer CLI still works on an older one. A typed surface
            would convert that tolerance into an evaluation error.

            Rendered to a read-only symlink into the Nix store. Nothing in the
            CLI writes this file; `omnigraph login` and `omnigraph logout` write
            only {file}`~/.omnigraph/credentials`, which this module deliberately
            leaves unmanaged so the bearer token stays out of Nix.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ cfg.package ];

        # No token may be added here. Omnigraph resolves a bearer token only
        # from OMNIGRAPH_TOKEN_<NAME>, the [<name>] section of
        # ~/.omnigraph/credentials, or OMNIGRAPH_BEARER_TOKEN, and upstream
        # specifies this file as carrying "no tokens in this file, ever". That
        # is what makes a world-readable store path an acceptable target.
        home.file.".omnigraph/config.yaml".source = yaml.generate "omnigraph-config.yaml" cfg.settings;
      };
    };

  # The upstream omnigraph skill, from the same pinned source the client is
  # built from, so it always describes the deployed CLI and server version.
  # This lives on the ai aggregate because aiSkills is declared there; tools
  # reaches users (christophersmith) who do not import ai, and an aiSkills
  # definition in the tools module would fail to evaluate for them.
  # Marketplace consumers install it directly from upstream instead (see the
  # companion skills in the consuming-marketplace-plugins guide).
  flake.modules.homeManager.ai =
    {
      config,
      options,
      lib,
      ...
    }:
    {
      aiSkills.extraSkillDirs = lib.mkIf (
        (options.programs ? omnigraph) && config.programs.omnigraph.enable
      ) [ "${config.programs.omnigraph.package.src}/skills" ];
    };
}

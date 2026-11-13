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
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ cfg.package ];

        # No token may be added here. Omnigraph resolves a bearer token only
        # from the source a target's `auth` names (the secure store, a named
        # environment variable, a file or a helper command), and upstream
        # forbids tokens in this YAML. That is what makes a world-readable
        # store path an acceptable target.
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
      aiSkills.extraSkills =
        lib.mkIf ((options.programs ? omnigraph) && config.programs.omnigraph.enable)
          {
            omnigraph = "${config.programs.omnigraph.package.src}/skills/omnigraph";
          };
    };
}

{ ... }:
{
  flake.modules.homeManager.packages =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # db
        dbt-fusion
        duckdb
        turso
        # TODO: re-enable pgcli once nixpkgs ships a cli-helpers (or pygments)
        # combination whose tests pass. As of nixpkgs c4073437f5ff (PR #1893's bump),
        # python3Packages.pygments 2.19.2 -> 2.20.0 (commit fb7d51fc8529, 2026-03-30)
        # changed an ANSI style tuple, breaking 3 cli-helpers 2.10.0 pytestCheckHook
        # tests (test_style_output{,_with_newlines,_custom_tokens})
        # Re-enable when either cli-helpers is bumped past 2.10.0 with
        # pygments-2.20-compatible test expectations, or a nixpkgs overlay disables
        # the brittle tests. Track upstream nixpkgs:trunk job state:
        #   https://hydra.nixos.org/job/nixpkgs/trunk/python313Packages.cli-helpers.x86_64-linux/all
        #   https://hydra.nixos.org/job/nixpkgs/trunk/python313Packages.cli-helpers.aarch64-darwin/all
        #   https://hydra.nixos.org/job/nixpkgs/trunk/python313Packages.pgcli.x86_64-linux/all
        #   https://hydra.nixos.org/job/nixpkgs/trunk/python313Packages.pgcli.aarch64-darwin/all
        # pgcli
        postgresql_16
        sqlite
        supabase-cli
        turso-cli
      ];
    };
}

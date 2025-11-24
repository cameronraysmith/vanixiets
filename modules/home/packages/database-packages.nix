{ ... }:
{
  flake.modules.homeManager.packages =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # db
        duckdb
        turso
        pgcli
        postgresql_16
        sqlite
        supabase-cli
        turso-cli
      ];
    };
}

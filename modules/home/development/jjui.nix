{ ... }:
{
  flake.modules.homeManager.development =
    { ... }:
    {
      programs.jjui = {
        enable = true;
        settings = {
          revisions.revset = "recent(8)";
          ui.auto_refresh_interval = 10;
        };
      };
    };
}

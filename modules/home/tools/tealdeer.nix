{ ... }:
{
  flake.modules.homeManager.tools =
    { ... }:
    {
      # Disabled to minimize compilation time
      programs.tealdeer = {
        enable = false;
        settings = {
          display = {
            compact = false;
            use_pager = true;
          };
          updates = {
            auto_update = true;
          };
        };
      };
    };
}

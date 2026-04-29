{
  ...
}:
{
  flake.modules.homeManager."portable/janettesmith" =
    {
      pkgs,
      ...
    }:
    {
      home.stateVersion = "23.11";

      home.packages = with pkgs; [
        gh # GitHub CLI (keep from baseline)
        just # Command runner
        ripgrep # Fast grep alternative
        fd # Fast find alternative
        bat # Cat with syntax highlighting
        eza # Modern ls replacement
      ];
    };
}

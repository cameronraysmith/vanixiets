# darwin-specific colima home-manager integration
{
  lib,
  pkgs,
  osConfig ? null,
  config,
  ...
}:
let
  # Check if colima is enabled at the darwin system level
  colimaEnabled = if osConfig != null then osConfig.services.colima.enable or false else false;

  # Colima completion helper - runs after shell completion system is loaded
  colimaCompletions = shell: ''
    # Colima shell completions (only if colima is installed and accessible)
    if command -v colima &> /dev/null; then
      eval "$(colima completion ${shell})"
    fi
  '';

in
{
  # Only configure completions if colima is enabled at system level
  config = lib.mkIf colimaEnabled {
    # Zsh completions
    # Runs AFTER oh-my-zsh initialization (which includes compinit)
    programs.zsh.initContent = lib.mkIf config.programs.zsh.enable (colimaCompletions "zsh");

    # Bash completions
    # Runs late in bash initialization
    programs.bash.initExtra = lib.mkIf config.programs.bash.enable (colimaCompletions "bash");
  };
}

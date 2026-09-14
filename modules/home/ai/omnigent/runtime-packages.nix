{
  config,
  inputs,
  lib,
  ...
}:
{
  flake.lib.omnigentRuntimePackages =
    pkgs:
    let
      system = pkgs.stdenv.hostPlatform.system;
    in
    [
      inputs.self.packages.${system}.claude-code
      inputs.self.packages.${system}.atomic
      inputs.llm-agents.packages.${system}.codex
      inputs.llm-agents.packages.${system}.pi
      inputs.llm-agents.packages.${system}.omp
      pkgs.bun
      pkgs.nodejs_22
      pkgs.python3
      pkgs.tmux
      pkgs.git
      pkgs.uv
      pkgs.bash
      pkgs.which
      pkgs.direnv
      pkgs.nix
      pkgs.gh
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.bubblewrap
      pkgs.procps
      pkgs.lsof
    ];

  flake.lib.omnigentWorkerPath =
    {
      pkgs,
      home,
      extraPackages ? [ ],
    }:
    let
      credentials = home.programs.omnigent.workerCredentials or null;
      required = map (
        package:
        if credentials != null && credentials.githubTokens != { } && package == pkgs.gh then
          home.programs.gh.package
        else if
          credentials != null
          && credentials.claudeSetupToken != null
          && package == inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
        then
          home.programs.claude-code.package
        else
          package
      ) (config.flake.lib.omnigentRuntimePackages pkgs);
    in
    lib.makeBinPath (required ++ [ home.home.path ] ++ extraPackages);
}

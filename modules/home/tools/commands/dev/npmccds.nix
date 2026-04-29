{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "npmccds";
          runtimeInputs = with pkgs; [ bun ];
          text = ''
            exec bunx -p @anthropic-ai/claude-code@next claude --dangerously-skip-permissions "$@"
          '';
          meta.description = "Claude code with dangerous skip permissions";
        })
      ];
    };
}

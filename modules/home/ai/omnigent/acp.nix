{ inputs, lib, ... }:
{
  flake.lib.omnigentACP = pkgs: {
    agents = [
      {
        name = "Atomic";
        command = lib.getExe inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi-acp;
        omnigent_mcp = false;
        inject_system_prompt = false;
        env_passthrough = [
          "PI_ACP_PI_COMMAND"
          "PI_CODING_AGENT_DIR"
        ];
      }
      # omp v18.1.13 resolves state via PI_CODING_AGENT_DIR (oh-my-pi
      # packages/utils/src/dirs.ts:438-473); the runner sets it to
      # /home/cameron/.atomic/agent for Atomic. ACP children are deny-by-default:
      # keep env_passthrough exactly empty to exclude that override. Adding
      # PI_CODING_AGENT_DIR here would silently share Atomic state.
      {
        name = "Oh My Pi";
        command = "omp acp";
        omnigent_mcp = false;
        inject_system_prompt = false;
        env_passthrough = [ ];
      }
    ];
  };
}

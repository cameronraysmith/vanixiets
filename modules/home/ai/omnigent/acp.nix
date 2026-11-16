{ inputs, lib, ... }:
{
  # ACP children receive only omnigent's base allowlist plus env_passthrough.
  # DOCKER_HOST and CONTAINER_HOST locate a worker's rootless podman socket; without
  # them Docker-API clients fall back to the rootful socket and podman runs locally,
  # where the host unit's NoNewPrivileges prevents it from starting.
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
          "DOCKER_HOST"
          "CONTAINER_HOST"
        ];
      }
      # omp v18.1.13 resolves state via PI_CODING_AGENT_DIR (oh-my-pi
      # packages/utils/src/dirs.ts:438-473), which the runner points at Atomic's
      # state. Never pass PI_CODING_AGENT_DIR here: it would silently share Atomic
      # state. Container socket locators carry no state and are allowed.
      {
        name = "Oh My Pi";
        command = "omp acp";
        omnigent_mcp = false;
        inject_system_prompt = false;
        env_passthrough = [
          "DOCKER_HOST"
          "CONTAINER_HOST"
        ];
      }
    ];
  };
}

{ lib, ... }:
{
  flake.lib.omnigentReservedEnvironment =
    { isDarwin }:
    name:
    lib.elem name (
      [
        "HOME"
        "USER"
        "LOGNAME"
        "PATH"
        "SHELL"
        "SSH_AUTH_SOCK"
        "SSH_AGENT_PID"
        "GIT_CONFIG_GLOBAL"
        "GIT_CONFIG_SYSTEM"
        "GIT_CONFIG_COUNT"
      ]
      ++ lib.optionals isDarwin [
        "BASH_ENV"
        "ENV"
        "SKIP_SANITY_CHECKS"
        "DRY_RUN"
      ]
    )
    || lib.any (prefix: lib.hasPrefix prefix name) [
      "XDG_"
      "NIX_"
      "OMNIGENT_"
      "PI_"
      "ATOMIC_"
      "OMP_"
      "CLAUDE_"
      "CODEX_"
      "GH_"
      "LINEAR_"
      "LD_"
      "DYLD_"
    ];
}

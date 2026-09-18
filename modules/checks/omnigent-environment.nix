{ config, lib, ... }:
let
  commonReserved = [
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
    "XDG_"
    "XDG_CONFIG_HOME"
    "NIX_"
    "NIX_CONFIG"
    "OMNIGENT_"
    "OMNIGENT_RUNNER_ENV_PASSTHROUGH"
    "PI_"
    "PI_CODING_AGENT_DIR"
    "ATOMIC_"
    "ATOMIC_CODING_AGENT_DIR"
    "OMP_"
    "OMP_CODING_AGENT_DIR"
    "CLAUDE_"
    "CLAUDE_CONFIG_DIR"
    "CODEX_"
    "CODEX_HOME"
    "GH_"
    "GH_TOKEN"
    "LINEAR_"
    "LINEAR_API_KEY"
    "LD_"
    "LD_PRELOAD"
    "DYLD_"
    "DYLD_INSERT_LIBRARIES"
  ];
  darwinReserved = [
    "BASH_ENV"
    "ENV"
    "SKIP_SANITY_CHECKS"
    "DRY_RUN"
  ];
  allowed = [
    ""
    "HOME_SUFFIX"
    "USER_SUFFIX"
    "LOGNAME_SUFFIX"
    "PATH_SUFFIX"
    "SHELL_SUFFIX"
    "SSH_AUTH_SOCK_SUFFIX"
    "SSH_AGENT_PID_SUFFIX"
    "GIT_CONFIG_GLOBAL_SUFFIX"
    "GIT_CONFIG_SYSTEM_SUFFIX"
    "GIT_CONFIG_COUNT_SUFFIX"
    "XDG"
    "NIX"
    "OMNIGENT"
    "PI"
    "ATOMIC"
    "OMP"
    "CLAUDE"
    "CODEX"
    "GH"
    "LINEAR"
    "LD"
    "DYLD"
    "BASH_ENV_SUFFIX"
    "ENV_SUFFIX"
    "SKIP_SANITY_CHECKS_SUFFIX"
    "DRY_RUN_SUFFIX"
    "CUSTOM_SETTING"
  ];
  casesFor = isDarwin: {
    reserved = lib.genAttrs commonReserved (_: true);
    platform = lib.genAttrs darwinReserved (_: isDarwin);
    allowed = lib.genAttrs (allowed ++ map lib.toLower (commonReserved ++ darwinReserved)) (_: false);
  };
  failures =
    predicate:
    lib.concatMap
      (
        isDarwin:
        lib.concatMap (
          table:
          lib.mapAttrsToList (name: expected: {
            inherit isDarwin name expected;
          }) (lib.filterAttrs (name: expected: predicate { inherit isDarwin; } name != expected) table)
        ) (lib.attrValues (casesFor isDarwin))
      )
      [
        false
        true
      ];
  predicate = config.flake.lib.omnigentReservedEnvironment;
  actual = failures predicate;
  mutants = {
    exactName = platform: name: name != "HOME" && predicate platform name;
    prefix = platform: name: !(lib.hasPrefix "LD_" name) && predicate platform name;
    darwinExtra = platform: name: name != "BASH_ENV" && predicate platform name;
    linuxExtraRestriction = _: predicate { isDarwin = true; };
    disconnected = _: _: false;
  };
in
{
  perSystem = { pkgs, ... }: {
    checks.omnigent-worker-environment =
      assert lib.assertMsg (
        actual == [ ]
      ) "Omnigent reserved environment failures: ${builtins.toJSON actual}";
      assert lib.assertMsg (lib.all (mutant: failures mutant != [ ]) (
        lib.attrValues mutants
      )) "Omnigent environment oracle accepted a policy mutant";
      pkgs.runCommand "omnigent-worker-environment"
        {
          passthru = { inherit failures; };
        }
        ''
          touch "$out"
        '';
  };
}

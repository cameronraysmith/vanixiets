{ config, lib, ... }:
let
  modules = config.flake.modules.homeManager;
  runtimePackages = config.flake.lib.omnigentRuntimePackages;
in
{
  flake.modules.homeManager.omnigent-worker =
    {
      config,
      pkgs,
      flake,
      ...
    }:
    let
      home = config.home.homeDirectory;
      localPath = path: lib.hasPrefix "${home}/" path;
      foreignReference =
        value:
        let
          text = lib.replaceStrings [ "${home}/" "\"${home}\"" ] [ "$WORKER_HOME/" "\"$WORKER_HOME\"" ] (
            builtins.toJSON value
          );
        in
        builtins.match ".*[\"'[:space:]=(:]/(home|Users)/.*" text != null;
      files = lib.filterAttrs (_: file: file.enable) config.home.file;
      # Check declared configuration and activation inputs, not documentary file bodies
      # or the contents of store dependencies; this is not a runtime sandbox.
      declaredPaths = {
        environment = config.home.sessionVariables;
        path = config.home.sessionPath;
        activation = config.home.activation;
        files = lib.mapAttrs (_: file: {
          inherit (file) target;
          source = toString file.source;
        }) files;
        settings = {
          git = gitSettings;
          gitIncludes = config.programs.git.includes;
          jujutsu = config.programs.jujutsu.settings;
          atomic = config.programs.atomic.settings;
          omp = config.programs.omp.settings;
          pi = config.programs.pi-coding-agent.settings;
          claude = config.programs.claude-code.settings;
          omnigent = config.programs.omnigent.settings;
        };
      };
      gitSettings = [ config.programs.git.iniContent ] ++ lib.toList config.programs.git.settings;
      signingSetting =
        section: key: value:
        let
          name = "${lib.toLower section}.${lib.toLower key}";
          disabled =
            v:
            lib.elem (lib.toLower (toString v)) [
              ""
              "false"
              "no"
              "off"
              "0"
            ];
        in
        !builtins.isAttrs value
        && (
          (name == "user.signingkey" && lib.toList value != [ ])
          || (
            lib.elem name [
              "commit.gpgsign"
              "tag.gpgsign"
            ]
            && lib.any (v: !disabled v) (lib.toList value)
          )
        );
      gitSigning = lib.any (
        fragment:
        lib.any (
          section:
          lib.any (key: signingSetting section key fragment.${section}.${key}) (
            lib.attrNames fragment.${section}
          )
        ) (lib.attrNames fragment)
      ) gitSettings;
    in
    {
      imports = map (name: modules.${name}) [
        "omnigent"
        "agent-settings"
        "atomic"
        "omp"
        "pi"
        "ai-skills-compose"
        "ai-skills"
        "agents-md"
        "agent-context"
        "ripgrep"
        "fd"
        "direnv"
        "gh"
        "git"
        "jujutsu"
        "linear"
      ];

      # Prefer HM's configured wrappers inside the profile, not in the supervisor PATH.
      home.packages = map lib.lowPrio (runtimePackages pkgs);

      programs.claude-code = {
        enable = true;
        package = flake.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
      };

      assertions = [
        {
          assertion = (config.sops.secrets or { }) == { } && (config.sops.templates or { }) == { };
          message = "Omnigent worker capabilities must not import personal sops secrets or templates.";
        }
        {
          assertion =
            config.programs.git.signing.key == null
            && config.programs.git.signing.signByDefault != true
            && !gitSigning
            && (config.programs.jujutsu.settings.signing.key or null) == null
            && config.programs.jujutsu.settings.signing.behavior == "drop"
            && !config.programs.jujutsu.settings.git.sign-on-push;
          message = "Omnigent worker capabilities do not grant Git or Jujutsu signing authority.";
        }
        {
          assertion =
            !(config.home.sessionVariables ? SSH_AUTH_SOCK)
            && !(config.home.sessionVariables ? SSH_AGENT_PID)
            && !config.services.ssh-agent.enable;
          message = "Omnigent worker capabilities must not inherit an SSH agent or signing socket.";
        }
        {
          assertion =
            lib.all localPath [
              config.programs.atomic.configDir
              config.programs.omp.configDir
              config.programs.pi-coding-agent.configDir
              config.programs.claude-code.configDir
            ]
            && !foreignReference declaredPaths;
          message = "Omnigent worker configuration must use its own home, not a foreign human home.";
        }
      ];
    };
}

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
      osConfig ? null,
      ...
    }:
    let
      home = config.home.homeDirectory;
      # The worker's owner, the person its sessions run for (agent-session-
      # telemetry design D4), from the host's worker declaration. A default,
      # forced only where the agent-telemetry module is active and nothing
      # sets the person: the darwin worker builder, whose home has no
      # osConfig, sets it to the owner (darwin-agent-session-telemetry D10).
      workerOwners = lib.mapAttrsToList (_: worker: worker.owner) (
        lib.filterAttrs (_: worker: worker.user == config.home.username) (
          if osConfig == null then { } else osConfig.services.omnigent-host.workers or { }
        )
      );
      credentials = config.programs.omnigent.workerCredentials;
      signingKey = if credentials == null then null else credentials.signingKey;
      signingAllowed = signingKey != null;
      localPath = path: lib.hasPrefix "${home}/" path;
      foreignReference =
        value:
        let
          text = lib.replaceStrings [ "${home}/" "\"${home}\"" ] [ "$WORKER_HOME/" "\"$WORKER_HOME\"" ] (
            builtins.toJSON value
          );
        in
        # A whole-string .* match exhausts libstdc++'s stack on large configurations.
        builtins.length (builtins.split "[\"'[:space:]=(:]/(home|Users)/" text) > 1;
      files = lib.filterAttrs (_: file: file.enable) config.home.file;
      # Check declared configuration and activation inputs, not documentary file bodies
      # or the contents of store dependencies; this is not a runtime sandbox.
      declaredPaths = {
        environment = config.home.sessionVariables;
        credentialPaths = credentials;
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
          (name == "user.signingkey" && lib.any (v: !signingAllowed || v != signingKey) (lib.toList value))
          || (
            lib.elem name [
              "commit.gpgsign"
              "tag.gpgsign"
            ]
            && !signingAllowed
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
        "omnigent-worker-credentials"
        "ai-capabilities"
        "atomic"
        "omp"
        "pi"
        "agents-md"
        "agent-context"
        "cli-tools"
        "ripgrep"
        "fd"
        "direnv"
        "gh"
        "git"
        "jujutsu"
        "vcs-author"
        "neovim"
        "linear"
        "repository-acquisition"
        "engineering-tools"
        "nix-development"
        "openspec"
        "mergify"
        "secret-file-modes"
        "agent-telemetry"
      ];

      agentTelemetry.person = lib.mkDefault (
        if lib.length workerOwners == 1 then
          lib.head workerOwners
        else
          throw "Omnigent worker home ${config.home.username}: agentTelemetry.person needs exactly one services.omnigent-host.workers entry with user ${config.home.username}, found ${toString (lib.length workerOwners)}; refusing to stamp the Unix account name as the person."
      );

      # Prefer HM's configured wrappers inside the profile, not in the supervisor PATH.
      home.packages = map (
        package:
        # lowPrio ties coreutils at 10; preserve the runtime PATH's procps kill provider.
        if pkgs.stdenv.hostPlatform.isLinux && package == pkgs.procps then
          lib.setPrio 9 package
        else
          lib.lowPrio package
      ) (runtimePackages pkgs);

      programs.openspec.enable = true;

      programs.claude-code = {
        enable = true;
        package = lib.mkDefault flake.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
      };

      # As for a human (claude-code/default.nix): Claude rewrites settings.json
      # at runtime, so once settings are declared (the agent-telemetry gates)
      # it is a managed copy, not a read-only store symlink. With no declared
      # settings home-manager writes no file and the worker's own file stands.
      managedConfigs.claude-code-settings = lib.mkIf (config.programs.claude-code.settings != { }) {
        target = "${config.programs.claude-code.configDir}/settings.json";
        format = "json";
        settings = config.programs.claude-code.settings // {
          "$schema" = "https://json.schemastore.org/claude-code-settings.json";
        };
        replacesHomeFile = "${config.programs.claude-code.configDir}/settings.json";
      };

      assertions = [
        {
          assertion =
            (config.sops.secrets or { }) == { }
            && (config.sops.templates or { }) == { }
            && (config.sops.age.keyFile or null) == null;
          message = "Omnigent worker capabilities must not import personal sops secrets or templates.";
        }
        {
          assertion =
            (
              if signingAllowed then
                config.programs.git.signing.key == signingKey
                && config.programs.git.signing.format == "ssh"
                && config.programs.git.signing.signByDefault
                && config.programs.jujutsu.settings.signing.key == signingKey
                && config.programs.jujutsu.settings.signing.behavior == "own"
                && config.programs.jujutsu.settings.signing.backend == "ssh"
                && credentials.sources.signingKey.path == signingKey
              else
                config.programs.git.signing.key == null
                && config.programs.git.signing.signByDefault != true
                && (config.programs.jujutsu.settings.signing.key or null) == null
                && config.programs.jujutsu.settings.signing.behavior == "drop"
            )
            && !gitSigning
            && !(config.programs.jujutsu.settings.git ? sign-on-push)
            && (config.programs.jujutsu.settings.revsets.git-sign-on-push or "none()") == "none()";
          message =
            if signingAllowed then
              "Omnigent worker signing must use only the adapter-delivered private key."
            else
              "Omnigent worker capabilities do not grant Git or Jujutsu signing authority.";
        }
        {
          assertion =
            !(config.home.sessionVariables ? SSH_AUTH_SOCK)
            && !(config.home.sessionVariables ? SSH_AGENT_PID)
            && !config.services.ssh-agent.enable
            && lib.all (
              block:
              (block.data.forwardAgent or false) != true
              && lib.elem (lib.toLower (toString (block.data.extraOptions.ForwardAgent or "no"))) [
                ""
                "no"
                "false"
                "0"
              ]
            ) (lib.attrValues config.programs.ssh.matchBlocks)
            && lib.all (
              block:
              lib.all (
                key:
                lib.toLower key != "forwardagent"
                || lib.elem (lib.toLower (toString block.data.${key})) [
                  ""
                  "no"
                  "false"
                  "0"
                ]
              ) (lib.attrNames block.data)
            ) (lib.attrValues config.programs.ssh.settings)
            &&
              builtins.match ".*[Ff][Oo][Rr][Ww][Aa][Rr][Dd][Aa][Gg][Ee][Nn][Tt].*" config.programs.ssh.extraConfig
              == null;
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

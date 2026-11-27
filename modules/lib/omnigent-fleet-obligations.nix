# Fleet obligations Omnigent imposes on a host, expressed over that host's own
# evaluated configuration. modules/checks/machines.nix asserts them against the
# configuration its toplevel check already forces, so no host is evaluated a
# second time to read its effective worker, account and credential facts.
{ config, lib, ... }:
let
  expectedOwners = {
    magnetite = [
      "cameron"
      "janettesmith"
    ];
    pyrite = [
      "cameron"
      "janettesmith"
    ];
    stibnite = [ "cameron" ];
  };

  keychainOwners = {
    stibnite = [ "cameron" ];
  };

  serverDomains = {
    magnetite = "omni.scientistexperience.net";
  };

  # The telemetry files a flagged home writes (agent-session-telemetry design D2, D13,
  # D15; darwin-agent-session-telemetry design D13), written out here rather than read
  # from modules/home/ai/agent-telemetry.nix, so that a key the module adds or drops
  # fails. `resource` is the expected OTEL_RESOURCE_ATTRIBUTES. Shared with
  # checks.x86_64-linux.agent-telemetry-emitters.
  telemetryFiles =
    let
      telemetryName =
        name:
        lib.hasPrefix "OTEL_" name
        || lib.elem name [
          "CLAUDE_CODE_ENABLE_TELEMETRY"
          "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA"
          "ENABLE_BETA_TRACING_DETAILED"
          "BETA_TRACING_ENDPOINT"
        ];
      telemetryOf = env: lib.filterAttrs (name: _: telemetryName name) env;
      ompFile =
        home:
        let
          file = home.home.file.".omp/agent/.env" or { enable = false; };
        in
        if file.enable then file.text else null;
    in
    {
      inherit telemetryOf ompFile;
      claudeExpected = resource: {
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        CLAUDE_CODE_ENHANCED_TELEMETRY_BETA = "1";
        OTEL_METRICS_EXPORTER = "otlp";
        OTEL_LOGS_EXPORTER = "otlp";
        OTEL_TRACES_EXPORTER = "otlp";
        OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
        OTEL_EXPORTER_OTLP_ENDPOINT = "http://127.0.0.1:4318";
        OTEL_LOG_USER_PROMPTS = "1";
        OTEL_LOG_ASSISTANT_RESPONSES = "1";
        OTEL_LOG_TOOL_DETAILS = "1";
        OTEL_LOG_TOOL_CONTENT = "1";
        OTEL_BSP_MAX_QUEUE_SIZE = "64";
        OTEL_METRICS_INCLUDE_ACCOUNT_UUID = "false";
        OTEL_RESOURCE_ATTRIBUTES = resource;
      };
      # In the file's sorted order.
      ompExpected = resource: ''
        OTEL_BSP_MAX_EXPORT_BATCH_SIZE=1
        OTEL_BSP_MAX_QUEUE_SIZE=64
        OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://127.0.0.1:4318/v1/metrics
        OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
        OTEL_EXPORTER_OTLP_TIMEOUT=5000
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://127.0.0.1:4318/v1/traces
        OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=full
        OTEL_LOGS_EXPORTER=none
        OTEL_RESOURCE_ATTRIBUTES=${resource}
      '';
      claudeOf = home: telemetryOf (home.managedConfigs.claude-code-settings.settings.env or { });
      claudeProgramOf = home: telemetryOf (home.programs.claude-code.settings.env or { });
      ompTelemetryLines =
        text: lib.filter (lib.hasPrefix "OTEL_") (lib.splitString "\n" (if text == null then "" else text));
    };

  authorBound =
    {
      meta,
      expected,
      home,
    }:
    let
      git = home.programs.git.settings.user or { };
      jj = home.programs.jujutsu.settings.user or { };
    in
    meta.fullname != ""
    && (git.name or null) == meta.fullname
    && (git.email or null) == meta.gitEmail
    && (jj.name or null) == meta.fullname
    && (jj.email or null) == meta.gitEmail
    && expected.gitEmail == meta.gitEmail;

  selection = credentials: config.flake.lib.omnigentCredentialSelection credentials;

  accountObligations =
    {
      hostConfig,
      isDarwin,
      machine,
    }:
    owner:
    let
      worker = hostConfig.services.omnigent-host.workers.${owner};
      user = "omnigent-${owner}";
      account = hostConfig.users.users.${user};
      group = hostConfig.users.groups.${user};
      home = "${if isDarwin then "/Users" else "/home"}/${user}";
      memberships = lib.attrNames (
        lib.filterAttrs (_: g: lib.elem user g.members) hostConfig.users.groups
      );
      sharing = hostConfig.services.shared-reference-tree or { enable = false; };
      admittedGroups = [
        user
      ]
      ++ lib.optional (sharing.enable && lib.elem user sharing.participants) sharing.writer
      ++ lib.optional (worker.containers.incus == "restricted") "incus";
    in
    worker.owner == owner
    && worker.user == user
    && worker.hostName == "${machine}-${owner}"
    && worker.workspaceRoot == "${home}/projects"
    && !worker.autoApproveDirenv
    && worker.environment == { }
    && worker.enable
    && account.home == home
    && account.createHome
    && account.openssh.authorizedKeys.keys == [ ]
    && account.openssh.authorizedKeys.keyFiles == [ ]
    && lib.all (name: lib.elem name admittedGroups) memberships
    && lib.all (name: name == user) group.members
    && lib.all (other: other.name == user || other.home != account.home) (
      lib.attrValues hostConfig.users.users
    )
    && (
      if isDarwin then
        account.uid == 551
        && account.gid == 551
        && group.gid == 551
        && lib.elem user hostConfig.users.knownUsers
        && lib.elem user hostConfig.users.knownGroups
        && !(builtins.hasAttr user hostConfig.home-manager.users)
        && hostConfig.environment.etc ? "omnigent/workers/${owner}"
        && builtins.hasAttr "omnigent-host-${owner}" hostConfig.launchd.daemons
      else
        account.isNormalUser
        && account.group == user
        && account.extraGroups == [ ]
        && lib.elem account.homeMode [
          "700"
          "0700"
        ]
        && account.hashedPassword == "!"
        && account.hashedPasswordFile == null
        && builtins.hasAttr "omnigent-host-${owner}" hostConfig.systemd.services
    );

  linearFilesFor =
    worker: label:
    map (source: source.file) (
      lib.attrValues (
        lib.filterAttrs (name: _: lib.hasPrefix "linear-${label}-" name) (selection worker.credentials)
      )
    );

  cases =
    machine: hostConfig:
    let
      isDarwin = config.flake.lib.hosts.${machine}.class == "darwin";
      owners = expectedOwners.${machine};
      workers = hostConfig.services.omnigent-host.workers;
      declaredOwners = lib.filter (owner: workers ? ${owner}) owners;
      generators = hostConfig.clan.core.vars.generators;
      homes = map (worker: toString hostConfig.users.users.${worker.user}.home) (lib.attrValues workers);
      agentTelemetry = hostConfig.vanixiets.otelCollector.agentTelemetry or false;
    in
    {
      workerRoster =
        lib.attrNames workers == owners
        &&
          lib.filter (lib.hasPrefix "omnigent-") (lib.attrNames hostConfig.users.users)
          == map (owner: "omnigent-${owner}") owners;

      accounts = lib.all (accountObligations { inherit hostConfig isDarwin machine; }) declaredOwners;

      enablement =
        lib.all (worker: worker.enable) (lib.attrValues workers)
        && !hostConfig.services.omnigent-host.enable;

      linearRenderedOutsideHomes =
        lib.all
          (
            template:
            template.path == "/run/secrets/rendered/${template.name}"
            && !lib.any (home: lib.hasPrefix "${home}/" template.path) homes
            && template.mode == "0400"
            && lib.any (worker: worker.user == template.owner) (lib.attrValues workers)
          )
          (
            lib.attrValues (lib.filterAttrs (name: _: lib.hasPrefix "omnigent-" name) hostConfig.sops.templates)
          );

      keychainScope = lib.all (
        owner:
        (workers.${owner}.keychainEnable or false) == lib.elem owner (keychainOwners.${machine} or [ ])
      ) owners;

      keychainSecret = lib.all (
        owner:
        let
          generator = generators."omnigent-${owner}-keychain";
        in
        !generator.share
        && generator.files.password.secret
        && generator.files.password.owner == "omnigent-${owner}"
        && generator.files.password.mode == "0400"
        && generator.files.password.neededFor == "services"
      ) (keychainOwners.${machine} or [ ]);

      linearGeneratorFiles = lib.all (
        worker:
        lib.all (
          label:
          let
            generator = generators.${worker.credentials.linearApiKeys.${label}.generator};
            files = linearFilesFor worker label;
          in
          lib.attrNames generator.files == lib.sort builtins.lessThan files
          && lib.all (file: lib.hasInfix ''cp "$prompts/${file}" "$out/${file}"'' generator.script) files
        ) (lib.attrNames (lib.filterAttrs (_: key: key.enable) worker.credentials.linearApiKeys))
      ) (lib.attrValues workers);

      declaredCredentials = lib.all (
        worker:
        let
          credentials = worker.credentials;
          meta = config.flake.users.${worker.owner}.meta;
        in
        credentials.signingKey == {
          enable = true;
          generator = "${worker.user}-signing-key";
          file = "key";
        }
        && credentials.deployRequestKey.generator == "${worker.user}-deploy-request"
        && credentials.deployRequestKey.file == "key"
        &&
          credentials.githubTokens
          == lib.genAttrs ([ "sciexp" ] ++ lib.optional (worker.owner == "cameron") "cameronraysmith")
            (owner: {
              enable = true;
              generator = "${worker.user}-github-token-${owner}";
              file = "token";
              expectedLogin = meta.githubUser;
            })
        && credentials.defaultOwner == (if worker.owner == "cameron" then "cameronraysmith" else "sciexp")
        &&
          credentials.linearApiKeys
          == lib.genAttrs ([ "personal" ] ++ lib.optional (worker.owner == "cameron") "work") (label: {
            enable = true;
            generator = "${worker.user}-linear-${label}";
          })
        && !credentials.claudeSetupToken.enable
        &&
          credentials.expected == {
            gitEmail = meta.gitEmail;
            signingPublicKey = meta.signingKey;
            omnigentEmail = meta.email;
          }
        && lib.all (
          name:
          let
            source = (selection credentials).${name};
            generator = generators.${source.generator};
            file = generator.files.${source.file};
            personGenerator = config.flake.lib.commitSigningGenerator (
              config.flake.lib.signingPerson worker.owner
            );
          in
          (
            if name == "signingKey" then
              generator.prompts == { } && generator.dependencies == [ personGenerator ]
            else if name == "deployRequestKey" then
              generator.prompts == { } && !generator.files."key.pub".secret
            else
              generator.prompts.${source.file}.type == "hidden"
          )
          && generator.share
          && file.secret
          && file.neededFor == "services"
          && file.owner == worker.user
          && file.mode == "0400"
        ) (lib.attrNames (selection credentials))
      ) (lib.attrValues workers);

      serverDomain = lib.all (domain: hostConfig.services.omnigent.domain == domain) (
        lib.optional (serverDomains ? ${machine}) serverDomains.${machine}
      );

      # The supervisor runs each worker as itself, privately, with its own identity; on
      # Linux it restarts with, and requires, the worker's Home Manager activation, and
      # on Darwin it is a system daemon whose session is created only for a Keychain
      # worker. Atomic's state selectors stay out of the host environment and its
      # runner passthrough, which every generic ACP child inherits since omnigent
      # 0.23.0; the Atomic ACP command sets them (checks.omnigent-acp-spawn-env).
      supervision = lib.all (
        owner:
        let
          worker = workers.${owner};
          user = worker.user;
          home = toString hostConfig.users.users.${user}.home;
          passthrough = lib.optionals (worker.containers.engine == "rootless-podman") [
            "DOCKER_HOST"
            "CONTAINER_HOST"
          ];
          identity =
            env:
            env.HOME == home
            && env.USER == user
            && env.LOGNAME == user
            && !(env ? PI_ACP_PI_COMMAND)
            && !(env ? PI_CODING_AGENT_DIR)
            && (
              if passthrough == [ ] then
                !(env ? OMNIGENT_RUNNER_ENV_PASSTHROUGH)
              else
                env.OMNIGENT_RUNNER_ENV_PASSTHROUGH == lib.concatStringsSep "," passthrough
            );
        in
        if isDarwin then
          let
            daemon = hostConfig.launchd.daemons."omnigent-host-${owner}".serviceConfig;
            log = "${home}/.omnigent/logs/host/service.log";
          in
          daemon.UserName == user
          && daemon.Umask == 63
          && daemon.WorkingDirectory == home
          && daemon.StandardOutPath == log
          && daemon.StandardErrorPath == log
          && daemon.SessionCreate == (if worker.keychainEnable then true else null)
          && identity daemon.EnvironmentVariables
          && !(hostConfig.launchd.agents ? "omnigent-host-${owner}")
          && !(hostConfig.launchd.user.agents ? "omnigent-host-${owner}")
        else
          let
            unit = hostConfig.systemd.services."omnigent-host-${owner}";
            service = unit.serviceConfig;
            activation = "home-manager-${lib.replaceStrings [ "-" ] [ "\\x2d" ] user}.service";
          in
          service.User == user
          && service.Group == user
          && service.WorkingDirectory == home
          && service.UMask == "0077"
          && service.NoNewPrivileges
          && service.RestartPreventExitStatus == 78
          && lib.elem "SSH_AUTH_SOCK" service.UnsetEnvironment
          && lib.elem "SSH_AGENT_PID" service.UnsetEnvironment
          && identity unit.environment
          && lib.elem activation unit.requires
          && lib.elem activation unit.after
          && lib.elem hostConfig.home-manager.users.${user}.home.activationPackage unit.restartTriggers
      ) declaredOwners;

      # Where the host's row sets agentTelemetry, each worker starts after the
      # agent-session collector and waits, bounded, for its receiver: on Linux
      # ordered after and wanting otel-agent-session.service, never requiring
      # it, with the wait in ExecStartPre; on Darwin the wait in the launcher.
      # Without agentTelemetry neither (darwin-agent-session-telemetry task
      # 15.5).
      collectorOrdering =
        let
          collector = "otel-agent-session.service";
          waits =
            text:
            let
              plain = builtins.unsafeDiscardStringContext text;
            in
            builtins.replaceStrings [ "-agent-session-receiver-wait" ] [ "" ] plain != plain;
        in
        lib.all (
          owner:
          if isDarwin then
            waits hostConfig.launchd.daemons."omnigent-host-${owner}".command.text == agentTelemetry
          else
            let
              unit = hostConfig.systemd.services."omnigent-host-${owner}";
            in
            lib.elem collector unit.after == agentTelemetry
            && lib.elem collector unit.wants == agentTelemetry
            && !lib.elem collector unit.requires
            && waits unit.serviceConfig.ExecStartPre.text == agentTelemetry
        ) declaredOwners;

      # A Darwin worker's home is a standalone generation the host only references, so
      # its telemetry files are held here, where the host is evaluated anyway: where the
      # row sets agentTelemetry, exactly the expected files stamped with the owner and
      # the omnigent harness host (darwin-agent-session-telemetry design D10, D15);
      # without it, no telemetry name and no omp OTEL_ line. The Linux workers' homes
      # are held by checks.x86_64-linux.agent-telemetry-emitters.
      workerTelemetry =
        !isDarwin
        || lib.all (
          owner:
          let
            home = hostConfig.services.omnigent-host.workerHomes.${owner};
            resource = "user.name=${owner},vanixiets.harness_host=omnigent";
          in
          if agentTelemetry then
            telemetryFiles.claudeOf home == telemetryFiles.claudeExpected resource
            && telemetryFiles.ompFile home == telemetryFiles.ompExpected resource
          else
            telemetryFiles.claudeProgramOf home == { }
            && telemetryFiles.ompTelemetryLines (telemetryFiles.ompFile home) == [ ]
        ) declaredOwners;

      # Worker Home Manager consumes the delivered policy: GitHub HTTPS goes through the
      # gh credential wrapper, signing uses exactly the delivered key, Linear reads the
      # linked rendered template, and no tool-owned OAuth state is declared. Darwin worker
      # homes are standalone generations not exposed in the host configuration; the same
      # Home Manager module is exercised here through the Linux hosts.
      credentialWiring =
        isDarwin
        || lib.all (
          worker:
          let
            h = hostConfig.home-manager.users.${worker.user};
            policy = h.programs.omnigent.workerCredentials;
            relative = target: lib.removePrefix "${h.home.homeDirectory}/" target;
            oauth = [
              ".atomic/agent/auth.json"
              ".pi/agent/auth.json"
              ".omp/agent/agent.db"
              ".codex/auth.json"
              ".claude/.credentials.json"
              ".omnigent/auth_tokens.json"
            ];
            github = h.programs.git.settings.credential."https://github.com";
          in
          !lib.any (file: file.enable && lib.elem (relative file.target) oauth) (lib.attrValues h.home.file)
          && !lib.any (spec: lib.elem (relative spec.target) oauth) (lib.attrValues h.managedConfigs)
          && (
            policy == null
            || (
              (
                policy.githubTokens == { }
                || (
                  # The wrapper is named plainly "gh"; the upstream package carries its version.
                  h.programs.gh.package.name == "gh"
                  && github.useHttpPath
                  && lib.elem "${h.programs.gh.package}/bin/gh auth git-credential" github.helper
                )
              )
              && (
                policy.signingKey == null
                || (
                  h.programs.git.signing.key == policy.signingKey
                  && h.programs.git.signing.format == "ssh"
                  && h.programs.git.settings.user.email == policy.expected.gitEmail
                )
              )
              && (policy.linearApiKeys == { } || h.xdg.configFile."linear/credentials.toml".enable)
            )
          )
        ) (lib.attrValues workers);

      # Real-host credential delivery lives here rather than in a fixture check because
      # each host is evaluated once, by its own machine check. It is regex-free:
      # libstdc++'s recursive std::regex overflows the evaluator stack on long patterns
      # (store paths, commands), so text is split only on "\n", compared by whole line,
      # and searched for a substring with builtins.replaceStrings rather than lib.hasInfix.
      credentialDelivery =
        let
          credentialed = lib.filterAttrs (_: worker: selection worker.credentials != { }) workers;
          linesOf = text: lib.splitString "\n" (builtins.unsafeDiscardStringContext text);
          # Linux: SOPS installs secrets before the worker's Home Manager unit and host
          # unit start, both of which run readiness over the delivered policy, which
          # requires the rendered Linear template rather than the Home Manager link to it.
          linux =
            name: worker:
            let
              home = hostConfig.home-manager.users.${worker.user};
              policy = home.programs.omnigent.workerCredentials;
              readiness = home.home.activation.omnigentCredentialReadiness;
              hostUnit = hostConfig.systemd.services."omnigent-host-${name}";
              units = [
                hostUnit
                hostConfig.systemd.services."home-manager-${lib.replaceStrings [ "-" ] [ "\\x2d" ] worker.user}"
              ];
              installed =
                if hostConfig.sops.useSystemdActivation then
                  lib.all (
                    unit:
                    lib.elem "sops-install-secrets.service" unit.after
                    && lib.elem "sops-install-secrets.service" unit.requires
                  ) units
                else
                  hostConfig.system.activationScripts ? setupSecrets;
              preStart = linesOf hostUnit.serviceConfig.ExecStartPre.text;
              linear = hostConfig.sops.templates."omnigent-${worker.user}-linear".path;
            in
            installed
            && readiness.before == [ "writeBoundary" ]
            && lib.all (line: lib.elem line preStart) (lib.filter (line: line != "") (linesOf readiness.data))
            && (
              policy.linearApiKeys == { }
              || (lib.elem linear policy.requiredFiles && !lib.elem policy.linearCredentials policy.requiredFiles)
            );
          # Darwin: the fail-closed SOPS installer runs in the launchd activation script
          # before any worker launch daemon is loaded. The installer command is multi-line,
          # so its lines, with " || exit 1" on the last, must occur as a contiguous run of
          # whole lines, starting before nix-darwin's "setting up launchd services" banner
          # and before the first "launchctl load". That user creation precedes launchd
          # is nix-darwin's own fixed activation order, so it is not asserted here.
          darwin =
            let
              lines = linesOf hostConfig.system.activationScripts.launchd.text;
              installer = builtins.unsafeDiscardStringContext hostConfig.launchd.daemons.sops-install-secrets.command;
              expected = lib.splitString "\n" (installer + " || exit 1");
              n = lib.length expected;
              installs =
                if lib.length lines < n then
                  null
                else
                  lib.lists.findFirstIndex (i: lib.sublist i n lines == expected) null (
                    lib.range 0 (lib.length lines - n)
                  );
              contains = infix: line: builtins.replaceStrings [ infix ] [ "" ] line != line;
              loads = lib.lists.findFirstIndex (
                line: contains "setting up launchd services" line || contains "launchctl load" line
              ) null lines;
            in
            installs != null && (loads == null || installs < loads);
        in
        credentialed == { }
        || (
          if isDarwin then
            darwin
          else
            lib.all (name: linux name credentialed.${name}) (lib.attrNames credentialed)
        );
    }
    # Darwin worker homes are standalone generations absent from the host configuration;
    # the shared vcs-author module and adapter code are exercised through the Linux hosts.
    // lib.optionalAttrs (!isDarwin) {
      authorBinding = lib.all (
        worker:
        authorBound {
          meta = config.flake.users.${worker.owner}.meta;
          expected = worker.credentials.expected;
          home = hostConfig.home-manager.users.${worker.user};
        }
      ) (lib.attrValues workers);

      # ACP children receive omnigent's base allowlist, each agent's declared
      # passthrough and the host's runner passthrough, so on a host with rootless
      # container access every agent must declare the socket locators, or its sessions
      # fall back to the rootful socket and to a local podman that NoNewPrivileges
      # cannot start. Oh My Pi must still never receive PI_CODING_AGENT_DIR, which
      # points at Atomic's state; supervision keeps it out of the runner passthrough and
      # checks.omnigent-acp-spawn-env observes what each agent receives.
      acpContainerLocators =
        !lib.any (worker: worker.containers.engine == "rootless-podman") (lib.attrValues workers)
        || lib.all (
          worker:
          let
            agents = hostConfig.home-manager.users.${worker.user}.programs.omnigent.settings.acp.agents;
          in
          lib.any (agent: agent.name == "Oh My Pi") agents
          && lib.all (
            agent:
            lib.elem "DOCKER_HOST" agent.env_passthrough
            && lib.elem "CONTAINER_HOST" agent.env_passthrough
            && (agent.name != "Oh My Pi" || !lib.elem "PI_CODING_AGENT_DIR" agent.env_passthrough)
          ) agents
        ) (lib.attrValues workers);
    };
in
{
  flake.lib.omnigentFleetObligations = {
    inherit expectedOwners authorBound telemetryFiles;

    failures =
      machine: hostConfig:
      lib.optionals (expectedOwners ? ${machine}) (
        lib.attrNames (lib.filterAttrs (_: met: !met) (cases machine hostConfig))
      );
  };
}

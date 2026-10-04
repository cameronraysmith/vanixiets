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

  janetteMeta = config.flake.users.janettesmith.meta;
  janetteAuthor = {
    name = janetteMeta.fullname;
    email = janetteMeta.gitEmail;
  };

  identityBinding =
    modules:
    (lib.evalModules {
      modules = [
        {
          options.programs = lib.mkOption { type = lib.types.attrs; };
        }
      ]
      ++ modules;
    }).config == {
      programs.git.settings.user = janetteAuthor;
      programs.jujutsu.settings.user = janetteAuthor;
    };

  selection = credentials: config.flake.lib.omnigentCredentialSelection credentials;

  ownerMeta = owner: config.flake.users.${if owner == "cameron" then "crs58" else owner}.meta;

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
    && lib.all (name: name == user) memberships
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
      isDarwin = lib.hasSuffix "-darwin" config.flake.lib.machineSystems.${machine};
      owners = expectedOwners.${machine};
      workers = hostConfig.services.omnigent-host.workers;
      declaredOwners = lib.filter (owner: workers ? ${owner}) owners;
      generators = hostConfig.clan.core.vars.generators;
      homes = map (worker: toString hostConfig.users.users.${worker.user}.home) (lib.attrValues workers);
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
          meta = ownerMeta worker.owner;
        in
        credentials.signingKey == {
          enable = true;
          generator = "${worker.user}-signing-key";
          file = "key";
        }
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
            signingPublicKey = lib.head meta.sshKeys;
            omnigentEmail = meta.email;
          }
        && lib.all (
          source:
          let
            generator = generators.${source.generator};
            file = generator.files.${source.file};
          in
          generator.prompts.${source.file}.type == "hidden"
          && generator.share
          && file.secret
          && file.neededFor == "services"
          && file.owner == worker.user
          && file.mode == "0400"
        ) (lib.attrValues (selection credentials))
      ) (lib.attrValues workers);

      identityBoundHomeModules = lib.all (owner: identityBinding workers.${owner}.extraHomeModules) (
        lib.filter (owner: owner == "janettesmith") declaredOwners
      );

      identityBindingDiscriminates =
        !identityBinding [
          {
            programs.git.settings.user = janetteAuthor;
            programs.jujutsu.settings.user = janetteAuthor;
            programs.unrelated.enable = true;
          }
        ];

      serverDomain = lib.all (domain: hostConfig.services.omnigent.domain == domain) (
        lib.optional (serverDomains ? ${machine}) serverDomains.${machine}
      );

      # Real-host credential delivery lives here rather than in omnigent-worker-credentials
      # because each host is evaluated once, by its own machine check. It is regex-free:
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
    };
in
{
  flake.lib.omnigentFleetObligations = {
    inherit expectedOwners;

    failures =
      machine: hostConfig:
      lib.optionals (expectedOwners ? ${machine}) (
        lib.attrNames (lib.filterAttrs (_: met: !met) (cases machine hostConfig))
      );
  };
}

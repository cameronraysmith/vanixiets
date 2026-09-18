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
      generators = hostConfig.clan.core.vars.generators;
      homes = map (worker: toString hostConfig.users.users.${worker.user}.home) (lib.attrValues workers);
    in
    {
      workerRoster =
        lib.attrNames workers == owners
        &&
          lib.filter (lib.hasPrefix "omnigent-") (lib.attrNames hostConfig.users.users)
          == map (owner: "omnigent-${owner}") owners;

      accounts = lib.all (accountObligations { inherit hostConfig isDarwin machine; }) owners;

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

      enrollmentDiagnostics =
        let
          missing =
            worker:
            lib.any (
              source:
              !builtins.pathExists (
                hostConfig.clan.core.settings.directory + "/vars/shared/${source.generator}/${source.file}/secret"
              )
            ) (lib.attrValues (selection worker.credentials));
          expectedFailures = lib.concatMap (
            worker:
            lib.optionals (missing worker) [
              "Omnigent worker ${worker.user}: credentials require private shared services files owned by the worker with mode 0400."
              "Omnigent worker ${worker.user}: only the declared Clan vars ciphertext and delivered paths are allowed."
            ]
          ) (lib.attrValues workers);
          failures = map (a: a.message) (lib.filter (a: !a.assertion) hostConfig.assertions);
        in
        lib.sort builtins.lessThan failures == lib.sort builtins.lessThan expectedFailures;

      identityBoundHomeModules = lib.all (owner: identityBinding workers.${owner}.extraHomeModules) (
        lib.filter (owner: owner == "janettesmith") owners
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

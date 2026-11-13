# Commit signing keys: naming, the agent-free signing program, the rendered
# signers file, and the fleet obligations machines.nix asserts per host.
{ config, lib, ... }:
let
  signingPerson = username: config.flake.userAliases.${username} or username;
  commitSigningGenerator = person: "${person}-commit-signing-key";

  # Machines whose homes still sign with the login key (`ssh-signing-key`) because
  # they have no clan machine key to receive a generated var; enrolling one is a
  # prerequisite of the phase B cutover. Only these may omit the generated key.
  commitSigningLegacyMachines = [ "blackphos" ];

  signerLine =
    principal: options: key:
    ''${principal} namespaces="git"${options} ${key}'';

  allowedSigners =
    {
      principal,
      signingKey,
      retiredSigningKeys,
    }:
    lib.concatMapStrings (line: line + "\n") (
      lib.optional (signingKey != null) (signerLine principal "" signingKey)
      ++ map (
        retired:
        signerLine principal (lib.optionalString (
          retired.validBefore != null
        ) '',valid-before="${retired.validBefore}"'') retired.key
      ) retiredSigningKeys
    );

  agentFreeSshKeygen =
    pkgs:
    pkgs.writeShellScriptBin "ssh-keygen" ''
      unset SSH_AUTH_SOCK
      exec ${lib.getExe' pkgs.openssh "ssh-keygen"} "$@"
    '';

  keyMaterial = line: lib.concatStringsSep " " (lib.take 2 (lib.splitString " " line));

  allowedFiles = [
    "/etc/ssh/authorized_keys.d/%u"
    "%h/.ssh/authorized_keys"
  ];

  loginSources =
    { isDarwin, hostConfig }:
    let
      users = hostConfig.users.users;
      sshd = hostConfig.services.openssh;
      initrd = if isDarwin then { enable = false; } else hostConfig.boot.initrd.network.ssh;
      directive =
        line: builtins.match "[[:space:]]*(AuthorizedKeysFile|AuthorizedKeysCommand)[[:space:]]+(.*)" line;
      directives = lib.filter (d: d != null) (
        map directive (lib.splitString "\n" (sshd.extraConfig or ""))
      );
    in
    {
      keys =
        lib.concatLists (
          lib.mapAttrsToList (
            name: user:
            map (key: {
              source = "users.users.${name}";
              inherit key;
            }) (user.openssh.authorizedKeys.keys or [ ])
          ) users
        )
        ++ lib.optionals initrd.enable (
          map (key: {
            source = "boot.initrd.network.ssh";
            inherit key;
          }) initrd.authorizedKeys
        );
      unjudgeable =
        lib.concatLists (
          lib.mapAttrsToList (
            name: user:
            lib.optional (
              (user.openssh.authorizedKeys.keyFiles or [ ]) != [ ]
            ) "users.users.${name}.openssh.authorizedKeys.keyFiles"
          ) users
        )
        ++ lib.optionals (!isDarwin) (
          lib.optional (initrd.authorizedKeyFiles != [ ]) "boot.initrd.network.ssh.authorizedKeyFiles"
          ++ lib.optional (sshd.authorizedKeysCommand != "none") "services.openssh.authorizedKeysCommand"
          ++ lib.optional (lib.any (
            file: !lib.elem file allowedFiles
          ) sshd.authorizedKeysFiles) "services.openssh.authorizedKeysFiles"
        )
        ++ lib.optional (lib.any (
          d:
          lib.elemAt d 0 == "AuthorizedKeysCommand"
          || lib.any (file: file != "" && !lib.elem file allowedFiles) (lib.splitString " " (lib.elemAt d 1))
        ) directives) "services.openssh.extraConfig";
    };

  unauthorized =
    {
      isDarwin,
      hostConfig,
      signingKeys,
    }:
    let
      sources = loginSources { inherit isDarwin hostConfig; };
      banned = map keyMaterial signingKeys;
    in
    sources.unjudgeable == [ ]
    && !lib.any (source: lib.elem (keyMaterial source.key) banned) sources.keys;

  # The expected signers text is assembled here from `meta`, not by calling
  # `allowedSigners`, so a defect in the renderer is not reproduced in its expectation.
  homeSigningBound =
    {
      home,
      meta,
      program,
      keyPath,
    }:
    let
      jj = home.programs.jujutsu.settings.signing or { };
      line = options: key: "${meta.gitEmail} namespaces=\"git\"${options} ${key}\n";
      expectedSigners =
        lib.optionalString (meta.signingKey != null) (line "" meta.signingKey)
        + lib.concatMapStrings (
          retired:
          line (
            if retired.validBefore == null then "" else '',valid-before="${retired.validBefore}"''
          ) retired.key
        ) meta.retiredSigningKeys;
    in
    keyPath != null
    && (home.programs.git.signing.key or null) == keyPath
    && (home.programs.git.signing.format or null) == "ssh"
    && (home.programs.git.signing.signByDefault or false)
    && (jj.key or null) == keyPath
    && (jj.behavior or null) == "own"
    && (jj.backend or null) == "ssh"
    && (home.programs.git.settings.gpg.ssh.program or null) == program
    && (jj.backends.ssh.program or null) == program
    && (home.xdg.configFile."git/allowed_signers".text or null) == expectedSigners;

  personGenerator =
    { generator, owner }:
    generator != null
    && generator.share
    && generator.prompts == { }
    && generator.files.key.secret
    && generator.files.key.owner == owner
    && generator.files.key.mode == "0400"
    && !generator.files."key.pub".secret;

  workerSigningKey =
    {
      expected,
      ownerMeta,
      loginKeys,
      generator,
      person,
    }:
    ownerMeta.signingKey != null
    && expected.signingPublicKey == ownerMeta.signingKey
    && !lib.elem (keyMaterial expected.signingPublicKey) (map keyMaterial loginKeys)
    && generator.dependencies == [ (commitSigningGenerator person) ]
    && generator.prompts == { };

  # Machines a person's generated key is encrypted to, read from the committed vars tree.
  generatedFor =
    person:
    let
      dir = ../../vars/shared + "/${commitSigningGenerator person}/key/machines";
    in
    if builtins.pathExists dir then lib.attrNames (builtins.readDir dir) else [ ];

  # A person has no signing key exactly when they are on a legacy machine and no
  # machine outside the legacy list carries their generated key, so a null key
  # cannot spread beyond the list.
  signingKeyPresent =
    {
      signingKey,
      legacy,
      recipients,
    }:
    (signingKey == null)
    == (legacy && lib.all (machine: lib.elem machine commitSigningLegacyMachines) recipients);

  # A legacy machine stays listed only while it has no clan machine key.
  unenrolled = name: !builtins.pathExists (../../sops/machines + "/${name}");

  failures =
    name: hostConfig:
    let
      isDarwin = lib.hasSuffix "-darwin" config.flake.lib.machineSystems.${name};
      legacy = lib.elem name commitSigningLegacyMachines;
      users = config.flake.users;
      generators = hostConfig.clan.core.vars.generators;
      workers = lib.attrValues (hostConfig.services.omnigent-host.workers or { });
      signing = lib.filter (worker: worker.credentials.signingKey.enable) workers;
      homes = lib.filterAttrs (account: _: users ? ${account}) (hostConfig.home-manager.users or { });
      homeOwner = lib.listToAttrs (
        map (account: lib.nameValuePair (signingPerson account) account) (lib.attrNames homes)
      );
      persons = lib.unique (lib.attrNames homeOwner ++ map (worker: signingPerson worker.owner) workers);
      generatorOf = person: generators.${commitSigningGenerator person} or null;
      inherit (hostConfig.vanixiets.commitSigning) program;
      loginKeys = lib.concatMap (user: user.meta.sshKeys) (lib.attrValues users);
      keyPathOf =
        account:
        if legacy then
          homes.${account}.sops.secrets.ssh-signing-key.path or null
        else
          (generatorOf (signingPerson account)).files.key.path or null;
      cases = {
        signingKeyUnauthorized = unauthorized {
          inherit isDarwin hostConfig;
          signingKeys =
            lib.filter (key: key != null) (lib.mapAttrsToList (_: user: user.meta.signingKey) users)
            ++ map (worker: worker.credentials.expected.signingPublicKey) signing;
        };
        signingKeyPresence = lib.all (
          person:
          signingKeyPresent {
            inherit (users.${person}.meta) signingKey;
            inherit legacy;
            recipients = generatedFor person;
          }
        ) persons;
        homeSigningBound = lib.all (
          account:
          homeSigningBound {
            home = homes.${account};
            meta = users.${account}.meta;
            inherit program;
            keyPath = keyPathOf account;
          }
        ) (lib.attrNames homes);
      }
      // (
        if legacy then
          {
            legacyNoGenerator =
              signing == [ ] && !lib.any (lib.hasSuffix "-commit-signing-key") (lib.attrNames generators);
            legacyUnenrolled = unenrolled name;
          }
        else
          {
            personGenerator = lib.all (
              person:
              personGenerator {
                generator = generatorOf person;
                owner = homeOwner.${person} or "root";
              }
            ) persons;
            workerSigningKey = lib.all (
              worker:
              workerSigningKey {
                inherit (worker.credentials) expected;
                ownerMeta = users.${worker.owner}.meta;
                inherit loginKeys;
                generator = generators.${worker.credentials.signingKey.generator};
                person = signingPerson worker.owner;
              }
            ) signing;
          }
      );
    in
    lib.attrNames (lib.filterAttrs (_: met: !met) cases);
in
{
  flake.lib = {
    inherit
      signingPerson
      commitSigningGenerator
      commitSigningLegacyMachines
      allowedSigners
      agentFreeSshKeygen
      ;
    commitSigningObligations = {
      inherit
        keyMaterial
        loginSources
        unauthorized
        homeSigningBound
        personGenerator
        workerSigningKey
        signingKeyPresent
        unenrolled
        failures
        ;
    };
  };
}

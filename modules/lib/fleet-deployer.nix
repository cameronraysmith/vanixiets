# Who may have which host deployed by the fleet deployer on cinnabar, and the
# per-host judge the machine checks assert (openspec change
# delegate-fleet-deploys, design D1-D13).
#
# Targets are derived, never listed: every NixOS or darwin inventory machine
# that is enabled (flake.fleet.hosts.<name>.cloud.enabled for a cloud machine,
# present in the inventory otherwise), minus the operator's workstations
# stibnite and blackphos. Re-enabling a cloud machine makes it a target with
# no edit here.
#
# Reach is a role policy over flake.lib.hosts.<name>.primaryUser: a shared
# server (no primary user) is reachable by every operator; a personal machine
# by its primary user and by the admin. Requesters are the people who hold a
# request credential (an omnigent worker's `<worker>-deploy-request` key);
# christophersmith reaches argentum by the policy but holds no credential.
#
# The deployer's own keys are generated on cinnabar and only their public
# halves are written here (design D2). Until they are, `keys` is null and no
# host accepts a deployer key; the obligation then only checks that no host
# carries one. A requester's public key is read from its generator's public
# file and is null until the operator generates it.
{
  config,
  lib,
  ...
}:
let
  inherit (config.flake.lib)
    hosts
    mesh
    ztRecords
    vars
    ;
  inventory = config.flake.clan.inventory.machines;

  deployerHost = "cinnabar";
  account = "fleet-deployer";
  excluded = [
    "stibnite"
    "blackphos"
  ];
  admin = "cameron";
  operators = [
    "cameron"
    "janettesmith"
  ];
  # People whose agent sessions hold a request credential: one per omnigent
  # worker owner (flake.fleet.workers, modules/lib/fleet-workers.nix).
  requesterNames = lib.attrNames config.flake.fleet.workers;

  # The public halves of the deployer's keys, generated on cinnabar by
  # fleet-deployer-keys on 2026-11-18 (task 2.2). Setting this to null
  # withdraws every target's trust in the deployer.
  keys = {
    age = "age107c7zd4v6wm6t3f8kfe87ly4y2f4zh2yeg34n0n9addc6fzfcf9sl9mpaw";
    ssh = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAnu4jxBMb1qSCgURz/E7mqrQvakcuuand4ZWFby+eGR fleet-deployer@cinnabar";
  };

  enabledOf = name: hosts.${name}.cloud == null || hosts.${name}.cloud.enabled;

  classOf = name: inventory.${name}.machineClass;
  isTarget =
    {
      enabledOf,
      excluded,
      classOf,
    }:
    name:
    lib.elem (classOf name) [
      "nixos"
      "darwin"
    ]
    && enabledOf name
    && !lib.elem name excluded;

  targetsFrom = args: names: lib.filter (isTarget args) (lib.sort lib.lessThan names);

  targets = targetsFrom { inherit enabledOf excluded classOf; } (lib.attrNames inventory);
  disabled = lib.filter (name: !enabledOf name) (lib.attrNames inventory);

  # The role policy as data: which requesters each kind of target admits.
  reachRule =
    {
      operators,
      admin,
    }:
    requester: primaryUser:
    if primaryUser == null then
      lib.elem requester operators
    else
      requester == primaryUser || requester == admin;
  rule = reachRule { inherit operators admin; };
  reachOf = requester: lib.filter (name: rule requester hosts.${name}.primaryUser) targets;

  requestKey = owner: {
    generator = "omnigent-${owner}-deploy-request";
    file = "key.pub";
  };
  requestKeyOf =
    owner:
    if vars.exists (requestKey owner // { secret = false; }) then
      lib.trim (vars.public (requestKey owner))
    else
      null;

  requesters = lib.genAttrs requesterNames (name: {
    sshPublicKey = requestKeyOf name;
    machines = reachOf name;
  });

  # Address ranges a request may come from (the tincr mesh and, until
  # ZeroTier is retired, ZeroTier's /64 and IPv4 /24), and the addresses the
  # deployer reaches targets from.
  zerotierNetwork = lib.concatStringsSep ":" (
    lib.take 4 (lib.splitString ":" hosts.${deployerHost}.zerotier.address)
  );
  deployerZtV4 = lib.findFirst (
    r: r.name == "${deployerHost}.zt" && lib.hasInfix "." r.address
  ) null ztRecords;
  zerotierV4Network =
    lib.concatStringsSep "." (lib.take 3 (lib.splitString "." deployerZtV4.address)) + ".0/24";
  requestSources = [
    (mesh.prefixOf mesh.instance)
    "${zerotierNetwork}::/64"
    zerotierV4Network
  ];
  deployerAddresses = lib.unique (
    [ hosts.${deployerHost}.address ]
    ++ map (r: r.address) (lib.filter (r: r.name == "${deployerHost}.zt") ztRecords)
  );

  # The single authorized_keys line a target's deploy account carries. On the
  # deployer host itself the deployer reaches `<host>.zt` over loopback (the
  # host maps its own name to 127.0.0.2), so that line also admits loopback
  # (F82); every other target admits only the deployer's addresses.
  loopbackAddresses = [
    "127.0.0.1"
    "::1"
  ];
  targetKeyLine =
    onDeployer: sshPublicKey:
    ''from="${
      lib.concatStringsSep "," (deployerAddresses ++ lib.optionals onDeployer loopbackAddresses)
    }",restrict ${sshPublicKey}'';
  # The line the deployer account carries for one requester.
  requestKeyLine =
    name: sshPublicKey:
    ''restrict,from="${lib.concatStringsSep "," requestSources}",command="${requestCommand} ${name}" ${sshPublicKey}'';
  # Absolute, because sshd runs a forced command through a non-login shell.
  requestCommand = "/run/current-system/sw/bin/fleet-deploy-request";

  keyDirMode = "0700";
  keyUMask = "0277";

  # The key's base64 body, so a line carries it whatever its options.
  keyBody = key: lib.elemAt (lib.splitString " " key) 1;
  carries = key: line: lib.hasInfix (keyBody key) line;

  # Policy judge over derived data, run on the real data by the machine
  # checks' module and on fixtures by checks.x86_64-linux.fleet-deployer-obligations.
  policyProblems =
    {
      targets,
      enabledOf,
      excluded,
      classOf,
      primaryUserOf,
      reach,
      operators,
      admin,
    }:
    let
      ruleOf = reachRule { inherit operators admin; };
    in
    lib.concatMap (
      name:
      lib.optional (!enabledOf name) "${name} is disabled but is a deploy target"
      ++ lib.optional (lib.elem name excluded) "${name} is excluded but is a deploy target"
      ++ lib.optional (
        !lib.elem (classOf name) [
          "nixos"
          "darwin"
        ]
      ) "${name} is neither NixOS nor darwin but is a deploy target"
    ) targets
    ++ lib.concatLists (
      lib.mapAttrsToList (
        requester: machines:
        lib.concatMap (
          name:
          lib.optional (!lib.elem name targets) "${requester} reaches ${name}, which is not a deploy target"
          ++ lib.optional (
            !ruleOf requester (primaryUserOf name)
          ) "${requester} reaches ${name} outside the role policy"
        ) machines
      ) reach
    );

  # Per-host judge. `facts` is what the machine's configuration declares:
  #   users        name -> list of authorized_keys lines
  #   deployerUnit { keysUMask; tmpfiles } on the deployer host, else null
  #   localSecrets the secrets `clan machines update` decrypts on the
  #                deployer for this machine, each { path; readable; }, where
  #                readable says the sops group fleet-deployers is a reader
  #   watcher      on darwin, the rollback watcher's launchd job
  #                (vanixiets.fleetDeployWatch: { domain; job; }), else null
  hostProblems =
    {
      name,
      facts,
      isTarget,
      isDarwin,
      deployUser,
      primaryUser,
      sshPublicKey,
      requesterLines,
      isDeployer,
    }:
    let
      holders = lib.attrNames (
        lib.filterAttrs (_: lines: lib.any (carries sshPublicKey) lines) facts.users
      );
      expectedLine = targetKeyLine isDeployer sshPublicKey;
      deployLines = facts.users.${deployUser} or [ ];
      deployerLines = facts.users.${account} or [ ];
    in
    lib.optional (
      primaryUser != null && !(facts.users ? ${primaryUser})
    ) "${name}'s primary user ${primaryUser} has no account on it"
    ++ lib.optionals (sshPublicKey != null && isTarget) (
      map (
        secret: "${name}: ${secret.path} is decrypted by the deployer but fleet-deployers is not a reader"
      ) (lib.filter (secret: !secret.readable) facts.localSecrets)
    )
    # The darwin watcher must be a root job in launchd's system domain that
    # runs once: in a user's domain it can neither roll back nor create the
    # directory the deployer confirms in (F84).
    ++ lib.optionals (isTarget && isDarwin) (
      let
        job = if facts.watcher == null then { } else facts.watcher.job;
        args = job.ProgramArguments or [ ];
      in
      if job == { } then
        [ "${name}: the darwin rollback watcher's launchd job is not declared" ]
      else
        lib.optional (facts.watcher.domain != "system")
          "${name}: the rollback watcher is bootstrapped into ${facts.watcher.domain}, not launchd's system domain"
        ++ lib.optional (
          (job.UserName or "root") != "root"
        ) "${name}: the rollback watcher's job runs as ${job.UserName}, not root"
        ++ lib.optional (
          (job.KeepAlive or false) != false
        ) "${name}: launchd restarts the rollback watcher's job (KeepAlive)"
        ++ lib.optional (
          !(
            lib.length args == 2
            && lib.hasSuffix "/bin/fleet-deploy-watch" (lib.head args)
            && lib.last args == "--run"
          )
        ) "${name}: the rollback watcher's job does not run fleet-deploy-watch --run"
    )
    ++ lib.optionals (sshPublicKey != null) (
      if isTarget then
        lib.optional (holders != [ deployUser ] && holders != [ ])
          "${name}: accounts other than ${deployUser} accept the deployer's key (${lib.concatStringsSep ", " holders})"
        ++ lib.optional (
          lib.filter (carries sshPublicKey) deployLines != [ expectedLine ]
        ) "${name}: ${deployUser} does not carry exactly the deployer's key line ${expectedLine}"
      else
        lib.optional (holders != [ ])
          "${name} is not a deploy target but ${lib.concatStringsSep ", " holders} accept the deployer's key"
    )
    ++ (
      if isDeployer then
        lib.optional (
          lib.sort lib.lessThan deployerLines != lib.sort lib.lessThan requesterLines
        ) "${name}: ${account}'s authorized keys are not exactly the requesters' forced-command lines"
        ++ lib.optional (
          facts.deployerUnit == null
        ) "${name} is the deployer host but does not run the deployer"
        ++ lib.optionals (facts.deployerUnit != null) (
          lib.optional (facts.deployerUnit.keysUMask != keyUMask)
            "${name}: fleet-deployer-keys runs with UMask ${toString facts.deployerUnit.keysUMask}, not ${keyUMask}"
          ++ lib.optional (
            !lib.elem "d /var/lib/${account}/keys ${keyDirMode} ${account} ${account} -" facts.deployerUnit.tmpfiles
          ) "${name}: the deployer's key directory is not declared ${keyDirMode} ${account}"
        )
      else
        lib.optional (
          facts.users ? ${account} || facts.deployerUnit != null
        ) "${name} is not the deployer host but declares the ${account} account or service"
    );

  # What `clan machines update` decrypts on the deployer (clan-core d718bcf,
  # clan_lib/vars/secret_modules/sops.py populate_dir, called with the phases
  # activation, users and services by clan_lib/vars/upload.py:21): the
  # machine key, and every secret var whose neededFor is "activation".
  # Partitioning vars are decrypted only by `clan machines install`; users
  # and services vars travel encrypted and are decrypted on the target.
  localSecretsOf =
    name: hostConfig:
    let
      generators = hostConfig.clan.core.vars.generators or { };
      varPath =
        generator: file:
        vars.relPath {
          inherit generator file;
          machine = if generators.${generator}.share then null else name;
        };
      activation = lib.concatLists (
        lib.mapAttrsToList (
          generator: spec:
          map (file: varPath generator file) (
            lib.attrNames (lib.filterAttrs (_: file: file.secret && file.neededFor == "activation") spec.files)
          )
        ) generators
      );
    in
    map (path: {
      inherit path;
      readable = builtins.pathExists (../.. + "/${path}/groups/fleet-deployers");
    }) ([ "sops/secrets/${name}-age.key" ] ++ activation);

  factsOf = name: hostConfig: {
    users = lib.mapAttrs (_: user: user.openssh.authorizedKeys.keys or [ ]) (
      lib.filterAttrs (_: user: user ? openssh) hostConfig.users.users
    );
    deployerUnit =
      if hostConfig ? systemd && hostConfig.systemd.services ? fleet-deployer-keys then
        {
          keysUMask = hostConfig.systemd.services.fleet-deployer-keys.serviceConfig.UMask or null;
          tmpfiles = hostConfig.systemd.tmpfiles.rules;
        }
      else
        null;
    localSecrets = if lib.elem name targets then localSecretsOf name hostConfig else [ ];
    watcher = hostConfig.vanixiets.fleetDeployWatch or null;
  };

  sshPublicKey = if keys == null then null else keys.ssh;
  requesterLines = lib.concatLists (
    lib.mapAttrsToList (
      name: r: lib.optional (r.sshPublicKey != null) (requestKeyLine name r.sshPublicKey)
    ) requesters
  );

  failures =
    name: hostConfig:
    hostProblems {
      inherit name sshPublicKey requesterLines;
      facts = factsOf name hostConfig;
      isTarget = lib.elem name targets;
      isDarwin = classOf name == "darwin";
      inherit (hosts.${name}) deployUser primaryUser;
      isDeployer = name == deployerHost;
    };
in
{
  fleetObligations.fleetDeployer.failures = failures;

  flake.lib.fleetDeployer = {
    inherit
      deployerHost
      account
      excluded
      admin
      operators
      targets
      disabled
      requesters
      keys
      requestSources
      deployerAddresses
      keyDirMode
      keyUMask
      targetKeyLine
      requestKeyLine
      requesterLines
      sshPublicKey
      isTarget
      targetsFrom
      reachRule
      policyProblems
      hostProblems
      factsOf
      failures
      ;
    endpoint = {
      hostName = "${deployerHost}.zt";
      user = account;
    };
    # Problems in the real data; asserted empty by modules/checks/machines.nix.
    problems = policyProblems {
      inherit
        targets
        enabledOf
        excluded
        classOf
        operators
        admin
        ;
      primaryUserOf = name: hosts.${name}.primaryUser;
      reach = lib.mapAttrs (_: r: r.machines) requesters;
    };
    # What the deployer's request command reads (pkgs/by-name/fleet-deploy-request).
    requestConfig = {
      # targetHost is the address probed before the commit is evaluated (F83);
      # the address resolved from the commit is re-probed before the lock.
      targets = lib.genAttrs targets (name: {
        class = classOf name;
        inherit (hosts.${name}) deployUser targetHost;
      });
      machines = lib.attrNames inventory;
      requesters = lib.mapAttrs (_: r: r.machines) requesters;
      cacheStore = "https://cache.scientistexperience.net";
      forge = "https://github.com/cameronraysmith/vanixiets.git";
      stateDir = "/var/lib/${account}";
      runDir = "/run/${account}";
      lockWait = 600;
      slots = 2;
      probeTimeout = 10;
      settle = 60;
      confirmWindow = 300;
      activationWait = 7200;
      # After a failed confirmation the deployer reads the target until
      # confirmWindow + rollbackGrace for the watcher's return (F84).
      rollbackGrace = 60;
    };
  };
}

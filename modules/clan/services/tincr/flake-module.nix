# A tincr mesh per instance on every machine in the `peer` role, NixOS and
# darwin. Addresses come from flake.lib.mesh, keys from the per-machine var
# tincr-<instance>, and every node carries one host file per peer and device
# with StrictSubnets on. README.md states the settings, the trust boundary and
# the provenance.
{
  inputs,
  config,
  lib,
  ...
}:
let
  inherit (config.flake.lib) mesh hosts launchdSecretPoll;

  # One member's host file. SPTPSCipher and SPTPSKex take effect on a link
  # only when both ends' host files carry them (tincr docs/COMPAT.md), so they
  # are written for clan peers only and a device's links keep the defaults.
  hostFile =
    {
      address,
      publicKey,
      endpoints ? [ ],
      pq ? false,
    }:
    lib.concatLines (
      map (endpoint: "Address = ${endpoint}") endpoints
      ++ [
        "Subnet = ${address}/128"
        "Ed25519PublicKey = ${publicKey}"
      ]
    )
    + lib.optionalString pq ''
      SPTPSCipher = aes-256-gcm
      SPTPSKex = x25519-mlkem768
    '';
in
{
  flake.lib.tincrHostFile = hostFile;

  flake.clan.modules.tincr =
    {
      clanLib,
      config,
      lib,
      ...
    }:
    let
      generatorName = instanceName: "tincr-${instanceName}";

      # nixpkgs' tinc_pre is in cache.nixos.org for every system the generator
      # runs on, so `clan vars generate` builds nothing; tincr reads the tinc
      # 1.1 key format it writes. The public file has no trailing newline
      # because it is spliced into host files.
      keyGenerator = pkgs: {
        files."ed25519_key.priv" = { };
        files."ed25519_key.pub".secret = false;
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnused
          pkgs.tinc_pre
        ];
        script = ''
          conf=$(mktemp -d -p /tmp)
          mkdir "$conf/hosts"
          echo "Name = node" > "$conf/tinc.conf"
          tinc -c "$conf" generate-ed25519-keys < /dev/null
          cp "$conf/ed25519_key.priv" "$out/ed25519_key.priv"
          printf %s "$(sed -n 's/^Ed25519PublicKey = //p' "$conf/hosts/node")" > "$out/ed25519_key.pub"
          test -s "$out/ed25519_key.pub"
        '';
      };

      # The values the host files are rendered from, as internal options so
      # the negative controls addressCollision and keyCollision, and the pq
      # device check, reach the rendering through the same values.
      meshModule =
        {
          instanceName,
          settings,
          roles,
          machine,
        }:
        { config, ... }:
        let
          cfg = config.vanixiets.tincr;
          peers = roles.peer.machines;
          peerKey =
            name:
            clanLib.getPublicValue {
              flake = config.clan.core.settings.directory;
              machine = name;
              generator = generatorName instanceName;
              file = "ed25519_key.pub";
            };
          sharing =
            values:
            lib.filterAttrs (_: names: lib.length names > 1) (
              lib.groupBy (name: values.${name}) (lib.attrNames values)
            );
          describe =
            shared:
            lib.concatStringsSep "; " (
              lib.mapAttrsToList (value: names: "${lib.concatStringsSep ", " names} -> ${value}") shared
            );
          addressCollisions = sharing cfg.addresses;
          keyCollisions = sharing cfg.publicKeys;
        in
        {
          options.vanixiets.tincr = {
            addresses = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              internal = true;
              description = "Overlay address of every peer and device of the instance, keyed by member name.";
            };
            publicKeys = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              internal = true;
              description = "Ed25519 public key of every peer and device of the instance, keyed by member name.";
            };
            devices = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              internal = true;
              description = "Ed25519 public key of every device of the instance, keyed by device name.";
            };
            crypto = lib.mkOption {
              type = lib.types.enum [
                "default"
                "pq"
              ];
              internal = true;
              description = "The instance's `crypto` setting.";
            };
            network = lib.mkOption {
              type = lib.types.attrs;
              internal = true;
              readOnly = true;
              description = "The class-independent part of `services.tincr.networks.<instance>`.";
            };
          };

          config = {
            vanixiets.tincr = {
              addresses = lib.mapAttrs (name: _: mesh.addressOf instanceName name) (peers // cfg.devices);
              publicKeys = lib.mapAttrs (name: _: peerKey name) peers // cfg.devices;
              devices = lib.mapAttrs (_: device: device.publicKey) settings.devices;
              inherit (settings) crypto;
              network = {
                nodeName = machine.name;
                listenPort = mesh.port;
                ed25519PrivateKeyFile =
                  config.clan.core.vars.generators.${generatorName instanceName}.files."ed25519_key.priv".path;
                hosts = lib.mapAttrs (
                  name: _:
                  hostFile {
                    address = cfg.addresses.${name};
                    publicKey = cfg.publicKeys.${name};
                    endpoints = peers.${name}.settings.endpoints or [ ];
                    pq = cfg.crypto == "pq" && peers ? ${name};
                  }
                ) cfg.addresses;
                connectTo = lib.attrNames (
                  lib.filterAttrs (name: peer: name != machine.name && peer.settings.endpoints != [ ]) peers
                );
                addresses = [ "${cfg.addresses.${machine.name}}/64" ];
                # Broadcast = no: the mesh carries IPv6 unicast only, and
                # krebs' retiolum stopped a mesh-wide packet storm from
                # broadcast loops with it (kartei modules/retiolum/nixos.nix).
                extraConfig = ''
                  StrictSubnets = yes
                  Broadcast = no
                '';
              };
            };

            assertions = [
              {
                assertion = instanceName == mesh.instance;
                message = "tincr: instance `${instanceName}` is not flake.lib.mesh.instance (`${mesh.instance}`), whose interface names the service uses.";
              }
              {
                assertion = addressCollisions == { };
                message = "tincr: members derive the same address: ${describe addressCollisions}.";
              }
              {
                assertion = keyCollisions == { };
                message = "tincr: members share an Ed25519 public key: ${describe keyCollisions}.";
              }
            ];
          };
        };

      # Prints the Subnet line of the node named by $NODE, by the shell slicing
      # that mirrors flake.lib.mesh.addressOf.
      subnetOfNode = pkgs: instanceName: ''
        hash=$(printf %s "$NODE" | ${pkgs.coreutils}/bin/sha256sum)
        printf 'Subnet = %s:%s:%s:%s:%s/128\n' \
          ${lib.removeSuffix "::/64" (mesh.prefixOf instanceName)} \
          "''${hash:0:4}" "''${hash:4:4}" "''${hash:8:4}" "''${hash:12:4}"
      '';

      # The invitee's address, into its section of the invitation.
      invitationCreated =
        pkgs: instanceName:
        pkgs.writeShellScript "tincr-${instanceName}-invitation-created" ''
          { ${subnetOfNode pkgs instanceName} } >> "$INVITATION_FILE"
        '';

      # tincd writes an accepted invitee's host file into the hosts overlay
      # with only its key, and that copy hides the declared hosts/<device>, so
      # the invitee's Subnet goes into it too or StrictSubnets refuses it.
      invitationAccepted =
        pkgs: instanceName:
        pkgs.writeShellScript "tincr-${instanceName}-invitation-accepted" ''
          if ! ${pkgs.gnugrep}/bin/grep -q '^Subnet' "$HOST_FILE"; then
            { ${subnetOfNode pkgs instanceName} } >> "$HOST_FILE"
          fi
        '';
    in
    {
      _class = "clan.service";
      manifest.name = "tincr";
      manifest.description = "tincr mesh VPN with addresses derived from member names and StrictSubnets on every node";
      manifest.categories = [ "Network" ];
      manifest.readme = builtins.readFile ./README.md;
      manifest.exports.out = [
        "networking"
        "peer"
      ];

      exports = lib.mapAttrs' (instanceName: _: {
        name = clanLib.buildScopeKey {
          inherit instanceName;
          serviceName = "tincr";
        };
        value.networking.priority = 1100;
      }) config.instances;

      roles.peer = {
        description = "A member of the mesh: dials every peer with endpoints and carries every member's host file.";
        interface =
          { lib, ... }:
          {
            options.endpoints = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "cinnabar.example.net" ];
              description = "Addresses other peers dial this machine at, each `\"<name or address> [port]\"`; empty behind NAT.";
            };
            options.devices = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options.publicKey = lib.mkOption {
                    type = lib.types.str;
                    description = "The device's Ed25519 public key, as its tinc client wrote it.";
                  };
                }
              );
              default = { };
              description = "Members outside clan, such as phones, keyed by name; each gets a host file on every peer.";
            };
            options.crypto = lib.mkOption {
              type = lib.types.enum [
                "default"
                "pq"
              ];
              default = mesh.crypto;
              description = "`default` writes no cipher or key-exchange lines; `pq` adds SPTPSCipher = aes-256-gcm and SPTPSKex = x25519-mlkem768 to every clan peer's host file and never to a device's, so links between clan peers use them and links to devices keep the defaults.";
            };
          };

        perInstance =
          {
            instanceName,
            settings,
            roles,
            machine,
            mkExports,
            ...
          }:
          let
            shared = meshModule {
              inherit
                instanceName
                settings
                roles
                machine
                ;
            };
          in
          {
            # clan logs in through a network as its export's user, root when
            # unset, ahead of the machine's own targetHost; darwin logs in as
            # its admin account (flake.lib.networkTargetObligations).
            exports = mkExports {
              peer.hosts = [ { plain = hosts.${machine.name}.fqdn; } ];
              peer.user = hosts.${machine.name}.deployUser;
            };

            nixosModule =
              { config, pkgs, ... }:
              let
                network = config.vanixiets.tincr.network;
              in
              {
                imports = [ shared ];
                services.tincr.networks.${instanceName} = network // {
                  interfaceName = mesh.interface.nixos;
                  openFirewall = true;
                  dns.enable = false;
                };
                environment.etc."tinc/${instanceName}/invitation-created".source =
                  invitationCreated pkgs instanceName;
                environment.etc."tinc/${instanceName}/invitation-accepted".source =
                  invitationAccepted pkgs instanceName;
                environment.systemPackages = [ config.services.tincr.package ];
                # tincr's module only reloads tincd when host files change, and
                # a reload does not apply StrictSubnets changes (tincr
                # docs/COMPAT.md), so a changed member list restarts it.
                systemd.services."tincr-${instanceName}".restartTriggers = [ (builtins.toJSON network.hosts) ];
                # PMTU black holes over double-NAT relays, as krebs' retiolum
                # pins it (kartei modules/retiolum/nixos.nix); tincr's darwin
                # module defaults to the same 1377.
                systemd.network.networks."40-tincr-${instanceName}".linkConfig.MTUBytes = "1377";
                # tincr's module hands the link to networkd; on a host that also
                # runs NetworkManager (pyrite) the two must not both manage it.
                networking.networkmanager.unmanaged = [ "interface-name:${mesh.interface.nixos}" ];
              };

            darwinModule =
              { config, pkgs, ... }:
              let
                network = config.vanixiets.tincr.network;
                package = config.services.tincr.networks.${instanceName}.package;
                daemon = "tincr-${instanceName}";
                job = config.launchd.daemons.${daemon};
                # What tincr writes under /etc/tinc/<instance>: tinc.conf
                # names the private key; hosts and tinc-up are store paths.
                configText = lib.concatMapStrings (entry: lib.optionalString (entry.text != null) entry.text) (
                  lib.attrValues (
                    lib.filterAttrs (name: _: lib.hasPrefix "tinc/${instanceName}/" name) config.environment.etc
                  )
                );
              in
              {
                imports = [ shared ];
                services.tincr.networks.${instanceName} = network // {
                  utunUnit = lib.toInt (lib.removePrefix "utun" mesh.interface.darwin);
                };
                launchd.daemons.${daemon} = {
                  # tincr's darwin daemon reads host files only at start; a
                  # changed plist makes nix-darwin reload the daemon on
                  # activation.
                  serviceConfig.EnvironmentVariables.TINCR_HOST_FILES = builtins.hashString "sha256" (
                    builtins.toJSON network.hosts
                  );
                  # tincd reads its key at start, and launchd can start it at
                  # boot before sops-install-secrets has written it; the start
                  # polls, bounded, for every secret its configuration names
                  # (flake.lib.launchdSecretPoll, which says why not wait4path).
                  script = lib.mkBefore (launchdSecretPoll.prefix { } (launchdSecretPoll.namedIn config configText));
                };
                assertions =
                  map
                    (message: {
                      assertion = false;
                      inherit message;
                    })
                    (
                      launchdSecretPoll.failures {
                        label = "launchd.daemons.${daemon}";
                        start = job.script;
                        outer = job.serviceConfig.ProgramArguments;
                        # Every /run path the daemon's configuration names.
                        named = lib.unique (
                          map builtins.head (builtins.filter builtins.isList (builtins.split "(/run/[^ \n]+)" configText))
                        );
                      }
                    );
                # The darwin daemon writes its pidfile where the tinc CLI does
                # not look (tincr nix/darwin-module.nix, names.rs).
                environment.systemPackages = [
                  (lib.hiPrio (
                    pkgs.writeShellScriptBin "tinc" ''
                      exec ${package}/bin/tinc --pidfile=/var/run/tincr-${instanceName}.pid "$@"
                    ''
                  ))
                ];
              };
          };
      };

      perMachine =
        { instances, ... }:
        let
          generators =
            pkgs:
            lib.mapAttrs' (
              instanceName: _: lib.nameValuePair (generatorName instanceName) (keyGenerator pkgs)
            ) instances;
        in
        {
          nixosModule =
            { pkgs, ... }:
            {
              imports = [ inputs.tincr.nixosModules.tincr ];
              clan.core.vars.generators = generators pkgs;
            };
          darwinModule =
            { pkgs, ... }:
            {
              imports = [ inputs.tincr.darwinModules.tincr ];
              clan.core.vars.generators = generators pkgs;
            };
        };
    };
}

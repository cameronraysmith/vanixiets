# The secret seam: `vanixiets.secrets.<name>`, through which a module declares
# the secrets it owns and reads the ones it uses without naming the backend
# that generates and delivers them. With modules/lib/vars.nix (the committed
# store) this file is meant to be the only first-party module that names clan
# vars; the modules that still do are listed in
# modules/checks/secrets-seam-confinement.nix, and they move behind this
# option one closed set of secrets at a time (the plan is
# openspec/changes/seam-secrets-away-from-clan-vars/design.md).
#
# `<name>` is the clan generator name. The writable fields are the ones the
# fleet's generator definitions set, each null (a list: empty) unless defined,
# and the translation into `clan.core.vars.generators.<name>` writes only the
# defined ones, so clan's own defaults decide every field a module leaves
# unset; checks.x86_64-linux.secrets-seam-translation pins that.
# An entry with `provided = true` names a generator clan's own services
# declare (sshd's `openssh`): its reader declares the files it reads, by name
# only, nothing is translated for it, and any writable field it sets fails
# evaluation where clan is present, naming the entry and the field. The
# read-only `files.<f>.{path,value,exists,placeholder}` are clan's values,
# read lazily, and null where clan-core is not imported (clan-free fixtures),
# the one place that tests for it.
#
# flake.modules.homeManager.secrets is the home side: a view of
# `{ files.<f>.{path,placeholder} }` that the hm-sops-bridge modules set
# (modules/nixos/hm-sops-bridge.nix) and that is `{ }` in a standalone home.
# flake.lib.secretsBackend.generatorsOf is clan's whole generator tree of a
# host, generators of clan's own services included. It is meant for judges
# that must see every generator a host has: which shared secrets the host must
# be a recipient of (modules/lib/shared-vars-recipients.nix) and which secrets
# a deploy decrypts locally (modules/lib/fleet-deployer.nix), both of which
# still read clan's tree directly.
{ config, lib, ... }:
let
  inherit (config.flake.lib) exportAs;

  unset =
    type:
    lib.mkOption {
      type = lib.types.nullOr type;
      default = null;
    };
  emptyList =
    type:
    lib.mkOption {
      type = lib.types.listOf type;
      default = [ ];
    };
  backendValue =
    type: value:
    lib.mkOption {
      type = lib.types.nullOr type;
      readOnly = true;
      default = value;
      defaultText = lib.literalMD "the secret backend's value, or `null` without one";
    };

  prune = lib.filterAttrs (_: v: v != null && v != [ ]);

  promptToBackend =
    p:
    prune { inherit (p) description type persist; }
    // lib.optionalAttrs (prune p.display != { }) { display = prune p.display; };

  toBackend =
    s:
    prune {
      inherit (s)
        share
        dependencies
        validation
        runtimeInputs
        script
        ;
    }
    // lib.optionalAttrs (s.prompts != { }) { prompts = lib.mapAttrs (_: promptToBackend) s.prompts; }
    // lib.optionalAttrs (s.files != { }) {
      files = lib.mapAttrs (
        _: f:
        prune {
          inherit (f)
            secret
            deploy
            owner
            group
            mode
            neededFor
            restartUnits
            ;
        }
      ) s.files;
    };

  # The writable fields a provided entry sets, as `<field>` or
  # `files.<f>.<field>`; the backend's service owns them, so any is an error.
  writableFieldsOf =
    s:
    let
      translated = toBackend s;
    in
    lib.attrNames (removeAttrs translated [ "files" ])
    ++ lib.concatLists (
      lib.mapAttrsToList (f: fields: map (field: "files.${f}.${field}") (lib.attrNames fields)) (
        translated.files or { }
      )
    );

  module =
    {
      config,
      options,
      lib,
      ...
    }:
    let
      hostConfig = config;
      hasBackend = options ? clan.core.vars;
      backendGenerator =
        name: provided:
        hostConfig.clan.core.vars.generators.${name} or (
          if provided then
            throw "vanixiets.secrets.${name} is provided, but the secret backend declares no generator ${name}"
          else
            throw "vanixiets.secrets.${name} has no generator in the secret backend"
        );

      fileModule =
        secretName: provided:
        { name, ... }:
        let
          backendFile = (backendGenerator secretName provided).files.${name};
        in
        {
          options = {
            secret = unset lib.types.bool;
            deploy = unset lib.types.bool;
            owner = unset lib.types.str;
            group = unset lib.types.str;
            mode = unset lib.types.str;
            neededFor = unset lib.types.str;
            restartUnits = emptyList lib.types.str;

            path = backendValue lib.types.str (if hasBackend then backendFile.path else null);
            value = backendValue lib.types.str (if hasBackend then backendFile.value else null);
            exists = backendValue lib.types.bool (if hasBackend then backendFile.exists else null);
            placeholder = backendValue lib.types.str (
              if hasBackend then hostConfig.sops.placeholder."vars/${backendFile.rel_dir}/${name}" else null
            );
          };
        };

      promptModule = {
        options = {
          description = unset lib.types.str;
          type = unset lib.types.str;
          persist = unset lib.types.bool;
          display = {
            group = unset lib.types.str;
            label = unset lib.types.str;
            required = unset lib.types.bool;
            helperText = unset lib.types.str;
          };
        };
      };

      notProvided =
        name: s:
        let
          fields = writableFieldsOf s;
        in
        if !s.provided then
          true
        else if fields == [ ] then
          false
        else
          throw "vanixiets.secrets.${name} is provided by the secret backend, so it cannot set ${lib.concatStringsSep ", " fields}";

      secretModule =
        { name, config, ... }:
        {
          options = {
            share = unset lib.types.bool;
            dependencies = emptyList lib.types.str;
            validation = unset lib.types.anything;
            runtimeInputs = emptyList lib.types.package;
            script = unset (lib.types.either lib.types.str lib.types.path);
            prompts = lib.mkOption {
              type = lib.types.attrsOf (lib.types.submodule promptModule);
              default = { };
            };
            files = lib.mkOption {
              type = lib.types.attrsOf (lib.types.submodule (fileModule name config.provided));
              default = { };
            };
            provided = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether a clan-core service declares this generator, so that the seam only reads it; the reader declares each file it reads.";
            };
          };
        };
    in
    {
      options.vanixiets.secrets = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule secretModule);
        default = { };
        description = "The secrets this host's modules declare and read, keyed by generator name.";
      };

      config = lib.optionalAttrs hasBackend {
        clan.core.vars.generators = lib.mapAttrs (_: toBackend) (
          lib.filterAttrs notProvided config.vanixiets.secrets
        );
      };
    };

  homeModule =
    { lib, ... }:
    {
      options.vanixiets.secrets = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.files = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options = {
                    path = unset lib.types.str;
                    placeholder = unset lib.types.str;
                  };
                }
              );
              default = { };
            };
          }
        );
        default = { };
        description = "The host's secrets with a file this home's user owns, set by the host's hm-sops-bridge.";
      };
    };

  exportSecrets =
    m:
    exportAs {
      key = "secrets";
      names = [ "secrets" ];
      module = m;
    };
  nixos = exportSecrets module;
  darwin = exportSecrets module;
in
{
  flake.modules.nixos = nixos // {
    base.imports = [ nixos.secrets ];
  };
  flake.modules.darwin = darwin // {
    base.imports = [ darwin.secrets ];
  };
  flake.modules.homeManager = exportSecrets homeModule;
  flake.lib.secretsBackend.generatorsOf = hostConfig: hostConfig.clan.core.vars.generators;
}

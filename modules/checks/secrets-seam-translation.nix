# checks.x86_64-linux.secrets-seam-translation: the judge of how the secret
# seam (modules/system/secrets.nix) hands `vanixiets.secrets` to clan: only the
# fields a module defines, nothing for a provided entry, and clan's values read
# back. The NixOS secrets module is evaluated with lib.evalModules
# against a stub of clan's generator option that keeps whatever it receives,
# and a stub of sops-nix's placeholder option, which like sops-nix's own
# defaults to `{ }`:
#   everyField         every writable field set once reaches the stub as set;
#   onlySecret         an entry setting only files.<f>.secret reaches it as
#                      that one field, with no null and no empty list;
#   provided           a provided entry adds nothing to the generator the stub
#                      (standing in for a clan service) declares, and its
#                      declared file reads that generator's value;
#   providedWritable   a provided entry that sets a writable field fails;
#   providedAbsent     a provided entry whose generator the backend lacks
#                      fails when its file is read;
#   readBack           a declared file's path, value, exists and placeholder
#                      are the backend's, the placeholder under the sops name
#                      vars/<rel_dir>/<file>;
#   placeholderAbsent  a declared file sops-nix has no placeholder for (a
#                      host without sops.templates, or a file that is no sops
#                      secret) reads a null placeholder;
#   homeView           on such a host, a home's whole view, set by the
#                      hm-sops-bridge view module, evaluates and holds the
#                      owned file's path and a null placeholder;
#   resolvedBack       `resolved` is the backend's generator in the option's
#                      field names, the backend's defaults included (a file's
#                      owner the entry left null reads as the backend's
#                      "root"), and without the backend's own fields (a
#                      file's rel_dir, a prompt's name);
#   noBackend          without the stub options the module defines nothing
#                      outside `vanixiets`, and every read-only field and
#                      `resolved` are null.
# No host is evaluated; the fixtures are literal, so the check runs on
# x86_64-linux only.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      clanStub = {
        options.clan.core.vars.generators = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule { freeformType = lib.types.attrsOf lib.types.anything; }
          );
          default = { };
        };
        options.sops.placeholder = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
        };
      };
      eval =
        modules:
        (lib.evalModules {
          modules = [ self.modules.nixos.secrets ] ++ modules;
        }).config;
      received =
        fixture:
        (eval [
          clanStub
          fixture
        ]).clan.core.vars.generators;
      differs =
        what: expected: actual:
        lib.optional (
          actual != expected
        ) "${what}: expected ${builtins.toJSON expected}, got ${builtins.toJSON actual}";

      everyField = {
        share = true;
        dependencies = [ "other" ];
        validation = {
          version = 2;
        };
        runtimeInputs = [ pkgs.emptyFile ];
        script = "echo generated > $out/token";
        prompts.passphrase = {
          description = "a passphrase";
          type = "hidden";
          persist = true;
          display = {
            group = "fixture";
            label = "Passphrase";
            required = false;
            helperText = "any text";
          };
        };
        files.token = {
          secret = true;
          deploy = false;
          owner = "alice";
          group = "users";
          mode = "0440";
          neededFor = "users";
          restartUnits = [ "a.service" ];
        };
      };

      cases = {
        everyField = {
          problems = 0;
          judge =
            _:
            differs "the stub received" { all = everyField; } (received {
              vanixiets.secrets.all = everyField;
            });
        };
        onlySecret = {
          problems = 0;
          judge =
            _:
            differs "the stub received" { one.files.token.secret = false; } (received {
              vanixiets.secrets.one.files.token.secret = false;
            });
        };
        provided = {
          problems = 0;
          judge =
            _:
            let
              backendDeclared.files.key = {
                secret = false;
                value = "public key";
              };
              config = eval [
                clanStub
                {
                  clan.core.vars.generators.service-key = backendDeclared;
                  vanixiets.secrets.service-key = {
                    provided = true;
                    files.key = { };
                  };
                }
              ];
            in
            differs "the stub received" { service-key = backendDeclared; } config.clan.core.vars.generators
            ++
              differs "the provided file's value" "public key"
                config.vanixiets.secrets.service-key.files.key.value;
        };
        providedWritable = {
          problems = 0;
          judge =
            _:
            let
              config = eval [
                clanStub
                {
                  clan.core.vars.generators.service-key.files.key.value = "public key";
                  vanixiets.secrets.service-key = {
                    provided = true;
                    files.key.owner = "alice";
                  };
                }
              ];
            in
            lib.optional (builtins.tryEval (builtins.attrNames config.clan.core.vars.generators)).success "a provided entry setting files.key.owner evaluated";
        };
        providedAbsent = {
          problems = 0;
          judge =
            _:
            let
              config = eval [
                clanStub
                {
                  vanixiets.secrets.missing = {
                    provided = true;
                    files.key = { };
                  };
                }
              ];
            in
            lib.optional (builtins.tryEval config.vanixiets.secrets.missing.files.key.value).success "a provided entry with no backend generator read without failing";
        };
        readBack = {
          problems = 0;
          judge =
            _:
            let
              config = eval [
                clanStub
                {
                  clan.core.vars.generators.declared.files.token = {
                    path = "/run/secrets/vars/per-machine/m/declared/token";
                    value = "token value";
                    exists = true;
                    rel_dir = "per-machine/m/declared";
                  };
                  sops.placeholder."vars/per-machine/m/declared/token" = "<SOPS:token>";
                  vanixiets.secrets.declared.files.token.owner = "alice";
                }
              ];
            in
            differs "the read-only fields"
              {
                path = "/run/secrets/vars/per-machine/m/declared/token";
                value = "token value";
                exists = true;
                placeholder = "<SOPS:token>";
              }
              {
                inherit (config.vanixiets.secrets.declared.files.token)
                  path
                  value
                  exists
                  placeholder
                  ;
              };
        };
        placeholderAbsent = {
          problems = 0;
          judge =
            _:
            let
              config = eval [
                clanStub
                {
                  clan.core.vars.generators.declared.files.token = {
                    path = "/run/secrets/vars/per-machine/m/declared/token";
                    rel_dir = "per-machine/m/declared";
                  };
                  vanixiets.secrets.declared.files.token.owner = "alice";
                }
              ];
            in
            differs "the placeholder" null config.vanixiets.secrets.declared.files.token.placeholder;
        };
        homeView = {
          problems = 0;
          judge =
            _:
            let
              host = eval [
                clanStub
                self.modules.darwin.hm-sops-bridge
                {
                  options.home-manager.sharedModules = lib.mkOption {
                    type = lib.types.listOf lib.types.raw;
                    default = [ ];
                  };
                }
                {
                  clan.core.vars.generators.declared.files = {
                    token = {
                      path = "/run/secrets/vars/per-machine/m/declared/token";
                      rel_dir = "per-machine/m/declared";
                    };
                    other.rel_dir = "per-machine/m/declared";
                  };
                  vanixiets.secrets.declared.files = {
                    token.owner = "alice";
                    other.owner = "bob";
                  };
                }
              ];
              home =
                (lib.evalModules {
                  modules = host.home-manager.sharedModules ++ [
                    {
                      options.home.username = lib.mkOption { type = lib.types.str; };
                      config.home.username = "alice";
                    }
                  ];
                }).config;
            in
            differs "the home's view" {
              declared.files.token = {
                path = "/run/secrets/vars/per-machine/m/declared/token";
                placeholder = null;
              };
            } home.vanixiets.secrets;
        };
        resolvedBack = {
          problems = 0;
          judge =
            _:
            let
              backendDefaults = {
                share = false;
                dependencies = [ ];
                validation = null;
                runtimeInputs = [ ];
                script = "echo generated > $out/token";
                prompts.passphrase = {
                  name = "passphrase";
                  description = "passphrase";
                  type = "line";
                  persist = false;
                  display = {
                    group = null;
                    label = null;
                    required = true;
                    helperText = null;
                  };
                };
                files.token = {
                  deploy = true;
                  owner = "root";
                  group = "root";
                  mode = "0400";
                  neededFor = "services";
                  restartUnits = [ ];
                  rel_dir = "per-machine/m/declared";
                  path = "/run/secrets/vars/per-machine/m/declared/token";
                };
              };
              config = eval [
                clanStub
                {
                  clan.core.vars.generators.declared = backendDefaults;
                  vanixiets.secrets.declared.files.token.secret = true;
                }
              ];
              entry = config.vanixiets.secrets.declared;
            in
            differs "resolved" {
              inherit (backendDefaults)
                share
                dependencies
                validation
                runtimeInputs
                script
                ;
              prompts.passphrase = {
                inherit (backendDefaults.prompts.passphrase)
                  description
                  type
                  persist
                  display
                  ;
              };
              files.token = {
                secret = true;
                inherit (backendDefaults.files.token)
                  deploy
                  owner
                  group
                  mode
                  neededFor
                  restartUnits
                  ;
              };
            } entry.resolved
            ++ differs "the entry's own owner" null entry.files.token.owner;
        };
        noBackend = {
          problems = 0;
          judge =
            _:
            let
              config = eval [ { vanixiets.secrets.all = everyField; } ];
            in
            differs "the configuration's top-level names" [ "vanixiets" ] (builtins.attrNames config)
            ++
              differs "the read-only fields"
                {
                  path = null;
                  value = null;
                  exists = null;
                  placeholder = null;
                  resolved = null;
                }
                {
                  inherit (config.vanixiets.secrets.all.files.token)
                    path
                    value
                    exists
                    placeholder
                    ;
                  inherit (config.vanixiets.secrets.all) resolved;
                };
        };
      };
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      testSizes.checks = {
        # nixbot: 0 runs, too few to class (declare-test-size-classes design D4)
        secrets-seam-translation = {
          class = "medium";
          measured = false;
        };
      };
      checks.secrets-seam-translation = self.lib.mkJudgeCheck pkgs {
        name = "secrets-seam-translation";
        judge = _: [ ];
        inherit cases;
      };
    };
}

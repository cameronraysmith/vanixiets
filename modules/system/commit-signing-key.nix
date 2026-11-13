# Each person's commit signing key, generated once as a shared clan var and
# declared on every machine carrying their home or an Omnigent worker for them.
# A shared generator may differ between machines only in a file's owner, group
# or mode (clan-core pkgs/clan-cli/clan_lib/vars/generator.py), so everything
# but `owner` depends on the person alone.
{ config, lib, ... }:
let
  flakeConfig = config;
  module =
    { config, pkgs, ... }:
    let
      users = flakeConfig.flake.users;
      inherit (flakeConfig.flake.lib)
        signingPerson
        commitSigningGenerator
        commitSigningLegacyMachines
        ;
      homeOwners = lib.listToAttrs (
        map (account: lib.nameValuePair (signingPerson account) account) (
          lib.filter (account: users ? ${account}) (lib.attrNames (config.home-manager.users or { }))
        )
      );
      workerPersons = map (worker: signingPerson worker.owner) (
        lib.attrValues (config.services.omnigent-host.workers or { })
      );
      persons = lib.unique (lib.attrNames homeOwners ++ workerPersons);
      generator = person: {
        share = true;
        files.key = {
          secret = true;
          owner = homeOwners.${person} or "root";
          mode = "0400";
        };
        files."key.pub".secret = false;
        runtimeInputs = [ pkgs.openssh ];
        script = ''
          ssh-keygen -q -t ed25519 -N "" -C ${lib.escapeShellArg "${users.${person}.meta.gitEmail} commit signing"} -f "$out/key"
        '';
      };
    in
    {
      options.vanixiets.commitSigning.program = lib.mkOption {
        type = lib.types.str;
        default = lib.getExe (flakeConfig.flake.lib.agentFreeSshKeygen pkgs);
        readOnly = true;
        description = "The agent-free `ssh-keygen` built from this host's packages, which its homes sign through.";
      };

      config.clan.core.vars.generators =
        lib.mkIf (!lib.elem config.clan.core.settings.machine.name commitSigningLegacyMachines)
          (
            lib.listToAttrs (
              map (person: lib.nameValuePair (commitSigningGenerator person) (generator person)) persons
            )
          );
    };
in
{
  flake.modules.nixos.base = module;
  flake.modules.darwin.base = module;
}

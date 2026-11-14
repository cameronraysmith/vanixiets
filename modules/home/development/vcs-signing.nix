{ config, ... }:
{
  flake.modules.homeManager.vcs-signing =
    {
      config,
      lib,
      pkgs,
      flake,
      osConfig ? null,
      ...
    }:
    let
      inherit (flake.lib)
        signingPerson
        commitSigningGenerator
        commitSigningLegacyMachines
        agentFreeSshKeygen
        allowedSigners
        ;
      username = config.home.username;
      meta = flake.users.${username}.meta;
      machine = if osConfig == null then null else osConfig.clan.core.settings.machine.name or null;
      generated =
        if osConfig == null then
          null
        else
          osConfig.clan.core.vars.generators.${commitSigningGenerator (signingPerson username)} or null;
      key = config.vcs.signing.keyFile;
      program = lib.getExe (agentFreeSshKeygen pkgs);
      signers = "${config.xdg.configHome}/git/allowed_signers";
    in
    {
      key = "vanixiets/vcs-signing-home-module";

      options.vcs.signing.keyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default =
          if lib.elem machine commitSigningLegacyMachines then
            config.sops.secrets.ssh-signing-key.path
          else if generated == null then
            null
          else
            generated.files.key.path;
        defaultText = lib.literalExpression "osConfig.clan.core.vars.generators.<person>-commit-signing-key.files.key.path";
        description = ''
          Private key file git and jj sign with: the machine's generated
          `<person>-commit-signing-key`, the login key file `ssh-signing-key` on
          a machine in `flake.lib.commitSigningLegacyMachines`, or null in a
          standalone home, which then configures no signing.
        '';
      };

      config = lib.mkIf (key != null) {
        xdg.configFile."git/allowed_signers" = {
          text = allowedSigners {
            principal = config.vcs.author.email;
            inherit (meta) signingKey retiredSigningKeys;
          };
          # Homes activated before this module hold a symlink here into the
          # retired sops-nix template; home-manager otherwise refuses to clobber it.
          force = true;
        };
        programs.git = {
          signing = {
            inherit key;
            format = "ssh";
            signByDefault = true;
          };
          settings.gpg.ssh = {
            inherit program;
            allowedSignersFile = signers;
          };
        };
        programs.jujutsu.settings.signing = {
          inherit key;
          behavior = "own";
          backend = "ssh";
          backends.ssh = {
            inherit program;
            allowed-signers = signers;
          };
        };
      };
    };

  flake.modules.homeManager.development.imports = [ config.flake.modules.homeManager.vcs-signing ];
}

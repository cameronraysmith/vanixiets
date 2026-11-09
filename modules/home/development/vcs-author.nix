{ config, ... }:
{
  flake.modules.homeManager.vcs-author =
    {
      config,
      lib,
      flake,
      ...
    }:
    let
      profile = flake.lib.vcsAuthor flake.users.${config.home.username}.meta;
    in
    {
      key = "vanixiets/vcs-author-home-module";

      options.vcs.author = {
        name = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = profile.name;
          defaultText = lib.literalExpression "(flake.lib.vcsAuthor flake.users.\${config.home.username}.meta).name";
          description = "Author name git and jj record on new commits.";
        };
        email = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = profile.email;
          defaultText = lib.literalExpression "(flake.lib.vcsAuthor flake.users.\${config.home.username}.meta).email";
          description = "Author address git and jj record on new commits, and the allowed_signers principal.";
        };
      };

      config = {
        programs.git.settings.user = { inherit (config.vcs.author) name email; };
        programs.jujutsu.settings.user = { inherit (config.vcs.author) name email; };
      };
    };

  flake.modules.homeManager.development.imports = [ config.flake.modules.homeManager.vcs-author ];
}

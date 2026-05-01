{
  # OUTER: Flake-parts module signature
  ...
}:
let
  content =
    {
      # INNER: Home-manager module signature
      config,
      pkgs,
      flake, # from extraSpecialArgs
      ...
    }:
    {
      # Compose portable content via typed slot (nix-0pd.17 A5).
      imports = [ flake.users.raquel.contentPortable ];

      # sops-nix configuration for raquel user
      # 5 secrets: development + shell aggregates (NO AI)
      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/raquel/secrets.yaml";
        secrets = {
          github-token = { };
          ssh-signing-key = {
            mode = "0400";
          };
          ssh-public-key = { }; # NEW: For allowed_signers generation
          bitwarden-email = { };
          atuin-key = { };
        };

        # Generate allowed_signers file using sops.templates
        templates."allowed_signers" = {
          mode = "0400";
          path = "${config.xdg.configHome}/git/allowed_signers";
          content = ''
            ${flake.users.raquel.meta.email} namespaces="git" ${config.sops.placeholder."ssh-public-key"}
          '';
        };
      };

      # User-specific git identity from typed meta.
      # (Identity setters home.username/home.homeDirectory now provided by
      # users/raquel/identity.nix via flake.users.raquel.identity —
      # nix-0pd.17 A5.)
      programs.git.settings = {
        user.name = flake.users.raquel.meta.fullname;
        user.email = flake.users.raquel.meta.email;
      };
    };
in
{
  # Typed-slot writer (nix-0pd.17 A5: registry-key dual-write dropped).
  flake.users.raquel.contentPrivate = content;
}

{
  inputs,
  ...
}:
{
  # Flake-parts module exporting to base namespace (merged with other base modules)
  flake.modules.nixos.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      users.users = {
        crs58 = {
          isNormalUser = true;
          shell = pkgs.zsh;
          extraGroups = [ "wheel" ];
          # SSH keys from shared identity module
          openssh.authorizedKeys.keys = inputs.self.lib.userIdentities.crs58.sshKeys;
        };

        # Root inherits SSH keys from all wheel users
        root.openssh.authorizedKeys.keys = builtins.concatMap (user: user.openssh.authorizedKeys.keys) (
          builtins.attrValues (
            lib.filterAttrs (
              _name: value: value.isNormalUser && builtins.elem "wheel" value.extraGroups
            ) config.users.users
          )
        );
      };

      # Allow wheel group sudo without password
      security.sudo.wheelNeedsPassword = false;

      programs.zsh.enable = true;
    };
}

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
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+ camrn86@gmail.com"
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFXI36PvOzvuJQKVXWbfQE7Mdb6avTKU1+rV1kgy8tvp pixel7-termux"
          ];
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

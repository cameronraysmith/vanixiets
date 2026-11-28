{
  flake.modules.nixos.base-initrd-networking =
    { config, pkgs, ... }:
    {
      # The initrd SSH host key
      vanixiets.secrets.initrd-ssh = {
        files."id_ed25519".neededFor = "activation";
        files."id_ed25519.pub".secret = false;
        runtimeInputs = [
          pkgs.coreutils
          pkgs.openssh
        ];
        script = ''
          ssh-keygen -t ed25519 -N "" -f $out/id_ed25519
        '';
      };

      # Configure initrd networking for remote unlock
      boot.initrd.network = {
        enable = true;
        ssh = {
          enable = true;
          port = 2222; # Different from main SSH (22)
          hostKeys = [ config.vanixiets.secrets.initrd-ssh.files.id_ed25519.path ];
          authorizedKeys = config.users.users.root.openssh.authorizedKeys.keys;
        };
      };

      # Required kernel modules for virtualized environments
      boot.initrd.kernelModules = [
        "virtio_pci" # Virtualization
        "virtio_net" # Network devices
      ];
    };
}

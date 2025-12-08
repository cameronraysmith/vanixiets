{
  inputs,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    let
      # VM tests only work on Linux systems (need QEMU/KVM)
      isLinux = lib.hasSuffix "-linux" system;
    in
    {
      checks = lib.optionalAttrs isLinux {
        # TC-040: VM test framework smoke test
        vm-test-framework = pkgs.testers.runNixOSTest {
          name = "vm-test-framework-validation";
          nodes.machine = {
            # Minimal NixOS configuration for VM testing
            virtualisation.memorySize = 512;
          };
          testScript = ''
            machine.start()
            machine.wait_for_unit("multi-user.target")
            machine.succeed("echo 'VM test framework works'")
          '';
        };

        # TC-041: VM boot validation for NixOS machines
        vm-boot-all-machines =
          let
            # Create a VM node with basic config matching a machine name
            # This validates the naming and basic structure without full deployment config
            mkVMNode =
              machineName:
              { ... }:
              {
                imports = [
                  # Import srvos for SSH and server basics
                  inputs.srvos.nixosModules.server
                ];

                # VM environment settings
                virtualisation.memorySize = 1024;

                # Set hostname to match machine name
                networking.hostName = machineName;

                # Basic system configuration
                system.stateVersion = "25.05";
              };
          in
          pkgs.testers.runNixOSTest {
            name = "vm-boot-validation";
            nodes = {
              cinnabar = mkVMNode "cinnabar";
              electrum = mkVMNode "electrum";
            };

            testScript = ''
              start_all()

              # Wait for all machines to reach multi-user target
              cinnabar.wait_for_unit("multi-user.target")
              electrum.wait_for_unit("multi-user.target")

              # Verify basic services are running
              cinnabar.succeed("systemctl is-active sshd")
              electrum.succeed("systemctl is-active sshd")

              # Verify networking configuration (hostnames)
              cinnabar.succeed("hostname | grep cinnabar")
              electrum.succeed("hostname | grep electrum")
            '';
          };
      };
    };
}

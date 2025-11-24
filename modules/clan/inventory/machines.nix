{
  clan.inventory.machines = {
    cinnabar = {
      tags = [
        "nixos"
        "cloud"
        "hetzner"
        "controller"
      ];
      machineClass = "nixos";
      description = "Primary VPS, zerotier controller";
    };

    electrum = {
      tags = [
        "nixos"
        "cloud"
        "hetzner"
        "peer"
      ];
      machineClass = "nixos";
      description = "Secondary test VM, zerotier peer";
    };

    gcp-vm = {
      tags = [
        "nixos"
        "cloud"
        "gcp"
      ];
      machineClass = "nixos";
    };

    test-darwin = {
      tags = [
        "darwin"
        "test"
      ];
      machineClass = "darwin";
    };

    blackphos = {
      tags = [
        "darwin"
        "workstation"
        "laptop"
      ];
      machineClass = "darwin";
      description = "raquel's laptop (primary user), crs58 admin";
    };
  };
}

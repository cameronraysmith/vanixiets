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

    stibnite = {
      tags = [
        "darwin"
        "workstation"
        "laptop"
      ];
      machineClass = "darwin";
      description = "crs58's primary workstation";
    };

    rosegold = {
      tags = [
        "darwin"
        "workstation"
        "laptop"
      ];
      machineClass = "darwin";
      description = "janettesmith's laptop (primary user), cameron admin";
    };
  };
}

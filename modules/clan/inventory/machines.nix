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
      # deploy.targetHost = "root@cinnabar.zt";
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
      # deploy.targetHost = "root@electrum.zt";
    };

    galena = {
      tags = [
        "nixos"
        "cloud"
        "gcp"
        "peer"
      ];
      machineClass = "nixos";
      description = "GCP CPU node (e2-standard-8), zerotier peer";
      # deploy.targetHost = "root@galena.zt";
    };

    scheelite = {
      tags = [
        "nixos"
        "cloud"
        "gcp"
        "gpu"
        "peer"
      ];
      machineClass = "nixos";
      description = "GCP GPU node (n1-standard-8, T4), zerotier peer";
      # deploy.targetHost = "root@scheelite.zt";
    };

    blackphos = {
      tags = [
        "darwin"
        "workstation"
        "laptop"
        "fleet"
      ];
      machineClass = "darwin";
      description = "raquel's laptop (primary user), crs58 admin";
    };

    stibnite = {
      tags = [
        "darwin"
        "workstation"
        "laptop"
        "controller"
      ];
      machineClass = "darwin";
      description = "crs58's primary workstation, deployment controller";
    };

    rosegold = {
      tags = [
        "darwin"
        "workstation"
        "laptop"
        "fleet"
      ];
      machineClass = "darwin";
      description = "janettesmith's laptop (primary user), cameron admin";
    };

    argentum = {
      tags = [
        "darwin"
        "workstation"
        "laptop"
        "fleet"
      ];
      machineClass = "darwin";
      description = "christophersmith's laptop (primary user), cameron admin";
    };
  };
}

# Who builds for whom. Addresses are the deterministic ZeroTier IPv6s pinned
# in modules/system/ssh-known-hosts.nix.
#
# CI never reaches the darwin builders: nixbot.toml evaluates
# checks.x86_64-linux only, and modules/nixos/{nixbot,buildbot}.nix each set
# buildSystems = [ "x86_64-linux" ] as an independent second layer, because a
# sleeping laptop must not gate CI.
let
  # Laptops in interactive use: a minority share of the machine, refused on
  # battery, and run at Background QoS so the owner's foreground work keeps
  # the CPU and I/O.
  darwinLaptop = {
    systems = [ "aarch64-darwin" ];
    uid = 530;
    acceptOnBattery = false;
    daemonProcessType = "Background";
    daemonIOLowPriority = true;
  };
in
{
  clan.inventory.instances.nix-builders = {
    module = {
      name = "nix-builders";
      input = "self";
    };

    roles.builder.machines = {
      # Hetzner CX53. kvm is not advertised: there is no /dev/kvm (see
      # declaredKvm there), so QEMU VM tests must not route here, while
      # nspawn container tests needing only uid-range still do. speedFactor 2
      # puts it ahead of the rosetta builder and pyrite for x86_64-linux.
      magnetite.settings = {
        systems = [ "x86_64-linux" ];
        maxJobs = 8;
        speedFactor = 2;
        supportedFeatures = [
          "big-parallel"
          "nixos-test"
          "uid-range"
          "recursive-nix"
        ];
        address = "fddb:4344:343b:14b9:399:930f:39db:40d2";
        hostAlias = "magnetite";
      };

      # MacBookPro14,1: two cores, four threads, in interactive use, so one job
      # at a time. The fleet's only /dev/kvm, so the only route for
      # x86_64-linux kvm work; no big-parallel on two cores. An offline pyrite
      # fails kvm work with `missing system features` rather than degrading it
      # to an emulated build.
      pyrite.settings = {
        systems = [ "x86_64-linux" ];
        maxJobs = 1;
        supportedFeatures = [
          "kvm"
          "nixos-test"
        ];
        address = "fddb:4344:343b:14b9:399:937e:8067:8028";
      };

      # 18 logical cores, 64 GiB, half of which the rosetta builder and colima
      # each claim when running, so 4 remote jobs. apple-virt is real and only
      # here; nixos-test (a Linux sandbox capability nix lists anyway) and
      # benchmark (laptop timings are not measurements) are not advertised.
      # uid 530 was free on 2026-08-31 (501 crs58, 502 runner, 535
      # _dnscrypt-proxy, 551 omnigent-cameron).
      stibnite.settings = darwinLaptop // {
        maxJobs = 4;
        supportedFeatures = [
          "apple-virt"
          "big-parallel"
        ];
        address = "fddb:4344:343b:14b9:399:9324:19d9:3451";
      };

      # No hardware notes in their machine files, so the default share of 2
      # jobs. uid 530 is clear of every declared account there (501, 502,
      # 535 _dnscrypt-proxy).
      rosegold.settings = darwinLaptop // {
        maxJobs = 2;
        supportedFeatures = [ "big-parallel" ];
        address = "fddb:4344:343b:14b9:399:9315:3431:ee8";
      };
      argentum.settings = darwinLaptop // {
        maxJobs = 2;
        supportedFeatures = [ "big-parallel" ];
        address = "fddb:4344:343b:14b9:399:93f7:54d5:ad7e";
      };
    };

    roles.dispatcher.machines = {
      stibnite.settings.exclude = [
        "rosegold"
        "argentum"
      ];
      # stibnite subscribes to the same binary cache, so a dependency a
      # builder can substitute itself is not worth shipping over ZeroTier.
      # pyrite is excluded: it is a laptop with two cores, and magnetite
      # already builds x86_64-linux natively.
      magnetite.settings = {
        buildersUseSubstitutes = true;
        exclude = [ "pyrite" ];
      };
    };
  };
}

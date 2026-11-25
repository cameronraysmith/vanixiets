# Who builds for whom. Addresses are the builders' ZeroTier IPv6s, read from
# the registry (flake.lib.hosts); dispatchers connect to them directly over
# grpc:// and each builder's certificate names its own.
#
# nixbot on magnetite builds checks.aarch64-darwin, which it requires like
# every other check, on the darwin builders magnetite admits below: stibnite
# alone. With stibnite asleep or unreachable those checks fail, and nothing
# lands (modules/nixos/nixbot.nix).
{ config, ... }:
let
  inherit (config.flake.lib) hosts;

  # Laptops in interactive use: a minority share of the machine, run at
  # Background QoS so the owner's foreground work keeps the CPU and I/O.
  # Their nix-grpc-daemon account takes the upstream darwin default uid and
  # gid 450, clear of every declared account (501 crs58, 502 runner, 535
  # _dnscrypt-proxy, 551 omnigent-cameron).
  darwinLaptop = {
    systems = [ "aarch64-darwin" ];
    daemonProcessType = "Background";
    daemonIOLowPriority = true;
  };
in
{
  flake.clan.inventory.instances.nix-builders = {
    module = {
      name = "nix-builders";
      input = "self";
    };

    roles.builder.machines = {
      # Hetzner CX53. kvm is not advertised: there is no /dev/kvm (see
      # declaredKvm there), so QEMU VM tests must not route here, while
      # nspawn container tests needing only uid-range still do. speedFactor 2
      # puts it ahead of pyrite for x86_64-linux.
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
        address = hosts.magnetite.zerotier.address;
      };

      # MacBookPro14,1: two cores, four threads, in interactive use, so one job
      # at a time. The fleet's only /dev/kvm, so the only route for
      # x86_64-linux kvm work; no big-parallel on two cores. An offline pyrite
      # fails kvm work with `missing system features` rather than degrading it
      # to an emulated build. uid-range comes from its auto-allocate-uids
      # settings, as on magnetite, so nspawn container tests can route to
      # either.
      pyrite.settings = {
        systems = [ "x86_64-linux" ];
        maxJobs = 1;
        supportedFeatures = [
          "kvm"
          "nixos-test"
          "uid-range"
        ];
        address = hosts.pyrite.zerotier.address;
      };

      # 18 logical cores, 64 GiB. Most dispatched darwin work is tiny
      # derivations whose cost is per-build dispatch latency, not CPU: with 4
      # jobs, nixbot build 1301 left stibnite busy ~15% of the time. 16 jobs
      # can oversubscribe memory when colima (48 GiB) runs during several
      # large builds. apple-virt is real and only here; nixos-test (a Linux
      # sandbox capability nix lists anyway) and benchmark (laptop timings are
      # not measurements) are not advertised.
      stibnite.settings = darwinLaptop // {
        maxJobs = 16;
        supportedFeatures = [
          "apple-virt"
          "big-parallel"
        ];
        address = hosts.stibnite.zerotier.address;
      };

      # No hardware notes in their machine files, so the default share of 2
      # jobs.
      rosegold.settings = darwinLaptop // {
        maxJobs = 2;
        supportedFeatures = [ "big-parallel" ];
        address = hosts.rosegold.zerotier.address;
      };
      argentum.settings = darwinLaptop // {
        maxJobs = 2;
        supportedFeatures = [ "big-parallel" ];
        address = hosts.argentum.zerotier.address;
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
      # already builds x86_64-linux natively. rosegold and argentum are
      # excluded until nixbot's darwin builds have filled the binary cache
      # from stibnite; deleting a name here and redeploying magnetite admits
      # that machine, whose builder side is already in place.
      magnetite.settings = {
        buildersUseSubstitutes = true;
        exclude = [
          "pyrite"
          "rosegold"
          "argentum"
        ];
      };
      # pyrite has two cores and travels, so it sends x86_64-linux work to
      # magnetite, which builds it natively, and aarch64-darwin work to
      # stibnite. max-jobs stays above zero, so when no builder is reachable
      # nix falls back to building locally. Its builders substitute from the
      # same binary cache rather than receive dependencies over ZeroTier.
      # rosegold and argentum are excluded, as in stibnite's entry; the
      # service never makes a dispatcher its own builder.
      pyrite.settings = {
        buildersUseSubstitutes = true;
        exclude = [
          "rosegold"
          "argentum"
        ];
      };
    };
  };
}

# A soft memory guard on the user sessions of the host nixbot evaluates on
# (CAM-111 design D14, the "reclaim" rung of D9, operator decision Q47 of
# 2026-11-19): user.slice gets MemoryHigh and no MemoryMax, so above the limit
# the kernel throttles user sessions and reclaims their memory first, and
# kills nothing. nix-daemon, nixbot and system.slice stay unlimited: builds
# through nix-daemon are what warm nixbot's cache, and a user's evaluation is
# not, so throttling user evaluation keeps the warming. A hard MemoryMax, and
# moving development evaluation off the host, wait for CAM-112's dev host.
#
# The obligation is a module assertion, so the nixos-magnetite check, which
# evaluates the configuration, fails when user.slice loses its MemoryHigh or
# gains a MemoryMax; checks.x86_64-linux.user-slice-guard-obligations runs
# the judge, flake.lib.userSliceGuard.problems, over fixtures. The budget
# probe (./magnetite-memory-budget.nix) exports user.slice's memory.events
# `high` count, how often the guard throttles.
{ lib, ... }:
let
  memoryHigh = "10G";

  # One message per way user.slice's sliceConfig fails the guard.
  problems =
    sliceConfig:
    lib.optional (
      !(sliceConfig ? MemoryHigh)
      || lib.elem sliceConfig.MemoryHigh [
        null
        "infinity"
      ]
    ) "user.slice has no MemoryHigh"
    ++
      lib.optional (sliceConfig ? MemoryMax && sliceConfig.MemoryMax != null)
        "user.slice has MemoryMax ${builtins.toJSON sliceConfig.MemoryMax}; the guard is soft and kills nothing";
in
{
  flake.lib.userSliceGuard = {
    inherit memoryHigh problems;
  };

  flake.modules.nixos.magnetite-user-slice-guard =
    { config, ... }:
    {
      assertions = map (message: {
        assertion = false;
        message = "magnetite-user-slice-guard: ${message} (CAM-111 design D14).";
      }) (problems (config.systemd.slices.user.sliceConfig or { }));

      systemd.slices.user.sliceConfig.MemoryHigh = memoryHigh;
    };
}

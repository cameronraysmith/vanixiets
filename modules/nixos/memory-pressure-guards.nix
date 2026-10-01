# Kernel-side guards against memory-pressure collapse on hosts that run
# evaluations and builds next to services or a desktop.
#
# MGLRU thrash protection. With min_ttl_ms at its default 0 the multi-gen LRU
# will evict any generation, including the working set the host needs to keep
# making progress, so a sustained overcommit degrades into reclaim churn
# rather than an OOM kill. Setting it makes the kernel refuse to evict pages
# younger than the TTL and invoke the OOM killer instead when nothing older is
# left, which is the documented purpose of the knob
# (Documentation/admin-guide/mm/multigen_lru.rst, "Thrashing prevention").
# 1000 ms is the value that document suggests. The rule is a tmpfiles `w`, so
# it is applied at boot and again by systemd-tmpfiles-resetup on switch.
#
# sshd is deliberately absent. OpenSSH already moves its listener to
# oom_score_adj -1000 on Linux and restores the value it inherited in every
# forked session (openbsd-compat/port-linux.c oom_adjust_setup/_restore,
# platform-listen.c), measured live on magnetite and pyrite as listener -1000,
# sessions 0. An OOMScoreAdjust on sshd.service would become that inherited
# value and make every ssh session and everything run from it OOM-immune.
{
  flake.modules.nixos.memory-pressure-guards =
    { config, lib, ... }:
    {
      options.services.memoryPressureGuards.enable = lib.mkEnableOption "MGLRU thrash protection (lru_gen min_ttl_ms = 1000)";

      config = lib.mkIf config.services.memoryPressureGuards.enable {
        systemd.tmpfiles.rules = [ "w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 1000" ];
      };
    };
}

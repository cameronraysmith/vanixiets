{
  config,
  lib,
  ...
}:
let
  # The oracle is deliberately NOT the declaration. Restating `max-jobs == 2`
  # here would be two hand-synchronised copies of one fact, which can only fail
  # when someone edits one site and forgets the other — exactly the duplication
  # defect removed from modules/checks/pyrite-desktop.nix in
  # cameronraysmith/vanixiets#3108. What is asserted instead is the *invariant*
  # the numbers were chosen to satisfy, against a CPU count read from the
  # machine's own hardware report.
  #
  # machines/pyrite/facter.json is generated on the metal by nixos-facter and
  # is not derived from nix.settings, so it is an independent source: for this
  # machine hardware.cpu = [ { cores = 2; siblings = 4; ... } ], one package,
  # two physical cores, four threads. `siblings` is the logical count, which is
  # what nix schedules against (nix's `max-jobs = auto` resolves to
  # std::thread::hardware_concurrency, i.e. 4 here, not 2).
  #
  # `siblings` is per package, so the total is a sum. pyrite is single-socket
  # and the length is asserted below rather than assumed: if a future facter
  # emits one entry per logical CPU instead of one per package, the sum would
  # silently inflate to 16 and quietly loosen the bound this check exists to
  # hold. That must fail loudly, not pass.
  facter = builtins.fromJSON (builtins.readFile ../../machines/pyrite/facter.json);
  packages = facter.hardware.cpu;
  threads = lib.foldl' (total: cpu: total + cpu.siblings) 0 packages;
  physicalCores = lib.foldl' (total: cpu: total + cpu.cores) 0 packages;
in
{
  perSystem =
    { system, ... }:
    lib.mkIf (system == "x86_64-linux") {
      checks.pyrite-nix-concurrency =
        let
          machine = config.flake.nixosConfigurations.pyrite;
          cfg = machine.config;
          pkgs = machine.pkgs;
          maxJobs = cfg.nix.settings.max-jobs;
          cores = cfg.nix.settings.cores;

          # Both settings must be explicit integers. nix's own defaults are
          # `max-jobs = auto` (a string) and `cores = 0`, and "the daemon runs
          # nix's defaults" is the state this machine was measured out of; a
          # regression back to either is the first thing to catch.
          declared = builtins.isInt maxJobs && builtins.isInt cores;

          # `cores = 0` is not zero threads, it is *every* thread, so folding it
          # into the product as a literal 0 would make the inequality trivially
          # true. Expand it to the real count before multiplying.
          effectiveCores = if cores == 0 then threads else cores;

          # 2 x 2 = 4 = threads. The bound is `<=`, not `==`, so retuning to
          # 1x4, 4x1, 2x1 or 1x2 stays green; what it rejects is a product above
          # the thread count, which is the direction that walks the machine back
          # toward the memory edge measured in
          # logs/pyrite-nix-concurrency-report.md.
          demand = maxJobs * effectiveCores;
        in
        assert lib.assertMsg (threads > 0 && builtins.length packages == 1)
          "pyrite nix concurrency: machines/pyrite/facter.json must report exactly one CPU package with a positive siblings count; pyrite is single-socket, and any other shape means hardware.cpu no longer means what this check reads it to mean. Re-run nixos-facter and re-derive the thread count before trusting the bound";
        assert lib.assertMsg (declared)
          "pyrite nix concurrency: nix.settings.max-jobs and nix.settings.cores must both be explicit integers on pyrite; nix's defaults (max-jobs = auto, cores = 0) oversubscribe a 2-core laptop";
        assert lib.assertMsg (
          maxJobs >= 1 && cores >= 0
        ) "pyrite nix concurrency: max-jobs must be at least 1 and cores must not be negative";
        assert lib.assertMsg (demand <= threads) ''
          pyrite nix concurrency: max-jobs x cores = ${toString maxJobs} x ${toString effectiveCores} = ${toString demand},
          above the ${toString threads} logical CPUs machines/pyrite/facter.json reports for this machine
          (${toString (builtins.length packages)} package(s), ${toString physicalCores} physical cores).
          pyrite is a 15 W dual-core laptop and also a daily driver; oversubscribing both axes
          is the configuration that was measured and rejected in logs/pyrite-nix-concurrency-report.md.
          If the hardware changed, regenerate machines/pyrite/facter.json; if the tuning changed,
          re-measure before raising the product above the thread count.
        '';
        pkgs.runCommand "pyrite-nix-concurrency"
          {
            passthru.meta.description = "pyrite's declared nix job concurrency does not oversubscribe the CPU count its hardware report states";
          }
          ''
            mkdir -p "$out"
            cat > "$out/concurrency" <<EOF
            facter-threads=${toString threads}
            facter-physical-cores=${toString physicalCores}
            max-jobs=${toString maxJobs}
            cores=${toString cores}
            effective-cores=${toString effectiveCores}
            demand=${toString demand}
            EOF
            cat "$out/concurrency"
          '';
    };
}

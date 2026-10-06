# Structural check for `flake.modules.homeManager.devin`'s worker surface
# (see modules/home/ai/devin/worker.nix).
#
# Two hosts enable the module, but their machine configurations only assert
# what those two deployments happen to need. What the module promises for any
# enabled host is checked here instead, for both platforms, with a dummy token
# path in place of the sops-nix secret so no real path is a build input. Only
# names, counts, and booleans are serialized into the diff, so this check
# evaluates and never builds a worker's launcher. Each probe names its own
# system, so the result does not depend on the evaluating platform and the
# check is defined for x86_64-linux only.
#
# Two evaluation vehicles, for two different reasons.
#
#   * The positive claims run through a minimal real
#     `homeManagerConfiguration` on both platforms, so launchd plist keys and
#     systemd unit sections are validated by the actual option types rather
#     than by a stub of them.
#
#   * The assertion claims run through a bare `lib.evalModules` against the
#     same deferred module. home-manager throws on the whole configuration
#     when any assertion fails, which makes the failure observable but hides
#     WHICH clause fired; outside that wrapper the resolved `assertions` list
#     is an ordinary value and each clause can be identified.
#
# Claims exercised:
#
# 1. Platform routing and instance fan-out: `workers = 2` produces exactly two
#    launchd agents and no systemd units on darwin, and exactly two systemd
#    user services and no launchd agents on linux.
#
# 2. No credential in the unit definition. A launchd plist and a systemd unit
#    are Nix store files readable by every user on the machine, which is why
#    the token is read from a file by the launcher at start. The service
#    environment is therefore required to carry PATH and nothing else.
#
# 3. Per-instance working directories: session repositories live under
#    `$(pwd)/repos`, so two instances sharing a working directory would race
#    on the same checkout.
#
# 4. Each assertion clause fires on exactly its own malformed input, and a
#    well-formed configuration fires none. The token probe leaves the sibling
#    queue fully wired, so it also shows that a queue whose own credential is
#    missing does not borrow another queue's.
#
# Severity rationale (Mayo): each claim fails under a plausible incorrect
# implementation. Dropping the `mkIf isDarwin` / `mkIf isLinux` gates puts
# units on both platforms and breaks claim 1. Moving the token into
# `EnvironmentVariables` or `Environment` -- the shortcut this module exists
# to refuse -- adds a key and breaks claim 2. Deriving the working directory
# from the outpost alone rather than from the instance index collapses the two
# paths and breaks claim 3. Weakening any assertion to a tautology empties its
# fired-clause list, and strengthening one into an always-firing predicate
# populates `wellFormed`, so claim 4 is falsifiable in both directions.
{
  inputs,
  lib,
  self,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;

      # The same package set the home configurations get (see
      # modules/home/mk-home.nix): `self.legacyPackages` is the channel before
      # flake.overlays.default is applied, where `devin-cli` would resolve to
      # the channel's older build rather than the one this repository vendors.
      probePkgs =
        system:
        import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ self.overlays.default ];
        };

      # Real home-manager evaluation: option types enforced, assertions
      # required to pass (home-manager throws otherwise, so reaching the
      # values below is itself part of the positive claim).
      evalHome =
        {
          system,
          homeDirectory,
          worker,
        }:
        (inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = probePkgs system;
          # Same reason as modules/home/mk-home.nix: a module formal that the
          # module system cannot resolve throws rather than taking its default.
          extraSpecialArgs.osConfig = null;
          modules = [
            self.modules.homeManager.devin
            {
              home = {
                username = "probe";
                inherit homeDirectory;
                stateVersion = "25.05";
              };
              services.devin-worker = worker;
            }
          ];
        }).config;

      # Bare module evaluation, for inspecting the assertions themselves.
      evalBare =
        system: worker:
        (lib.evalModules {
          specialArgs.osConfig = null;
          modules = [
            self.modules.homeManager.devin
            {
              _module.check = false;
              _module.args.pkgs = probePkgs system;
              freeformType = lib.types.lazyAttrsOf lib.types.raw;
            }
            { services.devin-worker = worker; }
          ];
        }).config;

      # Only the token files are supplied: the ids, platforms and names come
      # from the module's own registry, so these probes also show that a
      # partial definition merges with it instead of replacing it -- an option
      # `default` would have dropped the entries and the platforms.
      wired = {
        "stibnite".tokenFile = "/run/secrets/devin-outposts-token-stibnite.dummy";
        "magnetite".tokenFile = "/run/secrets/devin-outposts-token-magnetite.dummy";
      };

      darwin = evalHome {
        system = "aarch64-darwin";
        homeDirectory = "/Users/probe";
        worker = {
          enable = true;
          workers = 2;
          outpost = "stibnite";
          outposts = wired;
        };
      };

      linux = evalHome {
        system = "x86_64-linux";
        homeDirectory = "/home/probe";
        worker = {
          enable = true;
          workers = 2;
          outpost = "magnetite";
          outposts = wired;
        };
      };

      agents = config: lib.attrNames (config.launchd.agents or { });
      units = config: lib.attrNames (config.systemd.user.services or { });

      # Failing clauses, named by a distinctive substring of their message so
      # the diff identifies the clause instead of embedding whole prose.
      firedClauses =
        config:
        map (
          message:
          if lib.hasInfix "tokenFile is null" message then
            "token"
          else if lib.hasInfix "id is null" message then
            "id"
          else if lib.hasInfix "registered for platform" message then
            "platform"
          else if lib.hasInfix "not a key of" message then
            "unknown-outpost"
          else if lib.hasInfix "has not been told which queue it serves" message then
            "unset-outpost"
          else
            "unrecognized: ${message}"
        ) (map (a: a.message) (lib.filter (a: !a.assertion) config.assertions));

      # Warnings are the third platform state: neither an assertion failure nor
      # silence.
      warnedClauses =
        config:
        map (
          message:
          if lib.hasInfix "carries no platform" message then "platform-unset" else "unrecognized: ${message}"
        ) (config.warnings or [ ]);

      # A no-platform queue selected on a darwin host: warned, not asserted.
      # The registry gives magnetite a platform, so the null is set here
      # explicitly -- a plain definition outranks the registry's mkDefault.
      platformUnsetProbe = evalBare "aarch64-darwin" {
        enable = true;
        outpost = "magnetite";
        outposts = wired // {
          "magnetite" = {
            platform = null;
            inherit (wired."magnetite") tokenFile;
          };
        };
      };

      distinctWorkDirs = paths: paths != [ ] && lib.length (lib.unique paths) == lib.length paths;
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        devin-worker-structural = mkCheck {
          name = "devin-worker-structural";
          actual = {
            darwinAgents = agents darwin;
            darwinUnits = units darwin;
            darwinPlistEnvKeys =
              lib.attrNames
                darwin.launchd.agents."devin-worker-1".config.EnvironmentVariables;
            darwinWorkDirsDistinct = distinctWorkDirs (
              map (name: darwin.launchd.agents.${name}.config.WorkingDirectory) (agents darwin)
            );
            # Restart behaviour, which is where the two supervisors differ. On
            # darwin the worker is kept alive by the presence of its own token
            # file, so a missing secret stops it instead of respawning at
            # launchd's floor; `KeepAlive = true` would reintroduce that loop.
            darwinKeepAliveOnTokenPath =
              lib.attrNames
                darwin.launchd.agents."devin-worker-1".config.KeepAlive.PathState;

            linuxUnits = units linux;
            linuxAgents = agents linux;
            linuxUnitEnvNames = map (
              entry: lib.head (lib.splitString "=" entry)
            ) linux.systemd.user.services."devin-worker-1".Service.Environment;
            linuxWorkDirsDistinct = distinctWorkDirs (
              map (name: linux.systemd.user.services.${name}.Service.WorkingDirectory) (units linux)
            );

            # `outpost` must have nothing to resolve on its own. A default that
            # inferred it from the host's platform is what would put every linux
            # machine in this repository on the same queue.
            outpostDefault = (evalBare "x86_64-linux" { }).services.devin-worker.outpost;

            # Each host's selected queue matches its platform, so neither warns.
            darwinWarned = warnedClauses darwin;
            linuxWarned = warnedClauses linux;

            wellFormed = firedClauses (
              evalBare "aarch64-darwin" {
                enable = true;
                outpost = "stibnite";
                outposts = wired;
              }
            );
            # The sibling queue keeps its token, so this also shows a queue whose
            # own file is missing does not fall back to another's.
            tokenless = firedClauses (
              evalBare "aarch64-darwin" {
                enable = true;
                outpost = "stibnite";
                outposts = {
                  "magnetite".tokenFile = wired."magnetite".tokenFile;
                };
              }
            );
            idless = firedClauses (
              evalBare "aarch64-darwin" {
                enable = true;
                outpost = "stibnite";
                outposts = wired // {
                  "stibnite" = {
                    id = null;
                    inherit (wired."stibnite") tokenFile;
                  };
                };
              }
            );
            # Both platforms named and different, which is the only mismatch the
            # module asserts on.
            platformMismatch = firedClauses (
              evalBare "aarch64-darwin" {
                enable = true;
                outpost = "magnetite";
                outposts = wired // {
                  "magnetite" = {
                    platform = "linux";
                    inherit (wired."magnetite") tokenFile;
                  };
                };
              }
            );
            platformUnsetFired = firedClauses platformUnsetProbe;
            platformUnsetWarned = warnedClauses platformUnsetProbe;
            unknownOutpost = firedClauses (
              evalBare "aarch64-darwin" {
                enable = true;
                outpost = "no-such-queue";
                outposts = wired;
              }
            );
            # The regression this module's shape exists to prevent, in the form
            # it will arrive: pyrite and cinnabar are linux machines coming up
            # shortly on this same user. Enabling the worker there without naming
            # a queue must fail, because the alternative -- inferring one -- puts
            # them on magnetite's queue, where they would serve its sessions
            # perfectly well and report nothing.
            secondLinuxHostUnnamed = firedClauses (evalBare "x86_64-linux" { enable = true; });
            # And naming a queue whose credential this host does not have fails
            # by name rather than borrowing a sibling's.
            secondLinuxHostBorrowing = firedClauses (
              evalBare "x86_64-linux" {
                enable = true;
                outpost = "magnetite";
              }
            );
          };
          expected = {
            darwinAgents = [
              "devin-worker-1"
              "devin-worker-2"
            ];
            darwinUnits = [ ];
            darwinPlistEnvKeys = [ "PATH" ];
            darwinWorkDirsDistinct = true;
            darwinKeepAliveOnTokenPath = [ "/run/secrets/devin-outposts-token-stibnite.dummy" ];

            linuxUnits = [
              "devin-worker-1"
              "devin-worker-2"
            ];
            linuxAgents = [ ];
            linuxUnitEnvNames = [ "PATH" ];
            linuxWorkDirsDistinct = true;

            outpostDefault = null;
            darwinWarned = [ ];
            linuxWarned = [ ];

            wellFormed = [ ];
            tokenless = [ "token" ];
            idless = [ "id" ];
            platformMismatch = [ "platform" ];
            platformUnsetFired = [ ];
            platformUnsetWarned = [ "platform-unset" ];
            unknownOutpost = [ "unknown-outpost" ];
            secondLinuxHostUnnamed = [ "unset-outpost" ];
            secondLinuxHostBorrowing = [ "token" ];
          };
        };
      };
    };
}

# Structural check for nixbot's per-repository wiring.
#
# It guards the secret name transform, a failure mode indistinguishable from
# success by inspection. nixbot derives the systemd credential name it looks a
# repository's secrets up under by substituting ":" and "/" in the
# perRepoSecretFiles key; when that name does not match, the daemon finds no
# secrets, delivers an empty set, and every effect stops at its own
# missing-secret guard — exactly what an unwired service does. The check reads
# the name off the evaluated unit, so it exercises nixbot's own module code
# rather than a transcription of it. It also pins the facts that span modules
# or upstream behaviour: the unit's memory/OOM knob set, the binary-cache
# uploader set, that nixbot and buildbot share one secrets file and serve
# disjoint repositories, that every declared effect secret is used, and that
# darwin checks are best-effort without changing their derivations. Values
# set as literals in modules/nixos/nixbot.nix and buildbot.nix are not
# restated here.
#
# The repository-root config file is nixbot.toml. nixbot prefers that name over
# the legacy buildbot-nix.toml it also still reads
# (nixbot/nixbot/repo_config.py:17), and buildbot no longer serves either
# GitHub repository, so nothing reads the legacy name here.
{
  config,
  self,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;
      sortedNames = attrset: lib.naturalSort (builtins.attrNames attrset);

      magnetite = self.nixosConfigurations.magnetite.config;
      nixbot = magnetite.services.nixbot;
      buildbot = magnetite.services.buildbot-nix.master;

      # LoadCredential entries are "<name>:<source path>". The name never
      # contains a colon, because the transform that builds it replaces every
      # colon in the repository key, so the first field is exact. Keeping only
      # the name also keeps the oracle free of activation-time paths.
      credentialName = entry: builtins.head (lib.splitString ":" entry);
      effectsCredentialNames = lib.naturalSort (
        builtins.filter (lib.hasPrefix "effects-secret__") (
          map credentialName magnetite.systemd.services.nixbot.serviceConfig.LoadCredential
        )
      );

      # Every memory/OOM property the evaluated unit carries, by name. This is
      # the regulator for a deliberately near-empty set: MemoryHigh throttles
      # and never kills, while MemoryMax or any OOM* knob would move the OOM
      # domain off nixbot's delegated eval leaf onto the whole service and put
      # the daemon itself in the kernel's victim pool
      # (logs/nixbot-memorymax-oom-victim.md). The match is by name, so an
      # unrelated hardening property such as MemoryDenyWriteExecute would also
      # surface here and has to be admitted deliberately.
      nixbotUnit = magnetite.systemd.services.nixbot.serviceConfig;
      memoryAndOomKnobs = lib.naturalSort (
        builtins.filter (n: lib.hasInfix "Memory" n || lib.hasInfix "OOM" n) (builtins.attrNames nixbotUnit)
      );

      # Each service's own repository filter, transcribed with its citation so
      # the two selections can be asserted rather than described. Both take
      # the topic first and then the allowlists; only the allowlist stage is
      # modelled here, because a forge topic is not visible to evaluation.
      owner = fullName: builtins.head (lib.splitString "/" fullName);

      # buildbot_nix/buildbot_nix/common.py:138-148, with full_name as the
      # repo accessor (github_projects.py:225). The two allowlists are OR'd.
      buildbotAdmits =
        fullName:
        let
          f = buildbot.github;
        in
        (f.userAllowlist == null && f.repoAllowlist == null)
        || (f.userAllowlist != null && builtins.elem (owner fullName) f.userAllowlist)
        || (f.repoAllowlist != null && builtins.elem fullName f.repoAllowlist);

      # nixbot/nixbot/forge/base.py:128-141, the same shape.
      nixbotAdmits =
        fullName:
        let
          f = nixbot.github;
        in
        (f.userAllowlist == null && f.repoAllowlist == null)
        || (f.userAllowlist != null && builtins.elem (owner fullName) f.userAllowlist)
        || (f.repoAllowlist != null && builtins.elem fullName f.repoAllowlist);
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        nixbot-wiring = mkCheck {
          name = "nixbot-wiring";
          actual = {
            effectsCredentialNames = effectsCredentialNames;
            memoryAndOomKnobs = memoryAndOomKnobs;

            # Booleans rather than the paths themselves: the assertion is that
            # each repository buildbot still holds secrets for reads the same
            # file as nixbot, and the paths are activation-time state that
            # would churn the oracle without adding evidence. Keyed by
            # repository so a failure names which one diverged. buildbot admits
            # neither repository, so its copies are inert; asserting them keeps
            # a later re-admission from silently reading a different file.
            oneSecretsFileForBothServices = lib.genAttrs (sortedNames buildbot.effects.perRepoSecretFiles) (
              key: nixbot.effects.perRepoSecretFiles.${key} == buildbot.effects.perRepoSecretFiles.${key}
            );

            # Every declared effect secret is read by some trigger of some
            # effect and every secret a trigger reads is declared, so the
            # composed file holds nothing no effect uses.
            effectSecretsUsed = lib.naturalSort (
              lib.unique (
                lib.concatMap (
                  entry:
                  lib.concatMap (trigger: trigger.secrets) (
                    builtins.filter (trigger: trigger != null) (builtins.attrValues entry.triggers)
                  )
                ) (builtins.attrValues config.vanixiets.effects)
              )
            );

            # The cut itself. nixbot serves both repositories and buildbot
            # serves neither on GitHub, so the two selections are disjoint.
            buildbotAdmitsVanixiets = buildbotAdmits "cameronraysmith/vanixiets";
            buildbotAdmitsIronstar = buildbotAdmits "sciexp/ironstar";
            nixbotAdmitsVanixiets = nixbotAdmits "cameronraysmith/vanixiets";
            nixbotAdmitsIronstar = nixbotAdmits "sciexp/ironstar";

            # Binary-cache upload is nixbot's uploader set since upstream's
            # niks3 integration stopped emitting a per-attribute post-build
            # step and started registering a whole-closure uploader instead
            # (Mic92/nixbot cb0e0719, nixosModules/niks3.nix:40). An empty
            # uploader set is a service that builds correctly and uploads
            # nothing, which is indistinguishable from success by inspection,
            # so it is asserted on its own line rather than left to fall out
            # of a structural diff of the names. legacyPostBuildStepNames
            # catches the inverse regression: postBuildSteps still exists
            # upstream and unaliased, so something re-introducing a post-build
            # step in place of an uploader would otherwise be silent.
            uploadsSomewhere = nixbot.uploaders != [ ];
            uploaderNames = map (uploader: uploader.name) nixbot.uploaders;
            uploaderCommandsNonEmpty = lib.all (uploader: uploader.command != [ ]) nixbot.uploaders;
            legacyPostBuildStepNames = map (step: step.name) nixbot.postBuildSteps;

            # Darwin checks are best-effort without changing what they build
            # (modules/checks/nixbot-best-effort-darwin.nix). One mapAttrs
            # marks every check, so the names and one representative prove it
            # without forcing all darwin derivations here.
            darwinCheckNamesUnchanged =
              sortedNames self.checks.aarch64-darwin == sortedNames config.allSystems.aarch64-darwin.checks;
            darwinRepresentative =
              let
                check = self.checks.aarch64-darwin.jj-pr-tags-rehearsal;
              in
              {
                ignoreFailure = check.ignoreFailure or false;
                sameDerivation =
                  check.drvPath == config.allSystems.aarch64-darwin.checks.jj-pr-tags-rehearsal.drvPath;
              };
            linuxRepresentativeBestEffort = self.checks.x86_64-linux.jj-pr-tags-rehearsal ? ignoreFailure;
          };
          expected = {
            # Both repositories' secrets files are wired to nixbot's
            # convention, so nixbot loads a credential for each and their
            # effects run rather than stopping at a missing-secret guard.
            effectsCredentialNames = [
              "effects-secret__github_colon_cameronraysmith_slash_vanixiets"
              "effects-secret__github_colon_sciexp_slash_ironstar"
            ];
            memoryAndOomKnobs = [ "MemoryHigh" ];
            oneSecretsFileForBothServices = {
              "github:sciexp/ironstar" = true;
            };
            effectSecretsUsed = sortedNames self.lib.vanixietsEffectSecrets;
            buildbotAdmitsVanixiets = false;
            buildbotAdmitsIronstar = false;
            nixbotAdmitsVanixiets = true;
            nixbotAdmitsIronstar = true;
            uploadsSomewhere = true;
            uploaderNames = [ "niks3" ];
            uploaderCommandsNonEmpty = true;
            legacyPostBuildStepNames = [ ];
            darwinCheckNamesUnchanged = true;
            darwinRepresentative = {
              ignoreFailure = true;
              sameDerivation = true;
            };
            linuxRepresentativeBestEffort = false;
          };
        };
      };
    };
}

# One structural regulator for the atomic/pi extension divergence.
#
# The atomic analogue of modules/checks/pi-agent-environment.nix, sharing its
# mechanism: mkStructuralCheck diffs eval-time home-manager values against a
# literal oracle, so a failure names the violated claim as a unified diff.
#
# What this guards. modules/home/ai/agent-settings.nix generates one settings
# payload for two agents, and `packages` is the single key they do not share
# verbatim. It diverges twice over, through two different mechanisms that this
# check asserts separately because a change can break either one alone.
#
# Within a shared package entry, atomic takes packagesForAtomic, which appends
# atomicExtensionExclusions as `-`-prefixed force-excludes. The divergence is
# deliberate and one-sided, and both halves have to hold at once — atomic must
# exclude statusline because atomic 0.9.13's isolated interactive engine refuses
# ctx.ui.setFooter, and pi must keep it because pi honours that call in-process.
# Asserting only atomic's half would pass a change that silently disarmed the
# extension for both agents.
#
# At the level of whole entries, pi's list is the shared one plus
# aiAgentSettings.piOnlyPackages, which needs no force-exclude: atomic declaring
# its own `packages` shadows pi's array wholesale. pi-vim is the entry that
# relies on this, and the claim is two-sided for the same reason — an entry that
# reached atomic too would load, warn on the setEditorComponent stub, and leave
# atomic's native editor in place with no modal keybindings, which is invisible
# from atomic's side alone.
#
# Falsifiability: dropping "statusline/index.ts" from atomicExtensionExclusions
# flips atomicNegativeExtensions against the literal below; propagating the
# exclusion to pi flips piNegativeExtensions. Moving pi-vim from piOnlyPackages
# into packages flips atomicPiOnlyPackages; dropping it flips piOnlyPackages.
#
# atomicDeclaresPackages is asserted separately rather than inferred from the
# selector lists: a change that stopped declaring `packages` would leave atomic
# on its default package set, and that failure is invisible in the generated
# payload and visible only as the key's absence.
#
# Evidence boundary. This claims declaration shape alone: that the two agents'
# settings carry the selectors named below. It does not claim that atomic
# resolves those selectors as intended at runtime, which is upstream behavior
# (core/package-manager-resource-patterns.ts applies force-excludes last), nor
# that the extension package's contents are what its name suggests.
{ self, lib, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      system,
      ...
    }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;
      homeConfig = self.homeConfigurations."crs58@${system}".config;
      atomicConfig = homeConfig.programs.atomic;
      piConfig = homeConfig.programs.pi-coding-agent;
      extensionPackage = self'.packages.pi-agent-extensions or null;
      extensionSource = if extensionPackage == null then null else toString extensionPackage;
      selectorsFor =
        settings:
        let
          entry = lib.findFirst (
            candidate: builtins.isAttrs candidate && (candidate.source or null) == extensionSource
          ) null (settings.packages or [ ]);
        in
        if entry == null then [ ] else entry.extensions or [ ];
      atomicSelectors = selectorsFor atomicConfig.settings;
      piSelectors = selectorsFor piConfig.settings;
      positive = builtins.filter (selector: !lib.hasPrefix "-" selector);
      negative = builtins.filter (selector: lib.hasPrefix "-" selector);
      # A piOnlyPackages entry is a bare store-path string. It is reported by
      # package name rather than by path: a hash in the oracle would churn on
      # every unrelated rebuild, and mkStructuralCheck serializes `actual` into a
      # derivation attribute, which refuses a string carrying store-path context.
      piOnlyPaths = map toString homeConfig.aiAgentSettings.piOnlyPackages;
      nameOf =
        path:
        let
          base = builtins.unsafeDiscardStringContext (builtins.baseNameOf path);
          stripped = builtins.match "[a-z0-9]+-(.*)" base;
        in
        lib.getName (if stripped == null then base else builtins.head stripped);
      piOnlyNamesIn =
        settings:
        let
          declared = settings.packages or [ ];
        in
        map nameOf (
          builtins.filter (
            path: lib.any (entry: !builtins.isAttrs entry && entry == path) declared
          ) piOnlyPaths
        );
    in
    {
      checks = {
        atomic-agent-environment-structural = mkCheck {
          name = "atomic-agent-environment";
          actual = {
            atomicDeclaresPackages = builtins.hasAttr "packages" atomicConfig.settings;
            atomicPositiveExtensions = positive atomicSelectors;
            atomicNegativeExtensions = negative atomicSelectors;
            piPositiveExtensions = positive piSelectors;
            piNegativeExtensions = negative piSelectors;
            # The divergence must live in the selectors, not in a forked package:
            # two sources would make the lists incomparable and the exclusion
            # meaningless.
            sharedExtensionSource = atomicSelectors != [ ] && piSelectors != [ ];
            # Whole-entry divergence, the channel that carries no force-exclude
            # and is therefore invisible in the selector lists above.
            piOnlyPackages = map nameOf piOnlyPaths;
            piPiOnlyPackages = piOnlyNamesIn piConfig.settings;
            atomicPiOnlyPackages = piOnlyNamesIn atomicConfig.settings;
          };
          expected = {
            atomicDeclaresPackages = true;
            atomicPositiveExtensions = [
              "direnv/index.ts"
              "permission-gate/index.ts"
              "questionnaire/index.ts"
              "slow-mode/index.ts"
              "stash/index.ts"
              "statusline/index.ts"
            ];
            # statusline is force-excluded rather than removed from the positive
            # list: atomic applies `-` entries last and unconditionally, so the
            # exclusion survives a later change that widens the include set.
            atomicNegativeExtensions = [
              "-fetch/index.ts"
              "-notify/index.ts"
              "-statusline/index.ts"
            ];
            piPositiveExtensions = [
              "direnv/index.ts"
              "permission-gate/index.ts"
              "questionnaire/index.ts"
              "slow-mode/index.ts"
              "stash/index.ts"
              "statusline/index.ts"
            ];
            piNegativeExtensions = [
              "-fetch/index.ts"
              "-notify/index.ts"
            ];
            sharedExtensionSource = true;
            piOnlyPackages = [ "pi-vim" ];
            piPiOnlyPackages = [ "pi-vim" ];
            atomicPiOnlyPackages = [ ];
          };
        };
      };
    };
}

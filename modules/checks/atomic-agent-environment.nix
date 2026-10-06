# One structural regulator for the cross-module wiring between atomic and pi.
#
# modules/home/ai/agent-settings.nix generates one settings payload for two
# agents and names every deliberate divergence as its own option. Each value
# there is a literal, so restating it here would only catch someone editing it.
# What can break silently is the wiring: a consumer reading the wrong option, or
# a divergence leaking to the other agent. Every field below is therefore a
# relation between the two evaluated settings, not a copy of a literal, and the
# check is defined for x86_64-linux only because none of it depends on the
# platform.
#
# Selectors. atomic must receive pi's shared selectors plus
# atomicExtensionExclusions as `-`-prefixed force-excludes, and pi must not
# carry those force-excludes: atomic's isolated engine refuses ctx.ui.setFooter,
# while pi honours it in-process, so asserting only atomic's half would pass a
# change that disarmed statusline for both agents.
#
# Whole entries. pi-only packages (pi-vim) need no force-exclude because atomic
# declaring its own `packages` key shadows pi's array wholesale. The claim is
# two-sided: an entry that also reached atomic would load and warn on the
# setEditorComponent stub with no visible effect from atomic's side.
#
# Pi-only extension files. atomic scans ~/.pi/agent/extensions unconditionally,
# so each piOnlyExtensions file must be force-excluded under the
# root-relative `-extensions/<file>` spelling; the bare basename spelling is a
# silent no-op. The edit/write policy reached atomic through this gap for three
# days.
#
# Skill sink. ~/.agents/skills is canonical; a ~/.pi/agent/skills sink would
# shadow it.
#
# Evidence boundary. This claims declaration shape alone. It does not claim
# that atomic resolves those selectors as intended at runtime, which is upstream
# behaviour (core/package-manager-resource-patterns.ts applies force-excludes
# last).
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
      agentSettings = homeConfig.aiAgentSettings;
      atomicSettings = homeConfig.programs.atomic.settings;
      piSettings = homeConfig.programs.pi-coding-agent.settings;
      extensionSource = toString self'.packages.pi-agent-extensions;
      selectorsFor =
        settings:
        let
          entry = lib.findFirst (
            candidate: builtins.isAttrs candidate && (candidate.source or null) == extensionSource
          ) null (settings.packages or [ ]);
        in
        if entry == null then [ ] else entry.extensions or [ ];
      atomicSelectors = selectorsFor atomicSettings;
      piSelectors = selectorsFor piSettings;
      atomicForceExcludes = map (extension: "-${extension}") agentSettings.atomicExtensionExclusions;
      declaresEntry = settings: entry: builtins.elem entry (settings.packages or [ ]);
      atomicExtensions = atomicSettings.extensions or [ ];
      activationScripts = map (entry: entry.data or "") (builtins.attrValues homeConfig.home.activation);
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        atomic-agent-environment-structural = mkCheck {
          name = "atomic-agent-environment";
          actual = {
            # Without its own `packages` key atomic falls back to pi's array, so
            # every whole-entry divergence below would vanish.
            atomicDeclaresPackages = builtins.hasAttr "packages" atomicSettings;
            sharedExtensionSource = piSelectors != [ ];
            atomicSelectorsArePiPlusExclusions = atomicSelectors == piSelectors ++ atomicForceExcludes;
            piKeepsAtomicExclusions = !lib.any (exclude: builtins.elem exclude piSelectors) atomicForceExcludes;
            piReceivesPiOnlyPackages = lib.all (declaresEntry piSettings) agentSettings.piOnlyPackages;
            atomicLacksPiOnlyPackages = !lib.any (declaresEntry atomicSettings) agentSettings.piOnlyPackages;
            everyPiOnlyExtensionExcluded = lib.all (
              extension: builtins.elem "-extensions/${extension}" atomicExtensions
            ) agentSettings.piOnlyExtensions;
            noBareBasenameSpelling =
              !lib.any (
                entry: lib.any (extension: entry == "-${extension}") agentSettings.piOnlyExtensions
              ) atomicExtensions;
            piSpecificSkillsPresent =
              lib.any (name: lib.hasInfix ".pi/agent/skills" name) (builtins.attrNames homeConfig.home.file)
              || lib.any (script: lib.hasInfix ".pi/agent/skills" script) activationScripts;
          };
          expected = {
            atomicDeclaresPackages = true;
            sharedExtensionSource = true;
            atomicSelectorsArePiPlusExclusions = true;
            piKeepsAtomicExclusions = true;
            piReceivesPiOnlyPackages = true;
            atomicLacksPiOnlyPackages = true;
            everyPiOnlyExtensionExcluded = true;
            noBareBasenameSpelling = true;
            piSpecificSkillsPresent = false;
          };
        };
      };
    };
}

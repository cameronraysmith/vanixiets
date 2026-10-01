# Structural check that crs58's agent configs reach disk through
# managedConfigs and that moshi-hook re-adds its hooks after them.
#
# Falsifiability: dropping "managedConfigs" from moshiHookReconcile's after
# list, removing one of the four managedConfigs entries, or re-enabling the
# home.file entry an upstream module renders for one of those paths each
# changes `actual`.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;
      homeConfig = self.homeConfigurations."crs58@${system}".config;
      home = homeConfig.home.homeDirectory;
      paths = [
        "${home}/.claude/settings.json"
        "${home}/.codex/config.toml"
        "${home}/.config/devin/config.json"
        "${home}/.pi/agent/settings.json"
      ];
      managedTargets = lib.mapAttrsToList (_: entry: entry.target) homeConfig.managedConfigs;
      homeFileTargets = lib.mapAttrsToList (
        _: file: if lib.hasPrefix "/" file.target then file.target else "${home}/${file.target}"
      ) (lib.filterAttrs (_: file: file.enable) homeConfig.home.file);
      report = present: map (lib.removePrefix "${home}/") (lib.filter present paths);
    in
    {
      checks = lib.optionalAttrs (system == "aarch64-darwin") {
        managed-config-wiring = mkCheck {
          name = "managed-config-wiring";
          actual = {
            moshiAfterManagedConfigs = lib.elem "managedConfigs" homeConfig.home.activation.moshiHookReconcile.after;
            managed = report (path: lib.elem path managedTargets);
            alsoHomeFile = report (path: lib.elem path homeFileTargets);
          };
          expected = {
            moshiAfterManagedConfigs = true;
            managed = [
              ".claude/settings.json"
              ".codex/config.toml"
              ".config/devin/config.json"
              ".pi/agent/settings.json"
            ];
            alsoHomeFile = [ ];
          };
        };
      };
    };
}

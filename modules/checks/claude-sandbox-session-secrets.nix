# Holds the claude-sandbox profile to D5's secret path
# (openspec/changes/bootstrap-claude-sandbox): its Linear secrets are declared,
# decrypted only at session start, and only ever onto tmpfs. Evaluation-time
# obligations: the asserts fire when this attribute is evaluated, and the value
# is only a list of the profile's sops targets as a file.
#
# - the four Linear secrets are declared and the credentials template renders
#   ~/.config/linear/credentials.toml, so the remaining obligations are not
#   met vacuously by a profile that declares nothing;
# - no activation entry names the sops-nix install script, so activating the
#   profile, which the setup step does before any snapshot and with no access
#   to SOPS_AGE_KEY (A172), never decrypts (R6);
# - the SessionStart hooks include the session-secrets hook, which does;
# - the age key and the decrypted files live under /dev/shm, and the only
#   sops paths under the home directory are the symlinks sops-nix leaves;
# - no session variable sets LINEAR_API_KEY or LINEAR_WORKSPACE, which the
#   Linear skills refuse to run with.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        claude-sandbox-session-secrets = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        claude-sandbox-session-secrets =
          let
            hm = self.homeConfigurations."claude-sandbox@x86_64-linux".config;
            inherit (hm.sops) secrets templates;
            linearSecrets = [
              "linear-api-key-personal"
              "linear-api-key-work"
              "linear-workspace-personal"
              "linear-workspace-work"
            ];
            missing = lib.filter (name: !(secrets ? ${name})) linearSecrets;
            credentials = templates."linear-credentials.toml".path or null;

            # Compared without string context: matching on a store path is not a
            # dependency on it.
            plain = builtins.unsafeDiscardStringContext;
            installScript = plain hm.launchd.agents.sops-nix.config.Program;
            decrypting = lib.attrNames (
              lib.filterAttrs (
                _: entry:
                let
                  data = plain (entry.data or entry);
                in
                lib.hasInfix installScript data || lib.hasInfix "sops-install-secrets" data
              ) hm.home.activation
            );

            sessionStart = lib.concatMap (group: map (hook: hook.command) group.hooks) (
              hm.programs.claude-code.settings.hooks.SessionStart or [ ]
            );
            secretsHook = "/bin/claude-sandbox-session-secrets";

            onShm = path: lib.hasPrefix "/dev/shm/" path;
            runtimeDir = hm.sops.environment.XDG_RUNTIME_DIR or "";
            # sops-install-secrets expands %r to $XDG_RUNTIME_DIR at install time.
            tmpfsPaths = {
              "sops.age.keyFile" = hm.sops.age.keyFile;
              "sops.defaultSecretsMountPoint" =
                builtins.replaceStrings [ "%r" ] [ runtimeDir ]
                  hm.sops.defaultSecretsMountPoint;
              "sops.environment.XDG_RUNTIME_DIR" = runtimeDir;
            };
            offShm = lib.attrNames (lib.filterAttrs (_: path: !onShm path) tmpfsPaths);

            linearVariables = lib.filter (name: hm.home.sessionVariables ? ${name}) [
              "LINEAR_API_KEY"
              "LINEAR_WORKSPACE"
            ];
          in
          assert lib.assertMsg (
            missing == [ ]
          ) "claude-sandbox must declare the Linear secrets; missing: ${lib.concatStringsSep ", " missing}";
          assert lib.assertMsg (credentials == "${hm.xdg.configHome}/linear/credentials.toml")
            "claude-sandbox must render ${hm.xdg.configHome}/linear/credentials.toml from mkLinearCredentialsTemplate, not ${toString credentials}";
          assert lib.assertMsg (decrypting == [ ])
            "claude-sandbox activation must not decrypt (R6, A172); entries naming the sops install: ${lib.concatStringsSep ", " decrypting}";
          assert lib.assertMsg (lib.any (lib.hasSuffix secretsHook) sessionStart)
            "claude-sandbox SessionStart hooks must include a store-path command ending in ${secretsHook}";
          assert lib.assertMsg (
            offShm == [ ]
          ) "claude-sandbox sops paths must be under /dev/shm; not: ${lib.concatStringsSep ", " offShm}";
          assert lib.assertMsg (linearVariables == [ ])
            "claude-sandbox must not set ${lib.concatStringsSep " or " linearVariables}; the Linear skills refuse to run with them";
          pkgs.writeText "claude-sandbox-session-secrets.txt" (
            lib.concatLines (
              lib.mapAttrsToList (name: path: "${name} = ${path}") (
                tmpfsPaths // { "credentials.toml" = credentials; }
              )
            )
          );
      };
    };
}

{ lib, ... }:
let
  credentialSourceOptions = {
    enable = lib.mkEnableOption "delivery of this explicitly selected static credential";
    generator = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[a-z0-9][a-z0-9-]*");
      default = null;
      description = "Host-local Clan hidden-prompt generator; required when enabled.";
    };
    file = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[a-zA-Z0-9][a-zA-Z0-9_-]*");
      default = null;
      description = "Secret output file in the declared generator; required when enabled.";
    };
  };
  credentialSource = lib.types.submodule { options = credentialSourceOptions; };
  expectedIdentity =
    description:
    lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      inherit description;
    };
  credentialOptions = {
    signingKey = lib.mkOption {
      type = credentialSource;
      default = { };
      description = "Explicitly delegated passwordless SSH private key for Git and Jujutsu signing.";
    };
    githubToken = lib.mkOption {
      type = credentialSource;
      default = { };
      description = "Personal GitHub token consumed only by the worker's gh wrapper.";
    };
    linearApiKeys = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = { inherit (credentialSourceOptions) enable generator; };
        }
      );
      apply =
        entries:
        assert lib.assertMsg (lib.all (
          label:
          lib.elem label [
            "personal"
            "work"
          ]
        ) (lib.attrNames entries)) "Linear credentials must use masked personal/work labels.";
        entries;
      default = { };
      description = "Masked personal/work labels selecting a Clan generator with secret key, workspace, workspace-id and viewer-email files; each entry defaults off.";
    };
    claudeSetupToken = lib.mkOption {
      type = credentialSource;
      default = { };
      description = "Optional native Claude setup token, never an OAuth directory seed.";
    };
    expected = lib.mkOption {
      type = lib.types.submodule {
        options = {
          githubUser = expectedIdentity "Expected authenticated GitHub login; not inferred from the worker owner label.";
          gitEmail = expectedIdentity "Canonical Git author and allowed_signers principal.";
          signingPublicKey = expectedIdentity "Declared OpenSSH public key corresponding to the delegated private key.";
          omnigentEmail = expectedIdentity "Expected authenticated Omnigent /v1/me user_id in the email-based OIDC deployment.";
        };
      };
      default = { };
      description = "Non-secret expected identities for separately invoked enrollment verification.";
    };
  };
  workerOptions =
    { config, ... }:
    let
      osConfig = config;
    in
    {
      options.services.omnigent-host.workers = lib.mkOption {
        default = { };
        description = "Dedicated worker accounts prepared independently of host execution.";
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, config, ... }:
            {
              options = {
                enable = lib.mkEnableOption "foreground execution for this enrolled worker";
                owner = lib.mkOption {
                  type = lib.types.nonEmptyStr;
                  description = "Intended human association; enrollment must verify application ownership separately.";
                };
                user = lib.mkOption {
                  type = lib.types.strMatching "[a-z_][a-z0-9_-]*";
                  description = "Declared non-administrative Unix account; never inferred from a privileged user.";
                };
                hostName = lib.mkOption {
                  type = lib.types.nonEmptyStr;
                  default = "${osConfig.networking.hostName}-${name}";
                  description = "Distinct registration name for this machine and worker.";
                };
                workspaceRoot = lib.mkOption {
                  type = lib.types.strMatching "/.*";
                  default = "${osConfig.users.users.${config.user}.home}/projects";
                  description = "Project directory inside the declared account home.";
                };
                autoApproveDirenv = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Trust direnv files under workspaceRoot without individual approval.";
                };
                credentials = lib.mkOption {
                  type = lib.types.submodule { options = credentialOptions; };
                  default = { };
                  description = "Selected host-delivered static credentials, separate from tool-owned mutable OAuth state.";
                };
                environment = lib.mkOption {
                  type = lib.types.attrsOf lib.types.str;
                  default = { };
                  description = "Non-secret additions; identity, state, PATH and credential selectors are adapter-owned.";
                };
                extraPackages = lib.mkOption {
                  type = lib.types.listOf lib.types.package;
                  default = [ ];
                  description = "Executable providers appended after required runtime packages and the worker profile.";
                };
                extraHomeModules = lib.mkOption {
                  type = lib.types.listOf lib.types.deferredModule;
                  default = [ ];
                  description = "Additional credential-free Home Manager modules; not clan-serializable settings.";
                };
              };
            }
          )
        );
      };
    };
in
{
  flake.lib.omnigentWorkerCredentialOptions = credentialOptions;
  flake.modules.nixos.omnigent-worker-options = workerOptions;
  flake.modules.darwin.omnigent-worker-options = workerOptions;
}

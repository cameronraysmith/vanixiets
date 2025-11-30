{ self, ... }:
{
  perSystem =
    {
      inputs',
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # OpenTofu with required providers
      package = pkgs.opentofu.withPlugins (p: [
        p.hashicorp_external
        p.hashicorp_local
        p.hashicorp_null
        p.hashicorp_tls
        p.hetznercloud_hcloud
        p.hashicorp_google
      ]);
    in
    {
      terranix = {
        terranixConfigurations.terraform = {
          workdir = "terraform";
          modules = [
            self.modules.terranix.base
            self.modules.terranix.hetzner
            self.modules.terranix.gcp
          ];
          terraformWrapper.package = package;
          terraformWrapper.extraRuntimeInputs = [ inputs'.clan-core.packages.default ];
          terraformWrapper.prefixText = ''
            # Fetch passphrase from clan secrets
            TF_VAR_passphrase=$(clan secrets get tf-passphrase)
            export TF_VAR_passphrase

            # Configure OpenTofu state encryption
            TF_ENCRYPTION=$(cat <<'EOF'
            key_provider "pbkdf2" "state_encryption_password" {
              passphrase = var.passphrase
            }
            method "aes_gcm" "encryption_method" {
              keys = key_provider.pbkdf2.state_encryption_password
            }
            state {
              enforced = true
              method = method.aes_gcm.encryption_method
            }
            EOF
            )

            # shellcheck disable=SC2090
            export TF_ENCRYPTION
          '';
        };
      };

      # Override terranix-generated outputs to add metadata
      # terranix doesn't provide options for this, so we override after creation
      packages.terraform = lib.mkForce (
        config.terranix.terranixConfigurations.terraform.result.app.overrideAttrs (old: {
          meta = (old.meta or { }) // {
            description = "OpenTofu with Hetzner Cloud and GCP providers and encrypted state";
          };
        })
      );

      devShells.terraform = lib.mkForce (
        config.terranix.terranixConfigurations.terraform.result.devShell.overrideAttrs (old: {
          passthru = (old.passthru or { }) // {
            meta = (old.passthru.meta or { }) // {
              description = "Terraform/OpenTofu development environment with apply/plan/destroy scripts";
            };
          };
        })
      );
    };
}

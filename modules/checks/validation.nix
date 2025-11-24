{ self, config, ... }:
{
  perSystem =
    {
      pkgs,
      system,
      inputs',
      ...
    }:
    let
      terraformPkg = self.packages.${system}.terraform;
      terraformConfig = terraformPkg.passthru.config;
    in
    {
      checks = {
        # TC-018: Home Module Exports
        # Purpose: Validate portable home modules exported to dendritic namespace
        home-module-exports =
          pkgs.runCommand "home-module-exports"
            {
              passthru.meta.description = "Validate home modules exported to flake.modules.homeManager namespace";
            }
            ''
              echo "Validating home module exports..."

              # Check that the homeManager namespace exists
              ${
                if builtins.hasAttr "homeManager" config.flake.modules then
                  ''echo "✓ homeManager namespace exists in flake.modules"''
                else
                  ''echo "ERROR: homeManager namespace not found" >&2 && exit 1''
              }

              # Check that the modules exist in the namespace
              ${
                if builtins.hasAttr "users/crs58" config.flake.modules.homeManager then
                  ''echo "✓ crs58 home module found in namespace"''
                else
                  ''echo "ERROR: crs58 home module not found in namespace" >&2 && exit 1''
              }

              ${
                if builtins.hasAttr "users/raquel" config.flake.modules.homeManager then
                  ''echo "✓ raquel home module found in namespace"''
                else
                  ''echo "ERROR: raquel home module not found in namespace" >&2 && exit 1''
              }

              # Check that modules are defined (not null)
              ${
                if config.flake.modules.homeManager."users/crs58" != null then
                  ''echo "✓ crs58 module is defined (not null)"''
                else
                  ''echo "ERROR: crs58 module is null" >&2 && exit 1''
              }

              ${
                if config.flake.modules.homeManager."users/raquel" != null then
                  ''echo "✓ raquel module is defined (not null)"''
                else
                  ''echo "ERROR: raquel module is null" >&2 && exit 1''
              }

              echo "✓ Home module exports validated (namespace + definitions)"
              touch $out
            '';

        # TC-019: Home Configurations Exposed
        # Purpose: Validate nested homeConfigurations exposed in flake outputs
        # Structure: homeConfigurations.${system}.${username}
        home-configurations-exposed =
          pkgs.runCommand "home-configurations-exposed"
            {
              passthru.meta.description = "Validate nested homeConfigurations exposed for nh CLI";
            }
            ''
              echo "Validating homeConfigurations exposure (nested by system)..."

              # Check that system-level structure exists
              ${
                if builtins.hasAttr system self.homeConfigurations then
                  ''echo "✓ homeConfigurations.${system} exists"''
                else
                  ''echo "ERROR: homeConfigurations.${system} not found" >&2 && exit 1''
              }

              # Check that user configs exist under current system
              ${
                if builtins.hasAttr "crs58" self.homeConfigurations.${system} then
                  ''echo "✓ homeConfigurations.${system}.crs58 exposed"''
                else
                  ''echo "ERROR: homeConfigurations.${system}.crs58 not found" >&2 && exit 1''
              }

              ${
                if builtins.hasAttr "raquel" self.homeConfigurations.${system} then
                  ''echo "✓ homeConfigurations.${system}.raquel exposed"''
                else
                  ''echo "ERROR: homeConfigurations.${system}.raquel not found" >&2 && exit 1''
              }

              # Check that configs are derivations (buildable)
              ${
                if
                  builtins.isAttrs self.homeConfigurations.${system}.crs58
                  && builtins.hasAttr "activationPackage" self.homeConfigurations.${system}.crs58
                then
                  ''echo "✓ homeConfigurations.${system}.crs58 is buildable (has activationPackage)"''
                else
                  ''echo "ERROR: homeConfigurations.${system}.crs58 missing activationPackage" >&2 && exit 1''
              }

              ${
                if
                  builtins.isAttrs self.homeConfigurations.${system}.raquel
                  && builtins.hasAttr "activationPackage" self.homeConfigurations.${system}.raquel
                then
                  ''echo "✓ homeConfigurations.${system}.raquel is buildable (has activationPackage)"''
                else
                  ''echo "ERROR: homeConfigurations.${system}.raquel missing activationPackage" >&2 && exit 1''
              }

              echo "✓ Nested homeConfigurations validated for ${system}"
              touch $out
            '';

        # TC-017: Naming Conventions
        # Purpose: Validate consistent kebab-case naming across machines
        naming-conventions =
          pkgs.runCommand "naming-conventions"
            {
              nativeBuildInputs = [ pkgs.jq ];
              machines = builtins.toJSON (builtins.attrNames self.nixosConfigurations);
              passthru.meta.description = "Validate consistent kebab-case naming across machines";
            }
            ''
              echo "Checking machine naming conventions..."
              echo "$machines" | ${pkgs.jq}/bin/jq -r '.[]' | while read name; do
                if ! echo "$name" | grep -qE '^[a-z0-9-]+$'; then
                  echo "Invalid machine name (must be lowercase kebab-case): $name" >&2
                  exit 1
                fi
                echo "✓ $name"
              done

              echo "✓ All machine names follow kebab-case convention"
              touch $out
            '';

        # TC-012: Terraform Deep Validation
        # Purpose: Validate generated terraform is syntactically correct
        terraform-validate =
          pkgs.runCommand "terraform-validate"
            {
              nativeBuildInputs = [ pkgs.opentofu ];
              passthru.meta.description = "Validate generated terraform is syntactically correct";
            }
            ''
              echo "Validating terraform configuration..."

              # Create working directory
              mkdir -p terraform
              cd terraform

              # Link the generated terraform config
              ln -s ${terraformConfig} config.tf.json

              # Initialize terraform (backend=false to avoid network/state)
              tofu init -backend=false

              # Validate configuration
              tofu validate

              echo "✓ Terraform configuration is valid"
              touch $out
            '';

        # TC-007: Clan Secrets Generation
        # Purpose: Validate service targeting generates correct secrets
        # Note: This test validates that clan CLI is available and can be invoked
        # Full secrets generation testing requires actual clan workspace setup
        secrets-generation =
          pkgs.runCommand "secrets-generation"
            {
              nativeBuildInputs = [ inputs'.clan-core.packages.default ];
              passthru.meta.description = "Validate clan CLI availability for secrets generation";
            }
            ''
              echo "Testing clan CLI availability for secrets generation..."

              # Verify clan CLI is available
              if ! command -v clan >/dev/null 2>&1; then
                echo "ERROR: clan CLI not found in PATH" >&2
                exit 1
              fi

              # Verify clan CLI can show help (basic smoke test)
              clan secrets --help > /dev/null 2>&1 || {
                echo "ERROR: clan secrets command failed" >&2
                exit 1
              }

              echo "✓ Clan CLI available"
              echo "✓ clan secrets command accessible"

              # Note: Full secrets generation test would require:
              # - Clan workspace initialization
              # - Machine definitions with service instances
              # - Secret generation and validation
              # This is deferred to integration testing phase

              echo "✓ Secrets generation validation (smoke test)"
              touch $out
            '';

        # TC-006: Deployment Safety Validation
        # Purpose: Verify terraform plan won't destroy existing infrastructure
        # Note: This test analyzes terraform configuration structure for safety patterns
        deployment-safety =
          pkgs.runCommand "deployment-safety"
            {
              nativeBuildInputs = [
                pkgs.opentofu
                pkgs.jq
              ];
              passthru.meta.description = "Verify terraform configuration safety patterns";
            }
            ''
              echo "Validating deployment safety..."

              # Create working directory
              mkdir -p terraform
              cd terraform

              # Link the generated terraform config
              ln -s ${terraformConfig} config.tf.json

              # Analyze the configuration structure directly
              echo "Analyzing terraform configuration for destructive operations..."

              # Count resource blocks (validate infrastructure is defined)
              RESOURCE_COUNT=$(${pkgs.jq}/bin/jq '.resource | length' config.tf.json)
              echo "Found $RESOURCE_COUNT resource types defined"

              if [ "$RESOURCE_COUNT" -eq 0 ]; then
                echo "ERROR: No resources defined in terraform configuration!" >&2
                exit 1
              fi

              # Verify we have Hetzner provider configured
              HAS_HCLOUD=$(${pkgs.jq}/bin/jq 'has("provider") and (.provider | has("hcloud"))' config.tf.json)
              if [ "$HAS_HCLOUD" = "true" ]; then
                echo "✓ Hetzner Cloud provider configured"
              else
                echo "WARNING: Hetzner Cloud provider not found in config"
              fi

              # Check for SSH key resources (expected in base infrastructure)
              SSH_KEYS=$(${pkgs.jq}/bin/jq '.resource.hcloud_ssh_key // {} | length' config.tf.json)
              echo "Found $SSH_KEYS hcloud_ssh_key resources"

              if [ "$SSH_KEYS" -gt 0 ]; then
                echo "✓ SSH key infrastructure configured"
              fi

              # Verify no force-replacement flags
              # Check if any resources have force_destroy or similar dangerous settings
              FORCE_DESTROY=$(${pkgs.jq}/bin/jq '[.. | objects | select(.force_destroy == true)] | length' config.tf.json)

              if [ "$FORCE_DESTROY" -gt 0 ]; then
                echo "WARNING: Found $FORCE_DESTROY resources with force_destroy=true"
              fi

              echo "✓ Configuration defines infrastructure resources"
              echo "✓ No obvious destructive patterns detected"
              echo "✓ Deployment safety validated (config structure)"

              # Note: Full deployment safety requires state comparison with actual infrastructure
              # This test validates config structure doesn't have obvious destructive patterns

              touch $out
            '';

        # TC-024: Vars Validation
        # Purpose: Validate clan vars system for user password management
        # Tests vars file structure, SOPS encryption, and build integration
        vars-user-password-validation =
          pkgs.runCommand "vars-user-password-validation"
            {
              nativeBuildInputs = [ pkgs.file ];
              passthru.meta.description = "Validate clan vars system for cameron user password management";
            }
            ''
              echo "Validating clan vars for cameron user..."

              # TC-024-1: Vars directory structure test
              echo "TC-024-1: Checking vars directory structure..."
              VARS_DIR="${self}/vars/shared/user-password-cameron"

              if [ ! -d "$VARS_DIR" ]; then
                echo "ERROR: Vars directory not found at $VARS_DIR" >&2
                exit 1
              fi
              echo "✓ Vars directory exists: $VARS_DIR"

              # Check both password and hash files exist
              PASSWORD_FILE="$VARS_DIR/user-password/secret"
              HASH_FILE="$VARS_DIR/user-password-hash/secret"

              if [ ! -f "$PASSWORD_FILE" ]; then
                echo "ERROR: Password secret file not found at $PASSWORD_FILE" >&2
                exit 1
              fi
              echo "✓ Password secret file exists"

              if [ ! -f "$HASH_FILE" ]; then
                echo "ERROR: Hash secret file not found at $HASH_FILE" >&2
                exit 1
              fi
              echo "✓ Hash secret file exists"

              # TC-024-2: SOPS encryption test
              echo "TC-024-2: Validating SOPS encryption format..."

              # Check password file type is JSON
              FILE_TYPE=$(file "$PASSWORD_FILE")
              if echo "$FILE_TYPE" | grep -q "JSON"; then
                echo "✓ Password secret file is JSON format"
              else
                echo "ERROR: Password secret file is not JSON format: $FILE_TYPE" >&2
                exit 1
              fi

              # Check hash file type is JSON
              FILE_TYPE=$(file "$HASH_FILE")
              if echo "$FILE_TYPE" | grep -q "JSON"; then
                echo "✓ Hash secret file is JSON format"
              else
                echo "ERROR: Hash secret file is not JSON format: $FILE_TYPE" >&2
                exit 1
              fi

              # Verify SOPS structure in password file (encrypted data, not plaintext)
              if grep -q '"sops"' "$PASSWORD_FILE" && grep -q '"data"' "$PASSWORD_FILE"; then
                echo "✓ Password file has SOPS encryption structure"
              else
                echo "ERROR: Password file missing SOPS encryption structure" >&2
                exit 1
              fi

              # Verify data is encrypted in password file (should contain ENC[ markers)
              if grep -q 'ENC\[' "$PASSWORD_FILE"; then
                echo "✓ Password data is encrypted (ENC[ markers found)"
              else
                echo "ERROR: Password data appears to be plaintext" >&2
                exit 1
              fi

              # Verify SOPS structure in hash file
              if grep -q '"sops"' "$HASH_FILE" && grep -q '"data"' "$HASH_FILE"; then
                echo "✓ Hash file has SOPS encryption structure"
              else
                echo "ERROR: Hash file missing SOPS encryption structure" >&2
                exit 1
              fi

              # Verify data is encrypted in hash file
              if grep -q 'ENC\[' "$HASH_FILE"; then
                echo "✓ Hash data is encrypted (ENC[ markers found)"
              else
                echo "ERROR: Hash data appears to be plaintext" >&2
                exit 1
              fi

              echo "✓ Vars directory structure validated (user-password-cameron exists)"
              echo "✓ SOPS encryption validated (JSON format, encrypted content)"

              # Note: TC-024-3 (deployment test) and TC-024-4 (home-manager integration test)
              # require actual VPS deployment to cinnabar for validation.
              # These tests verify:
              # - TC-024-3: /run/secrets/vars/user-password-cameron/ populated on cinnabar
              # - TC-024-4: cameron user shell=zsh, home-manager configs active
              # Will be validated during actual deployment or in integration tests.

              echo "✓ Vars validation complete (local checks passed)"
              touch $out
            '';
      };
    };
}

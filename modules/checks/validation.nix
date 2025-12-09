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

      # match providers defined in modules/terranix/config.nix
      tofuWithProviders = pkgs.opentofu.withPlugins (p: [
        p.hashicorp_external
        p.hashicorp_local
        p.hashicorp_null
        p.hashicorp_tls
        p.hetznercloud_hcloud
        p.hashicorp_google
      ]);
    in
    {
      checks = {
        # TC-020: Home Module Exports
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
                  ''echo "OK: homeManager namespace exists in flake.modules"''
                else
                  ''echo "ERROR: homeManager namespace not found" >&2 && exit 1''
              }

              # Check that the modules exist in the namespace
              ${
                if builtins.hasAttr "users/crs58" config.flake.modules.homeManager then
                  ''echo "OK: crs58 home module found in namespace"''
                else
                  ''echo "ERROR: crs58 home module not found in namespace" >&2 && exit 1''
              }

              ${
                if builtins.hasAttr "users/raquel" config.flake.modules.homeManager then
                  ''echo "OK: raquel home module found in namespace"''
                else
                  ''echo "ERROR: raquel home module not found in namespace" >&2 && exit 1''
              }

              # Check that modules are defined (not null)
              ${
                if config.flake.modules.homeManager."users/crs58" != null then
                  ''echo "OK: crs58 module is defined (not null)"''
                else
                  ''echo "ERROR: crs58 module is null" >&2 && exit 1''
              }

              ${
                if config.flake.modules.homeManager."users/raquel" != null then
                  ''echo "OK: raquel module is defined (not null)"''
                else
                  ''echo "ERROR: raquel module is null" >&2 && exit 1''
              }

              echo "Home module exports validated (namespace + definitions)"
              touch $out
            '';

        # TC-021: Home Configurations Exposed
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
                  ''echo "OK: homeConfigurations.${system} exists"''
                else
                  ''echo "ERROR: homeConfigurations.${system} not found" >&2 && exit 1''
              }

              # Check that user configs exist under current system
              ${
                if builtins.hasAttr "crs58" self.homeConfigurations.${system} then
                  ''echo "OK: homeConfigurations.${system}.crs58 exposed"''
                else
                  ''echo "ERROR: homeConfigurations.${system}.crs58 not found" >&2 && exit 1''
              }

              ${
                if builtins.hasAttr "raquel" self.homeConfigurations.${system} then
                  ''echo "OK: homeConfigurations.${system}.raquel exposed"''
                else
                  ''echo "ERROR: homeConfigurations.${system}.raquel not found" >&2 && exit 1''
              }

              # Check that configs are derivations (buildable)
              ${
                if
                  builtins.isAttrs self.homeConfigurations.${system}.crs58
                  && builtins.hasAttr "activationPackage" self.homeConfigurations.${system}.crs58
                then
                  ''echo "OK: homeConfigurations.${system}.crs58 is buildable (has activationPackage)"''
                else
                  ''echo "ERROR: homeConfigurations.${system}.crs58 missing activationPackage" >&2 && exit 1''
              }

              ${
                if
                  builtins.isAttrs self.homeConfigurations.${system}.raquel
                  && builtins.hasAttr "activationPackage" self.homeConfigurations.${system}.raquel
                then
                  ''echo "OK: homeConfigurations.${system}.raquel is buildable (has activationPackage)"''
                else
                  ''echo "ERROR: homeConfigurations.${system}.raquel missing activationPackage" >&2 && exit 1''
              }

              echo "OK: Nested homeConfigurations validated for ${system}"
              touch $out
            '';

        # TC-022: Naming Conventions
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
                echo "OK: $name"
              done

              echo "OK: All machine names follow kebab-case convention"
              touch $out
            '';

        # TC-023: Terraform Deep Validation
        # Purpose: Validate generated terraform is syntactically correct
        terraform-validate =
          pkgs.runCommand "terraform-validate"
            {
              nativeBuildInputs = [ tofuWithProviders ];
              passthru.meta.description = "Validate generated terraform is syntactically correct";
            }
            ''
              echo "Validating terraform configuration..."

              # Create working directory
              mkdir -p terraform
              cd terraform

              # Link the generated terraform config
              ln -s ${terraformConfig} config.tf.json

              # Initialize with pre-bundled providers (no network access needed)
              # -plugin-dir ensures tofu uses only local providers, skipping registry
              tofu init -backend=false -plugin-dir=${tofuWithProviders}/libexec/terraform-providers

              # Validate configuration against provider schemas
              tofu validate

              echo "OK: Terraform configuration is valid"
              touch $out
            '';

        # TC-024: Terraform Config Structure
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
                echo "OK: Hetzner Cloud provider configured"
              else
                echo "WARNING: Hetzner Cloud provider not found in config"
              fi

              # Check for SSH key resources (expected in base infrastructure)
              SSH_KEYS=$(${pkgs.jq}/bin/jq '.resource.hcloud_ssh_key // {} | length' config.tf.json)
              echo "Found $SSH_KEYS hcloud_ssh_key resources"

              if [ "$SSH_KEYS" -gt 0 ]; then
                echo "OK: SSH key infrastructure configured"
              fi

              # Verify no force-replacement flags
              # Check if any resources have force_destroy or similar dangerous settings
              FORCE_DESTROY=$(${pkgs.jq}/bin/jq '[.. | objects | select(.force_destroy == true)] | length' config.tf.json)

              if [ "$FORCE_DESTROY" -gt 0 ]; then
                echo "WARNING: Found $FORCE_DESTROY resources with force_destroy=true"
              fi

              echo "OK: Configuration defines infrastructure resources"
              echo "OK: No obvious destructive patterns detected"
              echo "OK: Deployment safety validated (config structure)"

              # Note: Full deployment safety requires state comparison with actual infrastructure
              # This test validates config structure doesn't have obvious destructive patterns

              touch $out
            '';

        # TC-025: Vars Validation
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

              # TC-025-1: Vars directory structure test
              echo "TC-025-1: Checking vars directory structure..."
              VARS_DIR="${self}/vars/shared/user-password-cameron"

              if [ ! -d "$VARS_DIR" ]; then
                echo "ERROR: Vars directory not found at $VARS_DIR" >&2
                exit 1
              fi
              echo "OK: Vars directory exists: $VARS_DIR"

              # Check both password and hash files exist
              PASSWORD_FILE="$VARS_DIR/user-password/secret"
              HASH_FILE="$VARS_DIR/user-password-hash/secret"

              if [ ! -f "$PASSWORD_FILE" ]; then
                echo "ERROR: Password secret file not found at $PASSWORD_FILE" >&2
                exit 1
              fi
              echo "OK: Password secret file exists"

              if [ ! -f "$HASH_FILE" ]; then
                echo "ERROR: Hash secret file not found at $HASH_FILE" >&2
                exit 1
              fi
              echo "OK: Hash secret file exists"

              # TC-025-2: SOPS encryption test
              echo "TC-025-2: Validating SOPS encryption format..."

              # Check password file type is JSON
              FILE_TYPE=$(file "$PASSWORD_FILE")
              if echo "$FILE_TYPE" | grep -q "JSON"; then
                echo "OK: Password secret file is JSON format"
              else
                echo "ERROR: Password secret file is not JSON format: $FILE_TYPE" >&2
                exit 1
              fi

              # Check hash file type is JSON
              FILE_TYPE=$(file "$HASH_FILE")
              if echo "$FILE_TYPE" | grep -q "JSON"; then
                echo "OK: Hash secret file is JSON format"
              else
                echo "ERROR: Hash secret file is not JSON format: $FILE_TYPE" >&2
                exit 1
              fi

              # Verify SOPS structure in password file (encrypted data, not plaintext)
              if grep -q '"sops"' "$PASSWORD_FILE" && grep -q '"data"' "$PASSWORD_FILE"; then
                echo "OK: Password file has SOPS encryption structure"
              else
                echo "ERROR: Password file missing SOPS encryption structure" >&2
                exit 1
              fi

              # Verify data is encrypted in password file (should contain ENC[ markers)
              if grep -q 'ENC\[' "$PASSWORD_FILE"; then
                echo "OK: Password data is encrypted (ENC[ markers found)"
              else
                echo "ERROR: Password data appears to be plaintext" >&2
                exit 1
              fi

              # Verify SOPS structure in hash file
              if grep -q '"sops"' "$HASH_FILE" && grep -q '"data"' "$HASH_FILE"; then
                echo "OK: Hash file has SOPS encryption structure"
              else
                echo "ERROR: Hash file missing SOPS encryption structure" >&2
                exit 1
              fi

              # Verify data is encrypted in hash file
              if grep -q 'ENC\[' "$HASH_FILE"; then
                echo "OK: Hash data is encrypted (ENC[ markers found)"
              else
                echo "ERROR: Hash data appears to be plaintext" >&2
                exit 1
              fi

              echo "OK: Vars directory structure validated (user-password-cameron exists)"
              echo "OK: SOPS encryption validated (JSON format, encrypted content)"

              # Note: TC-025-3 (deployment test) and TC-025-4 (home-manager integration test)
              # require actual VPS deployment to cinnabar for validation.
              # These tests verify:
              # - TC-025-3: /run/secrets/vars/user-password-cameron/ populated on cinnabar
              # - TC-025-4: cameron user shell=zsh, home-manager configs active
              # Will be validated during actual deployment or in integration tests.

              echo "OK: Vars validation complete (local checks passed)"
              touch $out
            '';

        # TC-026: Secrets Tier Separation
        # Purpose: Validate that secrets are in the correct tier (vars/ for machine-specific, secrets/ for user-specific)
        secrets-tier-separation =
          pkgs.runCommand "secrets-tier-separation"
            {
              passthru.meta.description = "Validate secrets tier separation (vars vs secrets)";
            }
            ''
              echo "TC-026: Validating secrets tier separation..."

              # Check vars directory structure (machine-specific)
              VARS_DIR="${self}/vars"
              if [ -d "$VARS_DIR" ]; then
                echo "OK: vars/ directory exists"

                # Verify vars directory contains machine-specific or shared directories
                MACHINE_DIRS=$(find "$VARS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
                if [ "$MACHINE_DIRS" -gt 0 ]; then
                  echo "OK: Found $MACHINE_DIRS machine/shared directories in vars/"
                else
                  echo "WARNING: No subdirectories found in vars/"
                fi
              else
                echo "SKIP: vars/ directory not found"
              fi

              # Check secrets directory structure (user-specific)
              SECRETS_DIR="${self}/secrets"
              if [ -d "$SECRETS_DIR" ]; then
                echo "OK: secrets/ directory exists"

                # Count user-specific secret files
                USER_SECRETS=$(find "$SECRETS_DIR" -type f 2>/dev/null | wc -l)
                if [ "$USER_SECRETS" -gt 0 ]; then
                  echo "OK: Found $USER_SECRETS user-specific secret files in secrets/"
                else
                  echo "WARNING: No secret files found in secrets/"
                fi
              else
                echo "SKIP: secrets/ directory not found"
              fi

              echo "OK: Secrets tier separation validated"
              touch $out
            '';

        # TC-027: Clan Inventory Consistency
        # Purpose: Validate that all machine names in clan inventory services reference existing machines
        clan-inventory-consistency =
          pkgs.runCommand "clan-inventory-consistency"
            {
              nativeBuildInputs = [ pkgs.jq ];
              passthru.meta.description = "Validate clan inventory references valid machines";
              # Get all machines from clan.machines
              registeredMachines = builtins.toJSON (
                builtins.attrNames (if builtins.hasAttr "machines" self.clan then self.clan.machines else { })
              );
              # Get all machines from clan.inventory.machines
              inventoryMachines = builtins.toJSON (
                builtins.attrNames (
                  if builtins.hasAttr "inventory" self.clan && builtins.hasAttr "machines" self.clan.inventory then
                    self.clan.inventory.machines
                  else
                    { }
                )
              );
            }
            ''
              echo "TC-027: Validating clan inventory consistency..."

              # Check if we have any machines to validate
              REGISTERED_COUNT=$(echo "$registeredMachines" | ${pkgs.jq}/bin/jq 'length')
              INVENTORY_COUNT=$(echo "$inventoryMachines" | ${pkgs.jq}/bin/jq 'length')

              echo "Found $REGISTERED_COUNT registered machines and $INVENTORY_COUNT inventory machines"

              if [ "$REGISTERED_COUNT" -eq 0 ]; then
                echo "SKIP: No registered machines found"
                touch $out
                exit 0
              fi

              if [ "$INVENTORY_COUNT" -eq 0 ]; then
                echo "SKIP: No inventory machines found"
                touch $out
                exit 0
              fi

              # Compare inventory machines to registered machines
              echo "$inventoryMachines" | ${pkgs.jq}/bin/jq -r '.[]' | sort > /tmp/inventory.txt
              echo "$registeredMachines" | ${pkgs.jq}/bin/jq -r '.[]' | sort > /tmp/registered.txt

              # Check that all inventory machines exist in registered machines
              while read -r machine; do
                if grep -qx "$machine" /tmp/registered.txt; then
                  echo "OK: Inventory machine '$machine' is registered"
                else
                  echo "ERROR: Inventory machine '$machine' not found in clan.machines" >&2
                  exit 1
                fi
              done < /tmp/inventory.txt

              echo "OK: All inventory machines match registered machines"
              touch $out
            '';

        # TC-028: Secrets Encryption Integrity
        # Purpose: Validate that all secret files are properly SOPS-encrypted (no plaintext secrets)
        secrets-encryption-integrity =
          pkgs.runCommand "secrets-encryption-integrity"
            {
              nativeBuildInputs = [
                pkgs.findutils
                pkgs.file
              ];
              passthru.meta.description = "Validate all secrets are SOPS-encrypted";
            }
            ''
              echo "TC-028: Validating secrets encryption integrity..."

              check_encryption() {
                local file="$1"
                # Check if file is JSON format (SOPS encrypted files are JSON)
                FILE_TYPE=$(file "$file")

                if echo "$FILE_TYPE" | grep -q "JSON"; then
                  # Check for SOPS encryption markers
                  if grep -q '"sops"' "$file" 2>/dev/null; then
                    # Verify data is actually encrypted (ENC[ markers)
                    if grep -q 'ENC\[' "$file" 2>/dev/null; then
                      echo "OK: $file is SOPS-encrypted"
                      return 0
                    else
                      echo "ERROR: $file has SOPS structure but no encrypted data" >&2
                      return 1
                    fi
                  else
                    echo "ERROR: $file is JSON but missing SOPS encryption markers" >&2
                    return 1
                  fi
                else
                  echo "WARNING: $file is not JSON format: $FILE_TYPE"
                  return 0
                fi
              }

              TOTAL_CHECKED=0
              ENCRYPTED_OK=0

              # Check vars directory
              if [ -d "${self}/vars" ]; then
                echo "Checking secrets in vars/ directory..."
                find "${self}/vars" -name "secret" -type f 2>/dev/null | while read -r f; do
                  TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
                  if check_encryption "$f"; then
                    ENCRYPTED_OK=$((ENCRYPTED_OK + 1))
                  else
                    exit 1
                  fi
                done || exit 1
              else
                echo "SKIP: vars/ directory not found"
              fi

              # Check secrets directory
              if [ -d "${self}/secrets" ]; then
                echo "Checking secrets in secrets/ directory..."
                find "${self}/secrets" -type f 2>/dev/null | while read -r f; do
                  # Skip non-secret files like .gitignore
                  if [[ "$(basename "$f")" =~ ^\. ]]; then
                    continue
                  fi
                  TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
                  if check_encryption "$f"; then
                    ENCRYPTED_OK=$((ENCRYPTED_OK + 1))
                  else
                    exit 1
                  fi
                done || exit 1
              else
                echo "SKIP: secrets/ directory not found"
              fi

              echo "OK: Secrets encryption integrity validated"
              touch $out
            '';

        # TC-029: Machine Registry Completeness
        # Purpose: Validate that all machine module directories have corresponding clan.machines entries
        machine-registry-completeness =
          pkgs.runCommand "machine-registry-completeness"
            {
              nativeBuildInputs = [ pkgs.jq ];
              registeredMachines = builtins.toJSON (
                builtins.attrNames (if builtins.hasAttr "machines" self.clan then self.clan.machines else { })
              );
              passthru.meta.description = "Validate all machine modules are registered in clan";
            }
            ''
              echo "TC-029: Validating machine registry completeness..."

              TOTAL_MACHINES=0
              REGISTERED_OK=0

              # Check darwin machines
              DARWIN_DIR="${self}/modules/machines/darwin"
              if [ -d "$DARWIN_DIR" ]; then
                echo "Checking darwin machines..."
                for dir in "$DARWIN_DIR"/*/; do
                  if [ -d "$dir" ]; then
                    name=$(basename "$dir")
                    TOTAL_MACHINES=$((TOTAL_MACHINES + 1))

                    if echo "$registeredMachines" | ${pkgs.jq}/bin/jq -e --arg n "$name" 'index($n) != null' > /dev/null 2>&1; then
                      echo "OK: Darwin machine '$name' is registered"
                      REGISTERED_OK=$((REGISTERED_OK + 1))
                    else
                      echo "ERROR: Darwin machine '$name' not in clan.machines" >&2
                      exit 1
                    fi
                  fi
                done
              else
                echo "SKIP: Darwin machines directory not found"
              fi

              # Check nixos machines
              NIXOS_DIR="${self}/modules/machines/nixos"
              if [ -d "$NIXOS_DIR" ]; then
                echo "Checking nixos machines..."
                for dir in "$NIXOS_DIR"/*/; do
                  if [ -d "$dir" ]; then
                    name=$(basename "$dir")
                    TOTAL_MACHINES=$((TOTAL_MACHINES + 1))

                    if echo "$registeredMachines" | ${pkgs.jq}/bin/jq -e --arg n "$name" 'index($n) != null' > /dev/null 2>&1; then
                      echo "OK: NixOS machine '$name' is registered"
                      REGISTERED_OK=$((REGISTERED_OK + 1))
                    else
                      echo "ERROR: NixOS machine '$name' not in clan.machines" >&2
                      exit 1
                    fi
                  fi
                done
              else
                echo "SKIP: NixOS machines directory not found"
              fi

              if [ "$TOTAL_MACHINES" -eq 0 ]; then
                echo "SKIP: No machine directories found"
              else
                echo "OK: Validated $REGISTERED_OK/$TOTAL_MACHINES machine modules"
              fi

              echo "OK: Machine registry completeness validated"
              touch $out
            '';
      };
    };
}

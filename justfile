# This is a jusfile for the nix-config.
# Sections are separated by ## and recipes are documented with a single #
# on lines preceding the recipe.

## nix
## secrets
## CI/CD

# Default command when 'just' is run without arguments
# Run 'just <command>' to execute a command.
default: help

# Display help
help:
  @printf "\nRun 'just -n <command>' to print what would be executed...\n\n"
  @just --list --unsorted
  @printf "\n...by running 'just <command>'.\n"
  @printf "This message is printed by 'just help' and just 'just'.\n"

## nix

# Activate the appropriate configuration for current user and host
[group('nix')]
activate target="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{target}}" ]; then
        echo "activating {{target}} ..."
        nix run . {{target}} --accept-flake-config
    elif [ -f ./configurations/home/$USER@$(hostname).nix ]; then
        echo "activating home configuration $USER@$(hostname) ..."
        nix run . $USER@$(hostname) --accept-flake-config
    else
        echo "activating system configuration $(hostname) ..."
        nix run . $(hostname) --accept-flake-config
    fi

# Print nix flake inputs and outputs
[group('nix')]
io:
  nix flake metadata
  nix flake show --legacy --all-systems
  om show .

# Lint nix files
[group('nix')]
lint:
  pre-commit run --all-files

# Manually enter dev shell
[group('nix')]
dev:
  nix develop

# Remove build output link (no garbage collection)
[group('nix')]
clean:
  rm -f ./result

# Build nix flake
[group('nix')]
build profile: lint check
  nix build --json --no-link --print-build-logs ".#{{ profile }}"

# Check nix flake
[group('nix')]
check:
  nix flake check

# Run nix flake to execute `nix run .#activate` for the current host.
[group('nix')]
switch:
  nix run

# Run nix flake to execute `nix run .#activate-home` for the current user.
[group('nix')]
switch-home:
  nix run .#activate-home

# https://discourse.nixos.org/t/sudo-run-current-system-sw-bin-sudo-must-be-owned-by-uid-0-and-have-the-setuid-bit-set-and-cannot-chdir-var-cron-bailing-out-var-cron-permission-denied/20463
# sudo: /run/current-system/sw/bin/sudo must be owned by uid 0 and have the setuid bit set
# Run nix flake with explicit use of the sudo in `/run/wrappers`
[group('nix')]
switch-wrapper:
  /run/wrappers/bin/sudo nix run

# Shell with bootstrap dependencies
[group('nix')]
bootstrap-shell:
  nix \
  --extra-experimental-features "nix-command flakes" \
  shell \
  "nixpkgs#git" \
  "nixpkgs#just"

# nix run home-manager -- build --flake ".#{{ profile }}"
# Bootstrap build home-manager with flake
[group('nix-home-manager')]
home-manager-bootstrap-build profile="aarch64-linux":
  nix \
  --extra-experimental-features "nix-command flakes" \
  run home-manager -- build \
  --extra-experimental-features "nix-command flakes" \
  --flake ".#{{ profile }}" \
  --show-trace \
  --print-build-logs

# nix run home-manager -- switch --flake ".#{{ profile }}"
# Bootstrap switch home-manager with flake
[group('nix-home-manager')]
home-manager-bootstrap-switch profile="aarch64-linux":
  nix \
  --extra-experimental-features "nix-command flakes" \
  run home-manager -- switch \
  --extra-experimental-features "nix-command flakes" \
  --flake ".#{{ profile }}" \
  --show-trace \
  --print-build-logs

# Build home-manager with flake
[group('nix-home-manager')]
home-manager-build profile="aarch64-linux":
  home-manager build --flake ".#{{ profile }}"

# Switch home-manager with flake
[group('nix-home-manager')]
home-manager-switch profile="aarch64-linux":
  home-manager switch --flake ".#{{ profile }}"

# Bootstrap nix-darwin with flake
[group('nix-darwin')]
darwin-bootstrap profile="aarch64":
  nix run nix-darwin -- switch --flake ".#{{ profile }}"

# Build darwin from flake
[group('nix-darwin')]
darwin-build profile="aarch64":
  just build "darwinConfigurations.{{ profile }}.config.system.build.toplevel"

# Switch darwin from flake
[group('nix-darwin')]
darwin-switch profile="aarch64":
  darwin-rebuild switch --flake ".#{{ profile }}"

# Test darwin from flake
[group('nix-darwin')]
darwin-test profile="aarch64":
  darwin-rebuild check --flake ".#{{ profile }}"

# Bootstrap nixos
[group('nixos')]
nixos-bootstrap destination username publickey:
  ssh \
  -o PubkeyAuthentication=no \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  {{destination}} " \
      parted /dev/nvme0n1 -- mklabel gpt; \
      parted /dev/nvme0n1 -- mkpart primary 512MiB -8GiB; \
      parted /dev/nvme0n1 -- mkpart primary linux-swap -8GiB 100\%; \
      parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 512MiB; \
      parted /dev/nvme0n1 -- set 3 esp on; \
      sleep 1; \
      mkfs.ext4 -L nixos /dev/nvme0n1p1; \
      mkswap -L swap /dev/nvme0n1p2; \
      mkfs.fat -F 32 -n boot /dev/nvme0n1p3; \
      sleep 1; \
      mount /dev/disk/by-label/nixos /mnt; \
      mkdir -p /mnt/boot; \
      mount /dev/disk/by-label/boot /mnt/boot; \
      nixos-generate-config --root /mnt; \
      sed --in-place '/system\.stateVersion = .*/a \
          nix.extraOptions = \"experimental-features = nix-command flakes\";\n \
          security.sudo.enable = true;\n \
          security.sudo.wheelNeedsPassword = false;\n \
          services.openssh.enable = true;\n \
          services.openssh.settings.PasswordAuthentication = false;\n \
          services.openssh.settings.PermitRootLogin = \"no\";\n \
          users.mutableUsers = false;\n \
          users.users.{{username}}.extraGroups = [ \"wheel\" ];\n \
          users.users.{{username}}.initialPassword = \"{{username}}\";\n \
          users.users.{{username}}.home = \"/home/{{username}}\";\n \
          users.users.{{username}}.isNormalUser = true;\n \
          users.users.{{username}}.openssh.authorizedKeys.keys = [ \"{{publickey}}\" ];\n \
      ' /mnt/etc/nixos/configuration.nix; \
      nixos-install --no-root-passwd; \
      reboot;"

# Copy flake to VM
[group('nixos')]
nixos-vm-sync user destination:
  rsync -avz \
  --exclude='.direnv' \
  --exclude='result' \
  . \
  {{ user }}@{{ destination }}:~/nix-config

# Build nixos from flake
[group('nixos')]
nixos-build profile="aarch64":
  just build "nixosConfigurations.{{ profile }}.config.system.build.toplevel"

# Test nixos from flake
[group('nixos')]
nixos-test profile="aarch64":
  nixos-rebuild test --flake ".#{{ profile }}"

# Switch nixos from flake
[group('nixos')]
nixos-switch profile="aarch64":
  nixos-rebuild switch --flake ".#{{ profile }}"

# Update nix flake
[group('nix')]
update:
  nix flake update

# Update primary nix flake inputs (see flake.nix)
[group('nix')]
update-primary-inputs:
  nix run .#update

# Update a package using its updateScript
[group('nix')]
update-package package="claude-code-bin":
  #!/usr/bin/env bash
  set -euo pipefail
  UPDATE_SCRIPT=$(nix build .#{{ package }}.updateScript --no-link --print-out-paths)
  echo "Running updateScript for {{ package }}..."
  $UPDATE_SCRIPT
  echo "Update complete. Review changes with: git diff packages/{{ package }}/manifest.json"

## containers

# Architecture auto-detection: map host arch to target Linux arch
_current_arch := arch()
_native_linux_arch := if _current_arch == "aarch64" { "aarch64-linux" } else { "x86_64-linux" }

# Build a container image for the specified architecture (auto-detects native by default)
[group('containers')]
build-container container arch=_native_linux_arch:
  nix build '.#packages.{{arch}}.{{container}}'

# Build container for both aarch64-linux and x86_64-linux
[group('containers')]
build-multiarch container:
  @echo "Building aarch64-linux..."
  nix build '.#packages.aarch64-linux.{{container}}' -o result-aarch64-linux
  @echo "Building x86_64-linux..."
  nix build '.#packages.x86_64-linux.{{container}}' -o result-x86_64-linux
  @echo "✓ Both architectures built successfully"

# Load the container image from result into docker
[group('containers')]
load-container:
  docker load < result

# Load the native architecture from a multi-arch build
[group('containers')]
load-native:
  docker load < result-{{_native_linux_arch}}

# Test a container by running the binary with --help
[group('containers')]
test-container binary:
  docker run --rm {{binary}}:latest --help

# Complete workflow: build, load, and test a container (single-arch)
[group('containers')]
container-all container binary arch=_native_linux_arch:
  just build-container {{container}} {{arch}}
  just load-container
  just test-container {{binary}}

# Complete workflow: build both architectures, load native, and test
[group('containers')]
container-all-multiarch container binary:
  just build-multiarch {{container}}
  just load-native
  just test-container {{binary}}

## secrets

# Define the project variable
gcp_project_id := env_var_or_default('GCP_PROJECT_ID', 'development')

# Show existing secrets using sops
[group('secrets')]
show:
  @echo "=== Shared secrets (secrets/shared.yaml) ==="
  @sops -d secrets/shared.yaml
  @echo
  @echo "=== Test secrets (secrets/test.yaml) ==="
  @sops -d secrets/test.yaml

# Create a secret with the given name
[group('secrets')]
create-secret name:
  @gcloud secrets create {{name}} --replication-policy="automatic" --project {{gcp_project_id}}

# Populate a single secret with the contents of a dotenv-formatted file
[group('secrets')]
populate-single-secret name path:
  @gcloud secrets versions add {{name}} --data-file={{path}} --project {{gcp_project_id}}

# Populate each line of a dotenv-formatted file as a separate secret
[group('secrets')]
populate-separate-secrets path:
  @while IFS= read -r line; do \
     KEY=$(echo $line | cut -d '=' -f 1); \
     VALUE=$(echo $line | cut -d '=' -f 2); \
     gcloud secrets create $KEY --replication-policy="automatic" --project {{gcp_project_id}} 2>/dev/null; \
     printf "$VALUE" | gcloud secrets versions add $KEY --data-file=- --project {{gcp_project_id}}; \
   done < {{path}}

# Complete process: Create a secret and populate it with the entire contents of a dotenv file
[group('secrets')]
create-and-populate-single-secret name path:
  @just create-secret {{name}}
  @just populate-single-secret {{name}} {{path}}

# Complete process: Create and populate separate secrets for each line in the dotenv file
[group('secrets')]
create-and-populate-separate-secrets path:
  @just populate-separate-secrets {{path}}

# Retrieve the contents of a given secret
[group('secrets')]
get-secret name:
  @gcloud secrets versions access latest --secret={{name}} --project={{gcp_project_id}}

# Create empty dotenv from template
[group('secrets')]
seed-dotenv:
  @cp .template.env .env

# Export unique secrets to dotenv format using sops
[group('secrets')]
export:
  @echo "# Exported from sops secrets" > .secrets.env
  @sops exec-env secrets/shared.yaml 'env | grep -E "CACHIX_AUTH_TOKEN|GITHUB_TOKEN"' >> .secrets.env
  @sort -u .secrets.env -o .secrets.env

# Check secrets are available in sops environment.
[group('secrets')]
check-secrets:
  @printf "Check sops environment for secrets\n\n"
  @sops exec-env secrets/shared.yaml 'env | grep -E "GITHUB|CACHIX" | sed "s/=.*$/=***REDACTED***/"'

# Save KUBECONFIG to file (using sops - requires KUBECONFIG secret to be added)
[group('secrets')]
get-kubeconfig:
  @sops exec-env secrets/shared.yaml 'echo "$KUBECONFIG"' > kubeconfig.yaml || echo "KUBECONFIG not found in secrets/shared.yaml"

# Hash-encrypt a file: copy to secrets directory with content-based name and encrypt with sops
[group('secrets')]
hash-encrypt source_file user="crs58":
  #!/usr/bin/env bash
  set -euo pipefail

  # Generate content-based hash for filename
  HASH=$(nix hash file --type sha256 --base64 "{{source_file}}" | cut -d'-' -f2 | head -c 32)

  # Extract base filename without extension
  BASE_NAME=$(basename "{{source_file}}" .yaml)
  BASE_NAME=$(basename "$BASE_NAME" .yml)

  # Create target path
  TARGET_DIR="secrets/users/{{user}}"
  TARGET_FILE="${TARGET_DIR}/${HASH}-${BASE_NAME}.yaml"

  # Ensure target directory exists
  mkdir -p "$TARGET_DIR"

  # Copy file with hash-based name
  cp "{{source_file}}" "$TARGET_FILE"
  echo "Copied {{source_file}} → $TARGET_FILE"

  # Encrypt in place with sops
  sops encrypt --in-place "$TARGET_FILE"
  echo "Encrypted $TARGET_FILE with sops"

  # Display verification info
  echo "Hash: $HASH"
  echo "Final path: $TARGET_FILE"

# Verify hash integrity: decrypt secret file and compare hash with original file
[group('secrets')]
verify-hash original_file secret_file:
  #!/usr/bin/env bash
  set -euo pipefail

  # Extract hash from secret filename
  SECRET_BASENAME=$(basename "{{secret_file}}")
  EXPECTED_HASH=$(echo "$SECRET_BASENAME" | cut -d'-' -f1)

  # Generate hash of original file
  ACTUAL_HASH=$(nix hash file --type sha256 --base64 "{{original_file}}" | cut -d'-' -f2 | head -c 32)

  # Create temporary file for decrypted content
  TEMP_FILE=$(mktemp)
  trap "rm -f $TEMP_FILE" EXIT

  # Decrypt secret file to temp location
  sops decrypt "{{secret_file}}" > "$TEMP_FILE"

  # Generate hash of decrypted content
  DECRYPTED_HASH=$(nix hash file --type sha256 --base64 "$TEMP_FILE" | cut -d'-' -f2 | head -c 32)

  echo "Original file: {{original_file}}"
  echo "Secret file: {{secret_file}}"
  echo "Expected hash (from filename): $EXPECTED_HASH"
  echo "Actual hash (from original): $ACTUAL_HASH"
  echo "Decrypted hash: $DECRYPTED_HASH"
  echo

  # Verify original matches filename hash
  if [ "$ACTUAL_HASH" = "$EXPECTED_HASH" ]; then
    echo "Original file hash matches secret filename hash"
  else
    echo "Original file hash does NOT match secret filename hash"
    exit 1
  fi

  # Verify decrypted content matches original
  if [ "$DECRYPTED_HASH" = "$ACTUAL_HASH" ]; then
    echo "Decrypted content matches original file"
  else
    echo "Decrypted content does NOT match original file"
    exit 1
  fi

  echo "All verification checks passed!"

# Edit a sops encrypted file
[group('secrets')]
edit-secret file:
  @sops {{ file }}

# Create a new sops encrypted file
[group('secrets')]
new-secret file:
  @sops {{ file }}

# Show specific secret value from shared secrets
[group('secrets')]
get-shared-secret key:
  @sops -d --extract '["{{ key }}"]' secrets/shared.yaml

# Run command with all shared secrets as environment variables
[group('secrets')]
run-with-secrets +command:
  @sops exec-env secrets/shared.yaml '{{ command }}'

# Validate all sops encrypted files can be decrypted
[group('secrets')]
validate-secrets:
  @echo "Validating sops encrypted files..."
  @for file in $(find secrets -name "*.yaml" -not -name ".sops.yaml"); do \
    echo "Testing: $file"; \
    sops -d "$file" > /dev/null && echo "  ✅ Valid" || echo "  ❌ Failed"; \
  done

## CI/CD

# Trigger CI workflow and wait for result (blocking)
[group('CI/CD')]
test-ci-blocking workflow="ci.yaml":
    #!/usr/bin/env bash
    set -euo pipefail

    echo "triggering workflow: {{workflow}} on branch: $(git branch --show-current)"
    gh workflow run {{workflow}} --ref $(git branch --show-current)

    # wait a moment for run to start
    sleep 5

    # get the latest run ID
    RUN_ID=$(gh run list --workflow={{workflow}} --limit 1 --json databaseId --jq '.[0].databaseId')

    echo "watching run: $RUN_ID"
    gh run watch "$RUN_ID" --exit-status

# View latest CI run status and details
[group('CI/CD')]
ci-status workflow="ci.yaml":
    @gh run list --workflow={{workflow}} --limit 1

# View latest CI run logs
[group('CI/CD')]
ci-logs workflow="ci.yaml":
    @RUN_ID=$(gh run list --workflow={{workflow}} --limit 1 --json databaseId --jq '.[0].databaseId'); \
    gh run view "$RUN_ID" --log

# View only failed logs from latest CI run
[group('CI/CD')]
ci-logs-failed workflow="ci.yaml":
    @RUN_ID=$(gh run list --workflow={{workflow}} --limit 1 --json databaseId --jq '.[0].databaseId'); \
    gh run view "$RUN_ID" --log-failed

# List categorized flake outputs using nix eval
[group('CI/CD')]
ci-show-outputs system="":
    @./scripts/ci/ci-show-outputs.sh "{{system}}"

# Build all flake outputs locally with nom (inefficient manual version of om ci for debugging builds)
[group('CI/CD')]
ci-build-local category="" system="":
    @./scripts/ci/ci-build-local.sh "{{category}}" "{{system}}"

# Validate latest CI run comprehensively
[group('CI/CD')]
ci-validate workflow="ci.yaml" run_id="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "{{run_id}}" ]; then
        RUN_ID=$(gh run list --workflow={{workflow}} --limit 1 --json databaseId --jq '.[0].databaseId')
    else
        RUN_ID="{{run_id}}"
    fi
    ./scripts/ci/validate-run.sh "$RUN_ID"

# Debug specific failed job from latest CI run
[group('CI/CD')]
ci-debug-job workflow="ci.yaml" job_name="nix (aarch64-darwin)":
    @RUN_ID=$(gh run list --workflow={{workflow}} --limit 1 --json databaseId --jq '.[0].databaseId'); \
    JOB_ID=$(gh run view "$RUN_ID" --json jobs --jq ".jobs[] | select(.name == \"{{job_name}}\") | .databaseId"); \
    gh run view --job "$JOB_ID" --log

# Update github secrets for repo from environment variables
[group('CI/CD')]
ghsecrets repo="cameronraysmith/nix-config":
  @echo "secrets before updates:"
  @echo
  PAGER=cat gh secret list --repo={{ repo }}
  @echo
  sops exec-env secrets/shared.yaml 'gh secret set CACHIX_AUTH_TOKEN --repo={{ repo }} --body="$CACHIX_AUTH_TOKEN"'
  @echo
  @echo secrets after updates:
  @echo
  PAGER=cat gh secret list --repo={{ repo }}

# List available workflows and associated jobs.
[group('CI/CD')]
list-workflows:
  @act -l

# Execute ci.yaml workflow locally via act.
[group('CI/CD')]
test-flake-workflow:
  @sops exec-env secrets/shared.yaml 'act workflow_dispatch \
  -W ".github/workflows/ci.yaml" \
  -j nixci \
  -s GITHUB_TOKEN -s CACHIX_AUTH_TOKEN \
  --matrix os:ubuntu-latest \
  --container-architecture linux/amd64'

# Command to run sethvargo/ratchet to pin GitHub Actions workflows version tags to commit hashes
# If not installed, you can use docker to run the command
# ratchet_base := "docker run -it --rm -v \"${PWD}:${PWD}\" -w \"${PWD}\" ghcr.io/sethvargo/ratchet:0.9.2"
ratchet_base := "ratchet"

# List of GitHub Actions workflows
gha_workflows := "./.github/workflows/flake.yaml"

# Pin all workflow versions to hash values (requires Docker)
[group('CI/CD')]
ratchet-pin:
  @for workflow in {{gha_workflows}}; do \
    eval "{{ratchet_base}} pin $workflow"; \
  done

# Unpin hashed workflow versions to semantic values (requires Docker)
[group('CI/CD')]
ratchet-unpin:
  @for workflow in {{gha_workflows}}; do \
    eval "{{ratchet_base}} unpin $workflow"; \
  done

# Update GitHub Actions workflows to the latest version (requires Docker)
[group('CI/CD')]
ratchet-update:
  @for workflow in {{gha_workflows}}; do \
    eval "{{ratchet_base}} update $workflow"; \
  done

# Push nix-rosetta-builder VM image to Cachix and pin it (run after system updates)
[group('CI/CD')]
cache-rosetta-builder:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Finding nix-rosetta-builder VM image in current system..."

    # Find the rosetta-builder.yaml from current system
    YAML_PATH=$(nix-store --query --requisites /run/current-system | grep 'rosetta-builder.yaml$' || true)

    if [ -z "$YAML_PATH" ]; then
        echo "❌ nix-rosetta-builder not found in current system"
        echo "   Is nix-rosetta-builder.enable = true in your configuration?"
        exit 1
    fi

    echo "Found config: $YAML_PATH"

    # Extract VM image path from YAML (format: "- location: /path/to/image")
    IMAGE_PATH=$(grep -A1 "images:" "$YAML_PATH" | grep "location:" | awk '{print $3}')

    if [ -z "$IMAGE_PATH" ]; then
        echo "❌ Could not extract image path from $YAML_PATH"
        exit 1
    fi

    echo "VM image: $IMAGE_PATH"
    IMAGE_SIZE=$(du -h "$IMAGE_PATH" | cut -f1)
    echo "Size: $IMAGE_SIZE"

    # Push to cachix
    echo ""
    echo "Pushing to Cachix (this may take a few minutes for ~2GB image)..."
    sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME $IMAGE_PATH"

    # Pin the image to prevent garbage collection
    echo ""
    echo "Pinning image to prevent garbage collection..."
    SHORT_HASH=$(echo "$IMAGE_PATH" | cut -d'/' -f4 | cut -d'-' -f1 | head -c8)
    PIN_NAME="nix-rosetta-builder-$SHORT_HASH"
    sops exec-env secrets/shared.yaml "cachix pin \$CACHIX_CACHE_NAME $PIN_NAME $IMAGE_PATH --keep-forever"

    echo ""
    echo "✅ Successfully pushed and pinned nix-rosetta-builder to Cachix"
    CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')
    echo "   View at: https://app.cachix.org/cache/$CACHE_NAME"
    echo "   Image: $IMAGE_PATH"
    echo "   Pin: $PIN_NAME"

# Check if nix-rosetta-builder image is in Cachix
[group('CI/CD')]
check-rosetta-cache:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Checking if nix-rosetta-builder image is cached..."

    # Find the image from current system
    YAML_PATH=$(nix-store --query --requisites /run/current-system | grep 'rosetta-builder.yaml$' || true)

    if [ -z "$YAML_PATH" ]; then
        echo "⚠️  nix-rosetta-builder not enabled in current system"
        exit 0
    fi

    echo "Found config: $YAML_PATH"

    IMAGE_PATH=$(grep -A1 "images:" "$YAML_PATH" | grep "location:" | awk '{print $3}')

    if [ -z "$IMAGE_PATH" ]; then
        echo "❌ Could not extract image path"
        exit 1
    fi

    echo "Checking cache for: $IMAGE_PATH"

    # Check if the image is in cache
    CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')

    if nix path-info --store "https://$CACHE_NAME.cachix.org" "$IMAGE_PATH" &>/dev/null; then
        echo "✅ Image is cached"
        echo "   Cache: https://$CACHE_NAME.cachix.org"
        echo "   Path: $IMAGE_PATH"
    else
        echo "❌ Image NOT in cache"
        echo "   Path: $IMAGE_PATH"
        echo "   Run: just cache-rosetta-builder"
        exit 1
    fi

# Test cachix push/pull with a simple derivation
[group('CI/CD')]
test-cachix:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Testing cachix push/pull..."

    # Build a simple derivation
    STORE_PATH=$(nix build nixpkgs#hello --no-link --print-out-paths)
    echo "Built: $STORE_PATH"

    # Push to cachix
    echo "Pushing to cachix..."
    sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME $STORE_PATH"

    # Verify it's in the cache by trying to pull it from another location
    CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')
    echo "✅ Push completed. Verify at: https://app.cachix.org/cache/$CACHE_NAME"
    echo "Store path: $STORE_PATH"

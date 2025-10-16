# This is a jusfile for the nix-config.
# Sections are separated by ## and recipes are documented with a single #
# on lines preceding the recipe.

## nix
## secrets
## sops
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

# Build an experimental debug package with nom (isolated from nixpkgs/CI builds)
[group('nix')]
debug-build package:
  nom build '.#debug.{{ package }}'

# List all available debug packages
[group('nix')]
debug-list:
  @echo "Available debug packages:"
  @nix eval .#debug --apply 'builtins.attrNames' --json | jq -r '.[]' | sort

# Check nix flake
[group('nix')]
check:
  nix flake check

# Verify system configuration builds after updates (run before activate)
[group('nix')]
verify:
  @./scripts/verify-system.sh

# Bisect nixpkgs commits to find which one broke the build (automatic mode)
[group('nix')]
bisect-nixpkgs:
  @./scripts/bisect-nixpkgs.sh auto

# Bisect nixpkgs commits (manual mode: start, step, status, reset)
[group('nix')]
bisect-nixpkgs-manual command="status":
  @./scripts/bisect-nixpkgs.sh {{ command }}

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
  echo "Update complete. Review changes with: git diff overlays/packages/{{ package }}/manifest.json"

## docs

# Install workspace dependencies
[group('docs')]
install:
  bun install

# Start documentation development server
[group('docs')]
docs-dev:
  cd packages/docs && bun run dev

# Build the documentation site
[group('docs')]
docs-build:
  cd packages/docs && bun run build

# Preview the built documentation site
[group('docs')]
docs-preview:
  cd packages/docs && bun run preview

# Format documentation code with Biome
[group('docs')]
docs-format:
  cd packages/docs && bun run format

# Lint documentation code with Biome
[group('docs')]
docs-lint:
  cd packages/docs && bun run lint

# Check and fix documentation code with Biome
[group('docs')]
docs-check:
  cd packages/docs && bun run check:fix

# Run all documentation tests
[group('docs')]
docs-test:
  cd packages/docs && bun run test

# Run documentation unit tests
[group('docs')]
docs-test-unit:
  cd packages/docs && bun run test:unit

# Run documentation E2E tests
[group('docs')]
docs-test-e2e:
  cd packages/docs && bun run test:e2e

# Generate documentation test coverage report
[group('docs')]
docs-test-coverage:
  cd packages/docs && bun run test:coverage

# Deploy documentation to Cloudflare Workers (preview)
[group('docs')]
docs-deploy-preview branch=`git branch --show-current`:
  #!/usr/bin/env bash
  cd packages/docs
  sops exec-env ../../secrets/shared.yaml "
    echo 'Deploying preview for branch: {{branch}}'
    echo 'Building...'
    bun run build
    echo 'Uploading version with preview alias...'
    bunx wrangler versions upload --preview-alias b-{{branch}}
  "

# Deploy documentation to Cloudflare Workers (production)
[group('docs')]
docs-deploy-production:
  #!/usr/bin/env bash
  cd packages/docs
  sops exec-env ../../secrets/shared.yaml "
    echo 'Building and deploying to production...'
    bun run build
    bunx wrangler deploy
  "

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
ci-run-watch workflow="ci.yaml":
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

# Build specific category for CI matrix jobs (optimized for disk space distribution)
[group('CI/CD')]
ci-build-category system category config="":
    @./scripts/ci/ci-build-category.sh "{{system}}" "{{category}}" "{{config}}"

# Build and cache specific category with all dependencies pushed to cachix (local testing)
[group('CI/CD')]
ci-cache-category system category config="":
    @./scripts/ci/ci-cache-category.sh "{{system}}" "{{category}}" "{{config}}"

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

# Upgrade GitHub Actions workflows across major versions (requires careful review)
[group('CI/CD')]
ratchet-upgrade:
  @for workflow in {{gha_workflows}}; do \
    eval "{{ratchet_base}} upgrade $workflow"; \
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

# Build a package for Linux architectures and push to cachix to avoid CI disk space issues
[group('CI/CD')]
cache-linux-package package:
    #!/usr/bin/env bash
    set -euo pipefail
    PACKAGE="{{ package }}"
    echo "Building $PACKAGE for Linux architectures using rosetta-builder..."
    CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')
    echo "Cache: https://app.cachix.org/cache/$CACHE_NAME"
    echo ""

    # Check if our package is identical to nixpkgs (redundant overlay)
    echo "Checking if package is redundant with nixpkgs..."
    OUR_DRV=$(nix eval --raw .#packages.aarch64-linux.$PACKAGE.drvPath 2>/dev/null || echo "none")
    NIXPKGS_DRV=$(nix eval --raw nixpkgs#$PACKAGE.drvPath --system aarch64-linux 2>/dev/null || echo "none")

    if [[ "$OUR_DRV" != "none" && "$NIXPKGS_DRV" != "none" && "$OUR_DRV" == "$NIXPKGS_DRV" ]]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️  WARNING: Redundant Overlay Detected"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Your overlay package is IDENTICAL to nixpkgs:"
        echo "  Package: $PACKAGE"
        echo "  Derivation: $OUR_DRV"
        echo ""
        echo "This typically happens when:"
        echo "  1. You copied a nixpkgs derivation to your overlay for upgrades"
        echo "  2. Then updated your nixpkgs lockfile"
        echo "  3. Now both are at the same version"
        echo ""
        echo "Implications:"
        echo "  • Your overlay provides zero value (byte-for-byte identical)"
        echo "  • Package is already available from cache.nixos.org"
        echo "  • CI will fetch from cache.nixos.org automatically"
        echo "  • Caching in personal cachix will likely fail (already exists elsewhere)"
        echo ""
        echo "Recommended action:"
        echo "  rm -rf overlays/packages/$PACKAGE/"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Skip caching and exit? (Y/n): "
        read -r response
        if [[ ! "$response" =~ ^[Nn]$ ]]; then
            echo ""
            echo "✓ Skipped caching - package available from cache.nixos.org"
            echo ""
            echo "Next steps:"
            echo "  1. Remove the redundant overlay: rm -rf overlays/packages/$PACKAGE/"
            echo "  2. Update any explicit references to use nixpkgs directly"
            echo "  3. Commit the cleanup"
            echo ""
            exit 0
        fi
        echo ""
        echo "⚠️  Continuing anyway - expect push/pin failures..."
        echo ""
        REDUNDANT_OVERLAY=true
    else
        echo "✓ Package differs from nixpkgs (custom overlay)"
        REDUNDANT_OVERLAY=false
    fi
    echo ""

    # Check if already cached
    echo "Checking cache status..."
    AARCH64_CACHED=false
    X86_64_CACHED=false

    if nix path-info --store "https://$CACHE_NAME.cachix.org" .#packages.aarch64-linux.$PACKAGE &>/dev/null; then
        echo "✓ aarch64-linux: Already in cache"
        AARCH64_CACHED=true
    else
        echo "  aarch64-linux: Need to build"
    fi

    if nix path-info --store "https://$CACHE_NAME.cachix.org" .#packages.x86_64-linux.$PACKAGE &>/dev/null; then
        echo "✓ x86_64-linux: Already in cache"
        X86_64_CACHED=true
    else
        echo "  x86_64-linux: Need to build"
    fi

    if [[ "$AARCH64_CACHED" == true && "$X86_64_CACHED" == true ]]; then
        echo ""
        echo "✅ Both architectures already cached. Nothing to do."
        exit 0
    fi

    echo ""
    echo "Building and pushing to cachix (this may take 15-30 minutes for large packages)..."
    echo "Using cachix watch-exec to push store paths as they're built..."
    echo ""

    # Build for aarch64-linux with watch-exec
    if [[ "$AARCH64_CACHED" != true ]]; then
        echo "Building for aarch64-linux..."
        AARCH64_PATH=$(sops exec-env secrets/shared.yaml \
            "cachix watch-exec \$CACHIX_CACHE_NAME --jobs 8 -- nom build .#packages.aarch64-linux.$PACKAGE --no-link --print-out-paths --max-jobs 0" | tail -1)

        # Push the path to cachix
        echo "Pushing $AARCH64_PATH to cachix..."
        if [[ "$REDUNDANT_OVERLAY" == "true" ]]; then
            # Try to push but expect failure (package already in cache.nixos.org)
            if sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME $AARCH64_PATH" 2>&1 | tee /tmp/cachix_push.log | grep -q "Nothing to push"; then
                echo "⚠️  As expected: package already available (likely in cache.nixos.org)"
                echo "   Skipping pin - remove overlay to avoid this workflow"
            else
                echo "✓ Push succeeded (unexpected for redundant overlay)"
            fi
        else
            # Normal cachix push for custom packages
            sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME $AARCH64_PATH"

            # Verify it's actually in our cachix before pinning
            echo "Verifying path is in cache..."
            sleep 3  # Allow CDN propagation
            if ! nix path-info --store "https://$CACHE_NAME.cachix.org" "$AARCH64_PATH" &>/dev/null; then
                echo "✗ Path not in cache after push, retrying..."
                sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME $AARCH64_PATH"
                sleep 3
            fi

            # Pin the path to prevent garbage collection
            PIN_NAME="${PACKAGE}-aarch64-linux"
            echo "Pinning $AARCH64_PATH as '$PIN_NAME'..."
            if sops exec-env secrets/shared.yaml "cachix pin \$CACHIX_CACHE_NAME $PIN_NAME $AARCH64_PATH"; then
                echo "✓ Pinned and verified: $AARCH64_PATH"
            else
                echo "✗ Failed to pin - path may not be in cache"
                exit 1
            fi
        fi
        echo ""
    fi

    # Build for x86_64-linux with watch-exec
    if [[ "$X86_64_CACHED" != true ]]; then
        echo "Building for x86_64-linux..."
        X86_64_PATH=$(sops exec-env secrets/shared.yaml \
            "cachix watch-exec \$CACHIX_CACHE_NAME --jobs 8 -- nom build .#packages.x86_64-linux.$PACKAGE --no-link --print-out-paths --max-jobs 0" | tail -1)

        # Push the path to cachix
        echo "Pushing $X86_64_PATH to cachix..."
        if [[ "$REDUNDANT_OVERLAY" == "true" ]]; then
            # Try to push but expect failure (package already in cache.nixos.org)
            if sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME $X86_64_PATH" 2>&1 | tee /tmp/cachix_push.log | grep -q "Nothing to push"; then
                echo "⚠️  As expected: package already available (likely in cache.nixos.org)"
                echo "   Skipping pin - remove overlay to avoid this workflow"
            else
                echo "✓ Push succeeded (unexpected for redundant overlay)"
            fi
        else
            # Normal cachix push for custom packages
            sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME $X86_64_PATH"

            # Verify it's actually in our cachix before pinning
            echo "Verifying path is in cache..."
            sleep 3  # Allow CDN propagation
            if ! nix path-info --store "https://$CACHE_NAME.cachix.org" "$X86_64_PATH" &>/dev/null; then
                echo "✗ Path not in cache after push, retrying..."
                sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME $X86_64_PATH"
                sleep 3
            fi

            # Pin the path to prevent garbage collection
            PIN_NAME="${PACKAGE}-x86_64-linux"
            echo "Pinning $X86_64_PATH as '$PIN_NAME'..."
            if sops exec-env secrets/shared.yaml "cachix pin \$CACHIX_CACHE_NAME $PIN_NAME $X86_64_PATH"; then
                echo "✓ Pinned and verified: $X86_64_PATH"
            else
                echo "✗ Failed to pin - path may not be in cache"
                exit 1
            fi
        fi
    fi

    # Summary
    echo ""
    if [[ "$REDUNDANT_OVERLAY" == "true" ]]; then
        echo "⚠️  Build completed (but caching skipped - package redundant with nixpkgs)"
        echo ""
        echo "IMPORTANT: Remove the redundant overlay to avoid this issue:"
        echo "  rm -rf overlays/packages/$PACKAGE/"
        echo ""
        echo "Your CI will fetch from cache.nixos.org automatically."
    else
        echo "✅ Successfully built and cached $PACKAGE for Linux architectures"
        echo "   Cache: https://app.cachix.org/cache/$CACHE_NAME"
        echo ""
        echo "CI will now fetch from cachix instead of building, avoiding disk space issues."
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

# Build all CI outputs for a system and push to cachix (mimics CI workflow with caching)
[group('CI/CD')]
cache-ci-outputs system="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Determine target system (default to current system if not specified)
    if [ -z "{{system}}" ]; then
        TARGET_SYSTEM=$(nix eval --impure --raw --expr 'builtins.currentSystem')
    else
        TARGET_SYSTEM="{{system}}"
    fi

    # Validate system is one of the three supported platforms
    case "$TARGET_SYSTEM" in
        x86_64-linux|aarch64-linux|aarch64-darwin)
            echo "Building all CI outputs for $TARGET_SYSTEM..."
            ;;
        *)
            echo "❌ Error: Unsupported system '$TARGET_SYSTEM'"
            echo "Supported systems:"
            echo "  • x86_64-linux   (Intel/AMD Linux)"
            echo "  • aarch64-linux  (ARM Linux)"
            echo "  • aarch64-darwin (Apple Silicon macOS)"
            exit 1
            ;;
    esac

    CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')
    echo "Cache: https://app.cachix.org/cache/$CACHE_NAME"
    echo ""
    echo "This will:"
    echo "  1. Build all flake outputs for $TARGET_SYSTEM via 'om ci run'"
    echo "  2. Include all build dependencies (--include-all-dependencies)"
    echo "  3. Stream output to console while pushing to cachix"
    echo ""
    echo "Starting build + push (this may take 10-30 minutes)..."
    echo ""

    # Run om ci with dependency tracking, show output, and push to cachix
    # This matches the CI workflow for darwin builds (line 464 in ci.yaml)
    om ci run --systems "$TARGET_SYSTEM" --include-all-dependencies 2>&1 | \
        tee /dev/tty | \
        sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME"

    echo ""
    echo "✅ Successfully built and cached all CI outputs for $TARGET_SYSTEM"
    echo "   Cache: https://app.cachix.org/cache/$CACHE_NAME"
    echo ""
    echo "Other machines can now pull from cachix instead of rebuilding."

# Build darwin system and push to cachix (run after just verify or just activate)
[group('CI/CD')]
cache-darwin-system:
    #!/usr/bin/env bash
    set -euo pipefail

    HOSTNAME=$(hostname)
    echo "Building darwin system for $HOSTNAME..."
    CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')
    echo "Cache: https://app.cachix.org/cache/$CACHE_NAME"
    echo ""

    # Check if already cached
    FLAKE_OUTPUT=".#darwinConfigurations.$HOSTNAME.system"
    echo "Checking if system is already cached..."
    if nix path-info --store "https://$CACHE_NAME.cachix.org" "$FLAKE_OUTPUT" &>/dev/null; then
        CACHED_PATH=$(nix path-info --store "https://$CACHE_NAME.cachix.org" "$FLAKE_OUTPUT")
        echo "✓ System already cached: $CACHED_PATH"
        echo ""
        read -p "Push again anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping. System is already in cachix."
            exit 0
        fi
    fi

    echo "Building system configuration..."
    SYSTEM_PATH=$(nom build "$FLAKE_OUTPUT" --no-link --print-out-paths 2>&1 | tail -1)

    if [ -z "$SYSTEM_PATH" ] || [ ! -e "$SYSTEM_PATH" ]; then
        echo "❌ Failed to build system or get store path"
        exit 1
    fi

    echo "Built: $SYSTEM_PATH"
    echo ""

    # Push the path and all its runtime dependencies
    echo "Pushing system and all dependencies to cachix..."
    echo "(This may take several minutes depending on what's not already cached)"
    nix-store --query --requisites --include-outputs "$SYSTEM_PATH" | \
        sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME"

    echo ""
    echo "✅ Successfully pushed darwin system to cachix"
    echo "   Cache: https://app.cachix.org/cache/$CACHE_NAME"
    echo "   System: $SYSTEM_PATH"
    echo ""
    echo "Other machines can now pull from cachix instead of rebuilding."

# Build and cache all overlay packages for a specific system (avoids CI disk space issues)
[group('CI/CD')]
cache-overlay-packages system:
    #!/usr/bin/env bash
    set -euo pipefail

    SYSTEM="{{system}}"
    echo "Building all overlay packages for $SYSTEM..."
    CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')
    echo "Cache: https://app.cachix.org/cache/$CACHE_NAME"
    echo ""

    # Discover all packages via nix eval
    echo "Discovering packages..."
    PACKAGES=$(nix eval ".#packages.$SYSTEM" --apply 'builtins.attrNames' --json | jq -r '.[]')

    if [ -z "$PACKAGES" ]; then
        echo "❌ No packages found for $SYSTEM"
        exit 1
    fi

    PACKAGE_COUNT=$(echo "$PACKAGES" | wc -l | tr -d ' ')
    echo "Found $PACKAGE_COUNT packages:"
    echo "$PACKAGES" | while read pkg; do echo "  - $pkg"; done
    echo ""

    # Build all packages with single nix build command
    echo "Building all packages..."
    PACKAGE_TARGETS=$(echo "$PACKAGES" | sed "s|^|.#packages.$SYSTEM.|" | tr '\n' ' ')

    # Build and capture output paths
    STORE_PATHS=$(nix build $PACKAGE_TARGETS -L --no-link --print-out-paths)

    if [ -z "$STORE_PATHS" ]; then
        echo "❌ No store paths produced from build"
        exit 1
    fi

    PATHS_COUNT=$(echo "$STORE_PATHS" | wc -l | tr -d ' ')
    echo ""
    echo "Built $PATHS_COUNT store paths"
    echo ""

    # Query all dependencies and push to cachix
    echo "Querying dependencies and pushing to cachix..."
    echo "(This includes all build dependencies for cache efficiency)"

    echo "$STORE_PATHS" | while read path; do
        nix-store --query --requisites --include-outputs "$path"
    done | sort -u | sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME"

    echo ""
    echo "✅ Successfully cached all overlay packages for $SYSTEM"
    echo "   Cache: https://app.cachix.org/cache/$CACHE_NAME"
    echo ""
    echo "CI will now fetch from cachix instead of building."

## sops

# Extract key details from Bitwarden (all sops-* keys or specific key)
[group('sops')]
sops-extract-keys key="":
  #!/usr/bin/env bash
  if [ -n "{{key}}" ]; then
    scripts/sops/extract-key-details.sh "{{key}}"
  else
    scripts/sops/extract-key-details.sh
  fi

# Update .sops.yaml with keys from Bitwarden
[group('sops')]
sops-update-yaml:
  @scripts/sops/update-sops-yaml.sh

# Deploy host key from Bitwarden to /etc/ssh/ (requires sudo)
[group('sops')]
sops-deploy-host-key host:
  @scripts/sops/deploy-host-key.sh {{host}}

# Validate all SOPS key correspondences (config.nix ↔ Bitwarden ↔ .sops.yaml)
[group('sops')]
sops-validate-correspondences:
  @scripts/sops/validate-correspondences.sh

# Regenerate ~/.config/sops/age/keys.txt from Bitwarden
[group('sops')]
sops-sync-keys *FLAGS:
  @scripts/sops/sync-age-keys.sh {{FLAGS}}

# Full key rotation workflow (interactive)
[group('sops')]
sops-rotate:
  @echo "=== SOPS Key Rotation Workflow ==="
  @echo ""
  @echo "Prerequisites:"
  @echo "  1. Generate new SSH keys in Bitwarden Web UI:"
  @echo "     - sops-dev-ssh, sops-ci-ssh (repository keys)"
  @echo "     - sops-admin-user-ssh, sops-raquel-user-ssh (user identity keys)"
  @echo "     - sops-{hostname}-ssh for each host (host keys)"
  @echo "  2. Ensure Bitwarden CLI is unlocked: export BW_SESSION=\$(bw unlock --raw)"
  @echo ""
  @echo "Press Enter to continue or Ctrl-C to abort..."
  @read
  @echo ""
  @echo "Step 1: Extracting and validating keys from Bitwarden..."
  @just sops-extract-keys
  @echo ""
  @echo "Step 2: Updating .sops.yaml..."
  @just sops-update-yaml
  @echo ""
  @echo "Step 3: Re-encrypting secrets..."
  @find secrets/ -name "*.yaml" -type f -exec sops updatekeys {} \;
  @echo ""
  @echo "Step 4: Validating correspondences..."
  @just sops-validate-correspondences
  @echo ""
  @echo "=== Manual steps remaining ==="
  @echo "1. Deploy host keys: just sops-deploy-host-key <hostname>"
  @echo "2. Update GitHub CI secret: gh secret set SOPS_AGE_KEY --repo=\$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  @echo "3. Test decryption: sops -d secrets/shared.yaml"
  @echo "4. Commit and push changes"
  @echo "5. Verify CI pipeline passes"


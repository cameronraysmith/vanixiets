# This is a jusfile for the vanixiets repository.
# Sections are separated by ## and recipes are documented with a single #
# on lines preceding the recipe.

## nix
## clan
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

## activation
# Unified activation commands using nh via flake apps
# All recipes accept nh flags: --dry (preview), --ask (confirm), --verbose

# Auto-detect platform and activate current machine
[group('activation')]
activate *FLAGS:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "$(uname -s)" == "Darwin" ]]; then
        exec just activate-darwin "$(hostname -s)" {{FLAGS}}
    elif [ -f /etc/NIXOS ]; then
        exec just activate-os "$(hostname)" {{FLAGS}}
    else
        exec just activate-home "$USER" {{FLAGS}}
    fi

# Activate darwin configuration
[group('activation')]
activate-darwin hostname *FLAGS:
    @echo "Activating darwin configuration for {{hostname}}..."
    nix run --accept-flake-config .#darwin -- {{hostname}} . {{FLAGS}}

# Activate NixOS configuration
[group('activation')]
activate-os hostname *FLAGS:
    @echo "Activating NixOS configuration for {{hostname}}..."
    nix run --accept-flake-config .#os -- {{hostname}} . {{FLAGS}}

# Activate home-manager configuration
[group('activation')]
activate-home username *FLAGS:
    @echo "Activating home-manager configuration for {{username}}..."
    nix run --accept-flake-config .#home -- {{username}} . {{FLAGS}}

# Print nix flake inputs and outputs
[group('nix')]
flake-info:
  nix flake metadata
  nix flake show --legacy --all-systems

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
  #!/usr/bin/env bash
  set -euo pipefail
  echo "Running nix flake check..."
  echo ""
  echo "Note: The following nix-unit warnings are expected and harmless:"
  echo "  - 'unknown setting allowed-users/trusted-users' (daemon settings don't apply in pure eval)"
  echo "  - '--gc-roots-dir not specified' (nix-unit doesn't persist GC roots)"
  echo "  - 'input has an override for non-existent input self' (nix-unit internal mechanism)"
  echo "  - 'not writing modified lock file' (expected for read-only check)"
  echo ""
  nix flake check

# Fast checks excluding heavy VM integration tests (~1-2 min vs ~7 min for full)
[group('nix')]
check-fast system="x86_64-linux":
  #!/usr/bin/env bash
  set -euo pipefail
  echo "Running fast checks for {{system}} (excluding VM tests)..."
  echo ""
  echo "Note: The following nix-unit warnings are expected and harmless:"
  echo "  - 'unknown setting allowed-users/trusted-users' (daemon settings don't apply in pure eval)"
  echo "  - '--gc-roots-dir not specified' (nix-unit doesn't persist GC roots)"
  echo "  - 'input has an override for non-existent input self' (nix-unit internal mechanism)"
  echo "  - 'not writing modified lock file' (expected for read-only check)"
  echo ""

  # Get all checks except vm-* which are heavy integration tests
  CHECKS=$(nix eval ".#checks.{{system}}" --apply 'builtins.attrNames' --json | jq -r '.[] | select(startswith("vm-") | not)')

  echo "Checks to run:"
  echo "$CHECKS" | while read check; do echo "  - $check"; done
  echo ""

  # Build each check
  for check in $CHECKS; do
    echo "::group::$check"
    nix build ".#checks.{{system}}.$check" --print-build-logs
    echo "::endgroup::"
  done

  echo "✓ All fast checks passed"

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
  {{ user }}@{{ destination }}:~/vanixiets

# Build nixos from flake
[group('nixos')]
nixos-build profile="aarch64":
  just build "nixosConfigurations.{{ profile }}.config.system.build.toplevel"

# Test nixos from flake
[group('nixos')]
nixos-test profile="aarch64":
  nixos-rebuild test --flake ".#{{ profile }}"

# Update nix flake
[group('nix')]
update:
  nix flake update

# Update a package using its updateScript
# Note: claude-code-bin and ccstatusline are now from llm-agents and update via flake update
[group('nix')]
update-package package="atuin-format":
  #!/usr/bin/env bash
  set -euo pipefail
  UPDATE_SCRIPT=$(nix build .#{{ package }}.updateScript --no-link --print-out-paths)
  echo "Running updateScript for {{ package }}..."
  $UPDATE_SCRIPT
  echo "Update complete. Review changes with: git diff"

## clan
# Commands for clan-based machine management (dendritic+clan architecture)

# Run all tests (nix flake check)
[group('clan')]
test:
  nix flake check

# Run fast tests only (nix-unit + validation tests)
[group('clan')]
test-quick:
  @echo "Running fast validation tests..."
  @echo "TC-017: Naming conventions"
  nix build .#checks.aarch64-darwin.naming-conventions --print-build-logs
  @echo ""
  @echo "TC-007: Secrets generation"
  nix build .#checks.aarch64-darwin.secrets-generation --print-build-logs
  @echo ""
  @echo "TC-006: Deployment safety"
  nix build .#checks.aarch64-darwin.deployment-safety --print-build-logs
  @echo ""
  @echo "TC-012: Terraform validation"
  nix build .#checks.aarch64-darwin.terraform-validate --print-build-logs
  @echo ""
  @echo "✓ All validation tests passed"

# Run integration tests (VM tests - Linux only)
[group('clan')]
test-integration:
  @echo "Running VM integration tests (Linux only)..."
  @echo ""
  @echo "TC-005: VM test framework validation"
  nix build .#checks.x86_64-linux.vm-test-framework --print-build-logs
  @echo ""
  @echo "TC-010: VM boot all machines"
  nix build .#checks.x86_64-linux.vm-boot-all-machines --print-build-logs
  @echo ""
  @echo "All VM integration tests passed!"

# Build all machine configurations using nom
[group('clan')]
build-all:
  @echo "Building all machine configurations..."
  nom build .#nixosConfigurations.cinnabar.config.system.build.toplevel
  nom build .#nixosConfigurations.electrum.config.system.build.toplevel
  nom build .#darwinConfigurations.blackphos.system
  nom build .#darwinConfigurations.stibnite.system
  @echo "All machines built successfully"

# Build a specific machine configuration
[group('clan')]
build-machine machine:
  nom build .#nixosConfigurations.{{machine}}.config.system.build.toplevel || \
  nom build .#darwinConfigurations.{{machine}}.system

# Show flake outputs
[group('clan')]
clan-show:
  nix flake show

# Show flake metadata
[group('clan')]
clan-metadata:
  nix flake metadata

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

# Validate internal and external links in documentation
[group('docs')]
docs-linkcheck:
  cd packages/docs && bun run linkcheck

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
  set -euo pipefail
  cd packages/docs

  # Sanitize branch name for Cloudflare alias (must be valid subdomain component)
  # - Replace / and other non-alphanumeric chars with -
  # - Collapse consecutive hyphens, remove leading/trailing hyphens
  # - Truncate to 40 chars (safe for subdomain label limit of 63)
  SAFE_BRANCH=$(echo "{{branch}}" | tr '/' '-' | tr -c 'a-zA-Z0-9-' '-' | sed 's/--*/-/g; s/^-//; s/-$//' | cut -c1-40)

  # Capture git metadata (use 12-char SHA for tag - fits in 25 char limit, extremely collision-resistant)
  COMMIT_SHA=$(git rev-parse HEAD)
  COMMIT_TAG=$(git rev-parse --short=12 HEAD)
  COMMIT_SHORT=$(git rev-parse --short HEAD)
  COMMIT_MSG=$(git log -1 --pretty=format:'%s')
  GIT_STATUS=$(git diff-index --quiet HEAD -- && echo "clean" || echo "dirty")

  # Tag is 12-char SHA (deterministic, <= 25 chars, used to find this version on main)
  TAG="${COMMIT_TAG}"
  # Message includes full context for verification
  MESSAGE="[{{branch}}] ${COMMIT_MSG} (${COMMIT_TAG}, ${GIT_STATUS})"

  echo "Deploying preview for branch: {{branch}}"
  echo "Sanitized alias: b-${SAFE_BRANCH}"
  echo "Commit: ${COMMIT_SHORT} (${GIT_STATUS})"
  echo "Full SHA: ${COMMIT_SHA}"
  echo "Tag: ${COMMIT_TAG}"
  echo "Message: ${COMMIT_MSG}"
  echo ""

  # Export variables for use in sops exec-env
  export VERSION_TAG="${TAG}"
  export VERSION_MESSAGE="${MESSAGE}"
  export SAFE_BRANCH="${SAFE_BRANCH}"

  sops exec-env ../../secrets/shared.yaml '
    echo "Building..."
    bun run build
    echo "Uploading version with preview alias and metadata..."
    bunx wrangler versions upload \
      --preview-alias "b-${SAFE_BRANCH}" \
      --tag "$VERSION_TAG" \
      --message "$VERSION_MESSAGE"
  '

  echo ""
  echo "✓ Version uploaded successfully"
  echo "  Tag: ${COMMIT_TAG}"
  echo "  Full SHA: ${COMMIT_SHA}"
  echo "  Message: ${MESSAGE}"
  echo "  Preview URL: https://b-${SAFE_BRANCH}-infra-docs.sciexp.workers.dev"

# Deploy documentation to Cloudflare Workers (production)
[group('docs')]
docs-deploy-production:
    @./scripts/docs/deploy-production.sh

# List recent Cloudflare deployments
[group('docs')]
docs-deployments:
  cd packages/docs && sops exec-env ../../secrets/shared.yaml "bunx wrangler deployments list"

# Tail live logs from Cloudflare Workers
[group('docs')]
docs-tail:
  cd packages/docs && sops exec-env ../../secrets/shared.yaml "bunx wrangler tail"

# List recent Cloudflare versions
[group('docs')]
docs-versions limit="10":
  cd packages/docs && sops exec-env ../../secrets/shared.yaml "bunx wrangler versions list --limit {{limit}}"

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

# Scan repository for hardcoded secrets (full history)
[group('secrets')]
scan-secrets:
  gitleaks detect --verbose --redact

# Scan staged changes for secrets (pre-commit)
[group('secrets')]
scan-staged:
  gitleaks protect --staged --verbose --redact

# Show existing secrets using sops
[group('secrets')]
show:
  @echo "=== Shared secrets (secrets/shared.yaml) ==="
  @sops -d secrets/shared.yaml
  @echo
  @echo "=== Test secrets (secrets/test.yaml) ==="
  @sops -d secrets/test.yaml

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
    sops -d "$file" > /dev/null && echo "  ● Valid" || echo "  ⊘ Failed"; \
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

# Build all flake outputs locally with nom (for debugging builds)
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
ghsecrets repo="cameronraysmith/vanixiets": # gitleaks:allow
  @echo "secrets before updates:"
  @echo
  PAGER=cat gh secret list --repo={{ repo }}
  @echo
  sops exec-env secrets/shared.yaml 'unset GITHUB_TOKEN && gh secret set CACHIX_AUTH_TOKEN --repo={{ repo }} --body="$CACHIX_AUTH_TOKEN"'
  sops exec-env secrets/shared.yaml 'unset GITHUB_TOKEN && gh secret set FAST_FORWARD_PAT --repo={{ repo }} --body="$FAST_FORWARD_PAT"'
  sops exec-env secrets/shared.yaml 'unset GITHUB_TOKEN && gh secret set FLAKE_UPDATER_APP_ID --repo={{ repo }} --body="$FLAKE_UPDATER_APP_ID"'
  sops exec-env secrets/shared.yaml 'unset GITHUB_TOKEN && gh secret set FLAKE_UPDATER_PRIVATE_KEY --repo={{ repo }} --body="$FLAKE_UPDATER_PRIVATE_KEY"'
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

# Pin GitHub Actions workflow versions to commit SHAs
[group('CI/CD')]
ratchet-pin:
    @RATCHET_BASE="{{ratchet_base}}" GHA_WORKFLOWS="{{gha_workflows}}" ./scripts/ci/ratchet-workflow.sh pin

# Unpin GitHub Actions workflow versions to semantic versions
[group('CI/CD')]
ratchet-unpin:
    @RATCHET_BASE="{{ratchet_base}}" GHA_WORKFLOWS="{{gha_workflows}}" ./scripts/ci/ratchet-workflow.sh unpin

# Update GitHub Actions workflow versions to latest
[group('CI/CD')]
ratchet-update:
    @RATCHET_BASE="{{ratchet_base}}" GHA_WORKFLOWS="{{gha_workflows}}" ./scripts/ci/ratchet-workflow.sh update

# Upgrade GitHub Actions workflow versions across major versions
[group('CI/CD')]
ratchet-upgrade:
    @RATCHET_BASE="{{ratchet_base}}" GHA_WORKFLOWS="{{gha_workflows}}" ./scripts/ci/ratchet-workflow.sh upgrade

# Push nix-rosetta-builder VM image to Cachix and pin it (run after system updates)
[group('CI/CD')]
cache-rosetta-builder:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Finding nix-rosetta-builder VM image in current system..."

    # Find the rosetta-builder.yaml from current system
    YAML_PATH=$(nix-store --query --requisites /run/current-system | grep 'rosetta-builder.yaml$' || true)

    if [ -z "$YAML_PATH" ]; then
        echo "⊘ nix-rosetta-builder not found in current system"
        echo "   Is nix-rosetta-builder.enable = true in your configuration?"
        exit 1
    fi

    echo "Found config: $YAML_PATH"

    # Extract VM image path from YAML (format: "- location: /path/to/image")
    IMAGE_PATH=$(grep -A1 "images:" "$YAML_PATH" | grep "location:" | awk '{print $3}')

    if [ -z "$IMAGE_PATH" ]; then
        echo "⊘ Could not extract image path from $YAML_PATH"
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
    echo "● Successfully pushed and pinned nix-rosetta-builder to Cachix"
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
        echo "⊘ Could not extract image path"
        exit 1
    fi

    echo "Checking cache for: $IMAGE_PATH"

    # Check if the image is in cache
    CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')

    if nix path-info --store "https://$CACHE_NAME.cachix.org" "$IMAGE_PATH" &>/dev/null; then
        echo "● Image is cached"
        echo "   Cache: https://$CACHE_NAME.cachix.org"
        echo "   Path: $IMAGE_PATH"
    else
        echo "⊘ Image NOT in cache"
        echo "   Path: $IMAGE_PATH"
        echo "   Run: just cache-rosetta-builder"
        exit 1
    fi

# Build a package for Linux architectures and push to cachix
[group('CI/CD')]
cache-linux-package package:
    @./scripts/ci/cache-linux-package.sh "{{package}}"

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
    echo "● Push completed. Verify at: https://app.cachix.org/cache/$CACHE_NAME"
    echo "Store path: $STORE_PATH"

# Build all CI outputs for a system and push to cachix
[group('CI/CD')]
cache-ci-outputs system="":
    @./scripts/ci/cache-all-outputs.sh "{{system}}"

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
        echo "⊘ Failed to build system or get store path"
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
    echo "● Successfully pushed darwin system to cachix"
    echo "   Cache: https://app.cachix.org/cache/$CACHE_NAME"
    echo "   System: $SYSTEM_PATH"
    echo ""
    echo "Other machines can now pull from cachix instead of rebuilding."

# Build and cache all overlay packages for a specific system
[group('CI/CD')]
cache-overlay-packages system:
    @./scripts/ci/ci-cache-category.sh "{{system}}" packages

# List all packages in packages/ directory
[group('CI/CD')]
list-packages:
  @ls -1 packages/

# List packages in JSON format for CI matrix
[group('CI/CD')]
list-packages-json:
  #!/usr/bin/env bash
  cd packages
  packages=()
  for dir in */; do
    pkg_name="${dir%/}"
    if [ -f "$dir/package.json" ]; then
      packages+=("{\"name\":\"$pkg_name\",\"path\":\"packages/$pkg_name\"}")
    fi
  done
  echo "[$(IFS=,; echo "${packages[*]}")]"

# Validate package structure
[group('CI/CD')]
validate-package package:
  @echo "Validating package: {{ package }}"
  @test -d "packages/{{ package }}" || (echo "Package directory not found" && exit 1)
  @test -f "packages/{{ package }}/package.json" || (echo "package.json not found" && exit 1)
  @echo "✓ Package {{ package }} is valid"

# Test a package (install, unit tests, coverage, build, e2e)
[group('CI/CD')]
test-package package:
  cd packages/{{ package }} && bun install && bun run test:unit && bun run test:coverage && bun run build && bun run test:e2e

# Preview semantic-release version after merging current branch to target
[group('CI/CD')]
preview-version target="main" package="":
  #!/usr/bin/env bash
  set -euo pipefail
  if [ -n "{{package}}" ]; then
    ./scripts/preview-version.sh "{{target}}" "{{package}}"
  else
    ./scripts/preview-version.sh "{{target}}"
  fi

# Release a package using semantic-release
[group('CI/CD')]
release-package package dry_run="false":
  #!/usr/bin/env bash
  set -euo pipefail
  cd packages/{{ package }}
  if [ "{{ dry_run }}" = "true" ]; then
    npx semantic-release --dry-run --no-ci
  else
    echo "This will create a real release. Use dry_run=true for testing."
    npx semantic-release
  fi

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

# Update keys for all encrypted files in secrets directory
[group('sops')]
update-all-keys:
  fd -e yaml -e json . secrets/ -x sops updatekeys -y {}

# Load SOPS launchd agent for standalone home-manager (darwin only, one-time setup)
[group('sops')]
sops-load-agent:
  #!/usr/bin/env bash
  set -euo pipefail

  # Check if we're on darwin
  if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "⚠️  This command is only needed on macOS (darwin)"
    echo "   Linux uses systemd instead of launchd"
    exit 0
  fi

  PLIST="$HOME/Library/LaunchAgents/org.nix-community.home.sops-nix.plist"

  # Check if plist exists
  if [ ! -f "$PLIST" ]; then
    echo "⊘ SOPS plist not found: $PLIST"
    echo "   Run 'just activate' first to create the plist"
    exit 1
  fi

  # Check if already loaded
  if launchctl list | grep -q "org.nix-community.home.sops-nix"; then
    echo "✓ SOPS agent already loaded"
    echo "  Secrets directory: ~/.config/sops-nix/secrets/"
    exit 0
  fi

  # Load the agent
  echo "Loading SOPS launchd agent..."
  launchctl load "$PLIST"

  # Brief wait for agent to start
  sleep 1

  # Verify it loaded
  if launchctl list | grep -q "org.nix-community.home.sops-nix"; then
    echo "✓ SOPS agent loaded successfully"
    echo "  Secrets directory: ~/.config/sops-nix/secrets/"
    echo ""
    echo "  The agent will:"
    echo "  • Persist across reboots (plist in ~/Library/LaunchAgents)"
    echo "  • Automatically decrypt and deploy secrets"
    echo "  • Create symlinks from module paths to secrets directory"
  else
    echo "⊘ Failed to load SOPS agent"
    exit 1
  fi

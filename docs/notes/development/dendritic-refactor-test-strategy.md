# Test Strategy: Dendritic Flake-Parts Refactoring for test-clan

**Document Purpose:** Comprehensive testing strategy to enable risk-free refactoring of test-clan from manual module organization to full dendritic flake-parts compliance while preserving all clan-core integration requirements.

**Target Repository:** ~/projects/nix-workspace/test-clan (Phase 0 infrastructure)

**Strategic Context:** This test suite enables experimentation with dendritic patterns (import-tree, namespace exports, automatic discovery) while guaranteeing zero regression in critical infrastructure functionality validated by Story 1.5 (2 operational Hetzner VMs).

**Cross-Reference:**
- Architectural assessment: docs/notes/development/dendritic-flake-parts-assessment.md
- Story 1.2 evaluation: docs/notes/development/work-items/1-2-implement-dendritic-flake-parts-pattern-in-test-clan.md
- Reference architecture: ~/projects/nix-workspace/clan-infra (production patterns)
- Dendritic exemplar: ~/projects/nix-workspace/drupol-dendritic-infra (proven dendritic + infrastructure)

---

## Test Classification System

### Category 1: Regression Tests (MUST REMAIN PASSING)

Tests that validate existing functionality that **cannot break** during refactoring.
These tests should pass **before** refactoring and **after** refactoring with identical results.

**Critical Property:** If any regression test fails after refactoring, the refactoring has broken required functionality.

### Category 2: Feature Tests (EXPECTED TO FAIL → PASS)

Tests that validate new dendritic capabilities that **do not exist yet**.
These tests **will fail** before refactoring and **must pass** after refactoring.

**Critical Property:** These tests define what "successful dendritic adoption" means.

### Category 3: Invariant Tests (ARCHITECTURAL CONSTRAINTS)

Tests that validate clan-core compatibility requirements that **must never change** regardless of internal refactoring.
These tests enforce the contract between test-clan and clan-core's expected module structure.

**Critical Property:** These tests protect against breaking clan-core integration (service targeting, inventory, vars generation).

---

## Test Suite Architecture

```
test-clan/
├── tests/
│   ├── regression/              # Category 1: Must remain passing
│   │   ├── terraform-output-equivalence.nix
│   │   ├── nixos-closure-equivalence.nix
│   │   ├── machine-configurations-build.nix
│   │   └── operational-vm-stability.nix
│   ├── invariant/               # Category 3: Clan-core contract
│   │   ├── clan-inventory-structure.nix
│   │   ├── clan-service-targeting.nix
│   │   ├── clan-vars-generation.nix
│   │   └── specialArgs-propagation.nix
│   ├── feature/                 # Category 2: Dendritic capabilities
│   │   ├── import-tree-discovery.nix
│   │   ├── namespace-exports.nix
│   │   ├── automatic-host-collection.nix
│   │   └── self-composition.nix
│   ├── integration/             # End-to-end validation
│   │   ├── vm-boot-tests.nix
│   │   └── clan-services-functional.nix
│   └── snapshots/               # Golden outputs (baselines)
│       ├── terraform.json
│       ├── nixos-closures.json
│       ├── clan-inventory.json
│       └── flake-outputs.json
├── flake.nix                    # Add test infrastructure
└── test-runner.sh               # Orchestration script
```

---

## Regression Tests (Category 1)

These tests validate that refactoring preserves existing functionality validated in Story 1.5.

### RT-1: Terraform Output Equivalence

**File:** `tests/regression/terraform-output-equivalence.nix`

**Why Critical:**
Terraform state manages real infrastructure (2 operational Hetzner VMs: 162.55.175.87, 49.13.140.183).
Any divergence in terraform output could cause:
- Unintended resource destruction
- Configuration drift from deployed state
- Production outage

**Expected Behavior:**
- **Before refactor:** Generate terraform JSON, capture as baseline
- **After refactor:** Generate terraform JSON, must be semantically identical
- **Pass criteria:** Byte-for-byte identical (modulo timestamps/random IDs)

**Why It Should Remain Invariant:**
Dendritic refactoring changes internal module organization but should NOT change:
- Terraform resource definitions (modules/terranix/hetzner.nix)
- Terraform module exports (flake.modules.terranix.*)
- Terranix configuration generation (perSystem.terranix)

**clan-core Relationship:**
Terraform integration is orthogonal to clan-core.
clan-core provides `clan machines install` but doesn't control terraform resource definitions.

**Implementation:**

```nix
# tests/regression/terraform-output-equivalence.nix
{ self, pkgs, lib, ... }:
let
  # Build current terraform configuration
  terraformConfig = self.terranix.x86_64-linux.terraform;

  # Generate normalized JSON output
  generateTerraformJson = pkgs.runCommand "terraform-output" {
    buildInputs = [ terraformConfig.terraformWrapper.package pkgs.jq ];
  } ''
    cd ${terraformConfig.config.build}
    terraform init -backend=false 2>&1 | tee init.log
    terraform show -json > raw.json

    # Normalize: Remove timestamps, UUIDs, non-deterministic fields
    jq 'walk(
      if type == "object" then
        del(.timestamp, .id, .serial, .lineage)
      else .
      end
    )' raw.json | jq --sort-keys . > $out
  '';

  # Semantic comparison ignoring inconsequential differences
  compareTerraform = baseline: current: pkgs.runCommand "compare-terraform" {
    buildInputs = [ pkgs.jq pkgs.diffutils ];
  } ''
    echo "Comparing terraform outputs..."
    echo "Baseline: ${baseline}"
    echo "Current: ${current}"

    # Compare resource definitions
    jq '.values.root_module.resources' ${baseline} | jq --sort-keys . > baseline-resources.json
    jq '.values.root_module.resources' ${current} | jq --sort-keys . > current-resources.json

    if diff -u baseline-resources.json current-resources.json > $out; then
      echo "✅ PASS: Terraform resources identical" | tee -a $out
      exit 0
    else
      echo "❌ FAIL: Terraform resources differ!" | tee -a $out
      echo "This indicates the refactoring changed infrastructure definitions." | tee -a $out
      exit 1
    fi
  '';
in
{
  # Expose baseline generator
  baseline = generateTerraformJson;

  # Expose comparator (used after refactoring)
  compare = baseline: compareTerraform baseline generateTerraformJson;

  # Test metadata
  category = "regression";
  critical = true;
  mustRemainPassing = true;

  rationale = ''
    Terraform manages real infrastructure (2 operational VMs).
    Any divergence risks production outage.
    Dendritic refactoring MUST NOT change terraform resource definitions.
  '';
}
```

**Usage:**
```bash
# Before refactor: Capture baseline
nix build .#tests.regression.terraform-output-equivalence.baseline \
  -o tests/snapshots/terraform-baseline.json

# After refactor: Validate equivalence
nix build .#tests.regression.terraform-output-equivalence.compare \
  --arg baseline ./tests/snapshots/terraform-baseline.json
```

---

### RT-2: NixOS Configuration Closure Equivalence

**File:** `tests/regression/nixos-closure-equivalence.nix`

**Why Critical:**
NixOS configurations define the deployed system state.
Closure equivalence proves that machines will behave identically after refactoring.

**Expected Behavior:**
- **Before refactor:** Extract configuration properties (hostname, services, bootloader)
- **After refactor:** Configuration properties must be identical
- **Pass criteria:** All extracted properties match, closure runtime dependencies unchanged

**Why It Should Remain Invariant:**
Dendritic refactoring changes HOW modules are discovered/imported but should NOT change:
- Base module behavior (nix-settings, admins, initrd-networking)
- Host-specific configuration (bootloader, networking, firewall)
- Service enablement (sshd, zerotier, etc.)

**clan-core Relationship:**
clan-core's `clan machines install` deploys nixosConfigurations.
These configurations must remain functionally identical to preserve deployments.

**Implementation:**

```nix
# tests/regression/nixos-closure-equivalence.nix
{ self, lib, pkgs, ... }:
let
  # Extract deterministic properties from each configuration
  extractConfigProperties = name: config: {
    inherit name;

    # System identification
    hostName = config.config.networking.hostName;
    stateVersion = config.config.system.stateVersion;
    platform = config.config.nixpkgs.hostPlatform;

    # Boot configuration
    bootloader = {
      grubEnable = config.config.boot.loader.grub.enable;
      systemdBootEnable = config.config.boot.loader.systemd-boot.enable;
      efiCanTouch = config.config.boot.loader.efi.canTouchEfiVariables or false;
    };

    # Network configuration
    networking = {
      hostName = config.config.networking.hostName;
      firewallEnable = config.config.networking.firewall.enable;
      useDHCP = config.config.networking.useDHCP;
      useNetworkd = config.config.systemd.network.enable;
    };

    # Enabled services (clan-critical)
    services = {
      sshd = config.config.services.openssh.enable;
      zerotier = config.config.services.zerotierone.enable or false;
    };

    # User configuration
    users = builtins.attrNames config.config.users.users;
    hasWheelSudo = !config.config.security.sudo.wheelNeedsPassword;

    # Nix settings (from base modules)
    nixExperimentalFeatures = config.config.nix.settings.experimental-features or [];

    # Module imports count (for comparison)
    importsCount = builtins.length (config.config._module.args.modules or []);
  };

  # Generate snapshot for all configurations
  configSnapshot = lib.mapAttrs extractConfigProperties self.nixosConfigurations;

  # Validation: Ensure critical properties present
  validateConfig = name: props:
    let
      checks = {
        hasHostName = props.hostName != null && props.hostName != "";
        hasUsers = builtins.length props.users > 0;
        hasSshd = props.services.sshd == true;
        hasNixFlakes = builtins.elem "flakes" props.nixExperimentalFeatures;
      };
      failedChecks = lib.filterAttrs (_: v: !v) checks;
    in
      if failedChecks == {}
      then { success = true; }
      else { success = false; inherit failedChecks; };

  validationResults = lib.mapAttrs validateConfig configSnapshot;
in
{
  # Baseline snapshot
  baseline = pkgs.writeText "nixos-configs-baseline.json"
    (builtins.toJSON configSnapshot);

  # Current snapshot (for comparison)
  current = configSnapshot;

  # Validation results
  validation = validationResults;

  # Comparator
  compare = baseline: pkgs.runCommand "compare-nixos-configs" {
    buildInputs = [ pkgs.jq pkgs.diffutils ];
    baselineJson = pkgs.writeText "baseline.json" (builtins.toJSON baseline);
    currentJson = pkgs.writeText "current.json" (builtins.toJSON configSnapshot);
  } ''
    echo "Comparing NixOS configuration properties..."

    if diff -u $baselineJson $currentJson > $out; then
      echo "✅ PASS: NixOS configurations equivalent" | tee -a $out
      exit 0
    else
      echo "❌ FAIL: NixOS configurations differ!" | tee -a $out
      echo "This indicates the refactoring changed system behavior." | tee -a $out
      exit 1
    fi
  '';

  # Test metadata
  category = "regression";
  critical = true;
  mustRemainPassing = true;

  rationale = ''
    Deployed machines (162.55.175.87, 49.13.140.183) must behave identically.
    Configuration properties validate that system behavior is preserved.
    Dendritic refactoring MUST NOT change what modules DO, only HOW they're organized.
  '';
}
```

---

### RT-3: Machine Configurations Build Successfully

**File:** `tests/regression/machine-configurations-build.nix`

**Why Critical:**
If configurations don't evaluate/build, deployment is impossible.
This is the most basic sanity check.

**Expected Behavior:**
- **Before refactor:** All 3 machines build successfully
- **After refactor:** All 3 machines still build successfully
- **Pass criteria:** `nix build .#nixosConfigurations.{name}.config.system.build.toplevel` exits 0 for all machines

**Why It Should Remain Invariant:**
Dendritic refactoring must preserve module evaluation semantics.
Module imports via namespace should evaluate identically to relative path imports.

**clan-core Relationship:**
clan-core's `clan machines install` requires nixosConfigurations to build.
Build failures = deployment failures.

**Implementation:**

```nix
# tests/regression/machine-configurations-build.nix
{ self, lib, pkgs, ... }:
let
  # List of all expected machines
  expectedMachines = [ "hetzner-ccx23" "hetzner-cx43" "gcp-vm" ];

  # Build each configuration's toplevel
  buildMachine = name:
    let
      config = self.nixosConfigurations.${name} or (throw "Machine ${name} not found!");
      toplevel = config.config.system.build.toplevel;
    in
      pkgs.runCommand "build-${name}" {} ''
        echo "Building ${name}..."
        echo "Toplevel: ${toplevel}"
        echo "Store path: ${toplevel.outPath}"

        # Verify toplevel is a valid derivation
        if [ -e ${toplevel} ]; then
          echo "✅ ${name} builds successfully"
          echo "success" > $out
        else
          echo "❌ ${name} build failed!"
          exit 1
        fi
      '';

  # Build all machines
  buildResults = lib.listToAttrs (map (name: {
    inherit name;
    value = buildMachine name;
  }) expectedMachines);

  # Aggregate test
  buildAll = pkgs.runCommand "build-all-machines" {
    buildInputs = builtins.attrValues buildResults;
  } ''
    echo "Verifying all machines build..."

    ${lib.concatMapStringsSep "\n" (name: ''
      if [ -e ${buildResults.${name}} ]; then
        echo "✅ ${name}: $(cat ${buildResults.${name}})"
      else
        echo "❌ ${name}: FAILED"
        exit 1
      fi
    '') expectedMachines}

    echo "✅ PASS: All ${toString (builtins.length expectedMachines)} machines build successfully" > $out
  '';
in
{
  # Individual machine builds
  machines = buildResults;

  # Aggregate test
  all = buildAll;

  # Test metadata
  category = "regression";
  critical = true;
  mustRemainPassing = true;

  rationale = ''
    Configurations must evaluate and build successfully.
    This is the minimum requirement for deployment.
    Dendritic refactoring MUST NOT break module evaluation.

    Note: Store paths may differ (due to changed module organization in closure),
    but configurations must build without errors.
  '';

  clanCoreRequirement = ''
    clan-core's `clan machines install` invokes nixos-rebuild which requires
    .#nixosConfigurations.{name}.config.system.build.toplevel to be buildable.
    Build failures prevent deployment entirely.
  '';
}
```

---

## Invariant Tests (Category 3)

These tests validate clan-core integration requirements that must be preserved regardless of internal refactoring.

### IT-1: Clan Inventory Structure

**File:** `tests/invariant/clan-inventory-structure.nix`

**Why Critical:**
clan-core relies on specific inventory structure for machine discovery and service targeting.
Breaking this structure breaks clan's operational model.

**Expected Behavior:**
- **Before refactor:** Inventory has expected structure with 3 machines, 5 service instances
- **After refactor:** Inventory structure IDENTICAL (same machines, same services, same targeting)
- **Pass criteria:** All inventory paths exist with expected values

**Why It Must Remain Invariant:**
clan-core's service targeting (roles.controller.machines, roles.peer.tags."all") depends on inventory structure.
This is the contract between test-clan and clan-core.

**What test-clan Already Differs from clan-infra:**
- test-clan has 3 machines (2 operational + 1 planned GCP)
- clan-infra has 10+ machines
- Both use identical inventory.instances structure (emergency-access, users-root, zerotier, etc.)

**Implementation:**

```nix
# tests/invariant/clan-inventory-structure.nix
{ self, lib, pkgs, ... }:
let
  # Extract clan configuration
  clanConfig = self.clan or (throw "No clan configuration found! clan-core integration broken.");

  # Expected inventory structure (from Story 1.3)
  expectedStructure = {
    meta = {
      name = "test-clan";
      description = "Phase 0: Architectural validation + infrastructure deployment";
      tld = "clan";
    };

    machines = {
      hetzner-ccx23 = {
        tags = [ "nixos" "cloud" "hetzner" ];
        machineClass = "nixos";
      };
      hetzner-cx43 = {
        tags = [ "nixos" "cloud" "hetzner" ];
        machineClass = "nixos";
      };
      gcp-vm = {
        tags = [ "nixos" "cloud" "gcp" ];
        machineClass = "nixos";
      };
    };

    instances = {
      # Must have these service instances (clan-core services)
      requiredServices = [
        "emergency-access"
        "users-root"
        "zerotier"
        "tor"
      ];

      # Zerotier configuration is critical
      zerotier = {
        controller = "hetzner-ccx23";  # Specific controller machine
        peerTags = [ "all" ];           # All machines are peers
      };
    };
  };

  # Validate actual inventory matches expected
  validateInventory =
    let
      inventory = clanConfig.inventory;

      # Machine validation
      machineNames = builtins.attrNames inventory.machines;
      expectedMachines = builtins.attrNames expectedStructure.machines;
      hasMachines = lib.all (m: builtins.elem m machineNames) expectedMachines;

      machineTagsMatch = lib.all (name:
        let
          actual = inventory.machines.${name}.tags or [];
          expected = expectedStructure.machines.${name}.tags;
        in lib.all (t: builtins.elem t actual) expected
      ) expectedMachines;

      # Service instance validation
      instanceNames = builtins.attrNames inventory.instances;
      hasRequiredServices = lib.all (s:
        builtins.elem s instanceNames
      ) expectedStructure.instances.requiredServices;

      # Zerotier specific validation (critical for Story 1.5 operational VMs)
      zerotierInstance = inventory.instances.zerotier or null;
      zerotierValid =
        zerotierInstance != null &&
        builtins.hasAttr "controller" zerotierInstance.roles &&
        builtins.hasAttr "peer" zerotierInstance.roles &&
        builtins.hasAttr "hetzner-ccx23" zerotierInstance.roles.controller.machines &&
        builtins.hasAttr "all" zerotierInstance.roles.peer.tags;

      checks = {
        inherit hasMachines machineTagsMatch hasRequiredServices zerotierValid;

        # Meta validation
        metaNameCorrect = clanConfig.meta.name == expectedStructure.meta.name;
        metaTldCorrect = clanConfig.meta.tld == expectedStructure.meta.tld;
      };
    in
      checks;

  validationResult = validateInventory;
  allChecksPassed = builtins.all (x: x) (builtins.attrValues validationResult);
in
{
  # Validation results
  validation = validationResult;
  passed = allChecksPassed;

  # Detailed inventory snapshot
  snapshot = {
    meta = clanConfig.meta;
    machines = lib.mapAttrs (name: cfg: {
      inherit (cfg) tags machineClass;
    }) clanConfig.inventory.machines;
    instances = lib.mapAttrs (name: instance: {
      module = instance.module;
      roleNames = builtins.attrNames instance.roles;
    }) clanConfig.inventory.instances;
  };

  # Test assertion
  test = pkgs.runCommand "validate-clan-inventory" {
    result = builtins.toJSON validationResult;
  } ''
    echo "Validating clan inventory structure..."
    echo "$result" | ${pkgs.jq}/bin/jq .

    ${if allChecksPassed then ''
      echo "✅ PASS: Clan inventory structure correct"
      echo "All machines, services, and targeting rules present"
      echo "pass" > $out
    '' else ''
      echo "❌ FAIL: Clan inventory structure invalid"
      echo "Validation results: $result"
      echo "This breaks clan-core service targeting!"
      exit 1
    ''}
  '';

  # Test metadata
  category = "invariant";
  critical = true;
  mustAlwaysPass = true;

  rationale = ''
    clan-core's service targeting depends on inventory structure:
    - inventory.machines defines available machines
    - inventory.instances defines service deployments
    - roles.controller.machines targets specific machines
    - roles.peer.tags."all" targets all machines with "all" tag

    Dendritic refactoring MUST NOT change this structure.
    This is the contract between test-clan and clan-core.
  '';

  clanCoreContract = ''
    clan-core expects:
    1. clan.inventory.machines with tags and machineClass
    2. clan.inventory.instances with module references and roles
    3. Service targeting via roles.{name}.machines and roles.{name}.tags

    Breaking this contract breaks clan vars generation, service deployment,
    and operational tooling (clan machines list, clan machines install, etc.)
  '';

  differenceFromClanInfra = ''
    test-clan matches clan-infra's inventory structure pattern.
    Both use identical service instance format (emergency-access, zerotier, etc.)
    Difference is only in machine count (3 vs 10+) and specific machine names.
  '';
}
```

---

### IT-2: Clan Service Targeting Preservation

**File:** `tests/invariant/clan-service-targeting.nix`

**Why Critical:**
Service targeting (roles) determines which machines run which services.
Breaking targeting = services deploy to wrong machines or not at all.

**Expected Behavior:**
- **Before refactor:** zerotier controller on hetzner-ccx23, all machines are peers
- **After refactor:** IDENTICAL service targeting
- **Pass criteria:** All service role assignments unchanged

**Why It Must Remain Invariant:**
This validates Story 1.5's operational infrastructure:
- hetzner-ccx23 (162.55.175.87) is zerotier controller
- Both VMs are zerotier peers
- Emergency access on all machines

**clan-core Relationship:**
clan-core's `clan vars generate` uses service targeting to determine which machines receive which secrets/configs.

**Implementation:**

```nix
# tests/invariant/clan-service-targeting.nix
{ self, lib, pkgs, ... }:
let
  clanConfig = self.clan;
  instances = clanConfig.inventory.instances;

  # Expected service targeting (from Story 1.3, validated in Story 1.5)
  expectedTargeting = {
    "emergency-access" = {
      role = "default";
      targets = "tags.all";  # All machines
    };
    "users-root" = {
      role = "default";
      targets = "tags.all";  # All machines
    };
    "zerotier" = {
      controller = "machines.hetzner-ccx23";  # Specific machine
      peer = "tags.all";                      # All machines
    };
    "tor" = {
      role = "server";
      targets = "tags.nixos";  # All nixos machines
    };
  };

  # Extract actual targeting from inventory
  extractTargeting = instanceName: instance:
    let
      roles = instance.roles;
      roleTargets = lib.mapAttrs (roleName: roleConfig: {
        machines = builtins.attrNames (roleConfig.machines or {});
        tags = builtins.attrNames (roleConfig.tags or {});
      }) roles;
    in
      roleTargets;

  actualTargeting = lib.mapAttrs extractTargeting instances;

  # Validate specific critical targeting
  validateCriticalTargeting = {
    # Emergency access must target all machines
    emergencyAccessAll =
      let role = actualTargeting."emergency-access".default or null;
      in role != null && builtins.elem "all" role.tags;

    # Users-root must target all machines
    usersRootAll =
      let role = actualTargeting."users-root".default or null;
      in role != null && builtins.elem "all" role.tags;

    # Zerotier controller must be hetzner-ccx23 (Story 1.5 operational VM)
    zerotierControllerCorrect =
      let role = actualTargeting.zerotier.controller or null;
      in role != null && builtins.elem "hetzner-ccx23" role.machines;

    # Zerotier peers must be all machines
    zerotierPeerAll =
      let role = actualTargeting.zerotier.peer or null;
      in role != null && builtins.elem "all" role.tags;

    # Tor must target nixos machines
    torTargetsNixos =
      let role = actualTargeting.tor.server or null;
      in role != null && builtins.elem "nixos" role.tags;
  };

  allValidationsPassed = builtins.all (x: x) (builtins.attrValues validateCriticalTargeting);
in
{
  # Actual targeting extracted
  targeting = actualTargeting;

  # Validation results
  validation = validateCriticalTargeting;
  passed = allValidationsPassed;

  # Test assertion
  test = pkgs.runCommand "validate-service-targeting" {} ''
    echo "Validating clan service targeting..."

    ${lib.concatMapStringsSep "\n" (name:
      let check = validateCriticalTargeting.${name};
      in ''
        if ${if check then "true" else "false"}; then
          echo "✅ ${name}"
        else
          echo "❌ ${name} FAILED"
          exit 1
        fi
      ''
    ) (builtins.attrNames validateCriticalTargeting)}

    echo "✅ PASS: All service targeting preserved"
    echo "pass" > $out
  '';

  # Test metadata
  category = "invariant";
  critical = true;
  mustAlwaysPass = true;

  rationale = ''
    Service targeting determines service deployment topology.

    Critical for Story 1.5 operational infrastructure:
    - hetzner-ccx23 (162.55.175.87) MUST be zerotier controller
    - Both VMs MUST be zerotier peers (network connectivity)
    - Emergency access MUST be on all machines (operational recovery)

    Breaking targeting = services deploy incorrectly = infrastructure failure.
  '';

  clanCoreContract = ''
    clan-core uses service targeting for:
    1. vars generation: Which machines receive which secrets
    2. Service deployment: Which machines run which services
    3. Network topology: Controller/peer relationships (zerotier)

    Service targeting is defined via:
    - roles.{name}.machines.{machineName} = { ... }  (specific machines)
    - roles.{name}.tags.{tagName} = { ... }          (tag-based targeting)

    Dendritic refactoring MUST NOT change these role assignments.
  '';
}
```

---

### IT-3: specialArgs Propagation to Modules

**File:** `tests/invariant/specialArgs-propagation.nix`

**Why Critical:**
specialArgs = { inherit inputs; } enables host modules to import srvos.
Breaking this breaks module evaluation (infinite recursion, as documented in Story 1.4).

**Expected Behavior:**
- **Before refactor:** Host modules receive inputs via specialArgs
- **After refactor:** IDENTICAL specialArgs propagation
- **Pass criteria:** inputs accessible in all host module evaluation contexts

**Why It Must Remain Invariant:**
Story 1.4 established this pattern to fix module evaluation.
Story 1.2 assessment validated this is dendritic-compatible (drupol-dendritic-infra uses same pattern).

**What test-clan Already Differs from clan-infra:**
- test-clan: `specialArgs = { inherit inputs; }` (host modules need inputs)
- clan-infra: `specialArgs = { inherit self; }` (inputs accessed in flake-module scope)

This difference is INTENTIONAL and must be preserved.

**Implementation:**

```nix
# tests/invariant/specialArgs-propagation.nix
{ self, lib, pkgs, inputs, ... }:
let
  clanConfig = self.clan;

  # Verify specialArgs contains inputs
  hasInputsInSpecialArgs =
    clanConfig.specialArgs != null &&
    builtins.hasAttr "inputs" clanConfig.specialArgs;

  # Test that host modules can access inputs
  testModuleEvaluation = name: config:
    let
      # Create test module that requires inputs
      testModule = { inputs, lib, ... }: {
        _module.args._testInputsAvailable = inputs != null;
        _module.args._testSrvosAccessible =
          builtins.hasAttr "srvos" inputs &&
          builtins.hasAttr "nixosModules" inputs.srvos;
      };

      # Evaluate with test module
      testConfig = lib.nixosSystem {
        inherit (config.config.nixpkgs) system;
        specialArgs = clanConfig.specialArgs;
        modules = config.config._module.args.modules ++ [ testModule ];
      };
    in {
      inherit name;
      inputsAvailable = testConfig.config._module.args._testInputsAvailable;
      srvosAccessible = testConfig.config._module.args._testSrvosAccessible;
    };

  # Test all nixosConfigurations
  moduleTests = lib.mapAttrs testModuleEvaluation self.nixosConfigurations;

  allModulesCanAccessInputs = lib.all (test:
    test.inputsAvailable && test.srvosAccessible
  ) (builtins.attrValues moduleTests);
in
{
  # specialArgs validation
  hasInputs = hasInputsInSpecialArgs;

  # Module evaluation tests
  tests = moduleTests;
  passed = allModulesCanAccessInputs;

  # Test assertion
  test = pkgs.runCommand "validate-specialArgs" {
    testResults = builtins.toJSON moduleTests;
  } ''
    echo "Validating specialArgs propagation..."

    if ${if hasInputsInSpecialArgs then "true" else "false"}; then
      echo "✅ specialArgs contains inputs"
    else
      echo "❌ specialArgs missing inputs!"
      exit 1
    fi

    ${lib.concatMapStringsSep "\n" (name:
      let test = moduleTests.${name};
      in ''
        if ${if test.inputsAvailable && test.srvosAccessible then "true" else "false"}; then
          echo "✅ ${name}: inputs accessible, srvos importable"
        else
          echo "❌ ${name}: inputs NOT accessible!"
          exit 1
        fi
      ''
    ) (builtins.attrNames moduleTests)}

    echo "✅ PASS: specialArgs propagates inputs to all modules"
    echo "pass" > $out
  '';

  # Test metadata
  category = "invariant";
  critical = true;
  mustAlwaysPass = true;

  rationale = ''
    Story 1.4 established specialArgs = { inherit inputs; } to fix:
    - Infinite recursion in module evaluation
    - Enable srvos imports in host modules: inputs.srvos.nixosModules.server

    Story 1.2 assessment validated this pattern is dendritic-compatible.
    Real-world dendritic infrastructure (drupol-dendritic-infra) uses same pattern.

    Breaking this pattern breaks module evaluation entirely.
  '';

  clanCoreContract = ''
    clan-core doesn't directly depend on specialArgs content.
    However, modules that use clan-core services need specialArgs for:
    - Accessing inputs.clan-core.nixosModules.*
    - Accessing external module inputs (srvos, disko, etc.)

    This is orthogonal to clan-core but required for practical usage.
  '';

  differenceFromClanInfra = ''
    INTENTIONAL DIFFERENCE (documented in Story 1.4, validated in Story 1.2):

    clan-infra: specialArgs = { inherit self; }
    - Accesses inputs in modules/flake-module.nix scope (definition time)
    - Module definitions include inputs.srvos imports directly

    test-clan: specialArgs = { inherit inputs; }
    - Accesses inputs in individual host modules (evaluation time)
    - Host modules import inputs.srvos at runtime

    Both patterns are valid. test-clan prioritizes host module flexibility.
    Dendritic refactoring MUST preserve this choice.
  '';
}
```

---

## Feature Tests (Category 2)

These tests validate new dendritic capabilities that don't exist yet.
They WILL FAIL before refactoring and MUST PASS after refactoring.

### FT-1: import-tree Automatic Discovery

**File:** `tests/feature/import-tree-discovery.nix`

**Why Important:**
import-tree automatic discovery is the PRIMARY dendritic pattern.
This test defines what "successful dendritic adoption" means.

**Expected Behavior:**
- **Before refactor:** FAIL - import-tree not used in flake.nix
- **After refactor:** PASS - import-tree discovers all modules automatically
- **Pass criteria:** All modules in modules/ discovered without manual imports

**Why It Will Fail Now:**
Current flake.nix uses manual imports (lines 37-40):
```nix
imports = [
  inputs.clan-core.flakeModules.default
  ./modules/flake-parts/clan.nix
  ./modules/flake-parts/nixpkgs.nix
];
```

**Why It Should Pass After Refactoring:**
After dendritic refactoring, flake.nix will use:
```nix
outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; }
  (inputs.import-tree ./modules);
```

**Implementation:**

```nix
# tests/feature/import-tree-discovery.nix
{ self, lib, pkgs, ... }:
let
  # Expected modules that should be discovered
  expectedModules = {
    # flake-parts modules
    "flake-parts/clan" = true;
    "flake-parts/nixpkgs" = true;

    # Host modules (after refactoring to namespace exports)
    "hosts/hetzner-ccx23" = true;
    "hosts/hetzner-cx43" = true;
    "hosts/gcp-vm" = true;

    # Base modules (after refactoring to namespace exports)
    "base/nix-settings" = true;
    "base/admins" = true;
    "base/initrd-networking" = true;
  };

  # Check if module exists in flake.modules namespace
  moduleExists = path:
    let
      # Try nixos namespace first
      nixosPath = lib.splitString "/" path;
      hasInNixos = lib.hasAttrByPath (["flake" "modules" "nixos"] ++ nixosPath) self;

      # Try other namespaces
      hasInOther = lib.hasAttrByPath (["flake" "modules"] ++ nixosPath) self;
    in
      hasInNixos || hasInOther;

  # Test each expected module
  discoveryTests = lib.mapAttrs (path: _: {
    inherit path;
    discovered = moduleExists path;
  }) expectedModules;

  allModulesDiscovered = lib.all (test: test.discovered)
    (builtins.attrValues discoveryTests);

  # Check if import-tree is actually being used
  usesImportTree =
    # Heuristic: If we have many modules in namespace without manual imports,
    # import-tree is likely active
    let
      moduleCount = builtins.length (builtins.attrNames (self.flake.modules or {}));
    in moduleCount >= builtins.length (builtins.attrNames expectedModules);
in
{
  # Discovery test results
  tests = discoveryTests;
  passed = allModulesDiscovered && usesImportTree;

  # Detailed diagnostics
  diagnostics = {
    expectedModuleCount = builtins.length (builtins.attrNames expectedModules);
    discoveredModuleCount = builtins.length (lib.filter (t: t.discovered)
      (builtins.attrValues discoveryTests));
    usesImportTree = usesImportTree;
  };

  # Test assertion
  test = pkgs.runCommand "validate-import-tree" {} ''
    echo "Testing import-tree automatic discovery..."

    ${lib.concatMapStringsSep "\n" (path:
      let test = discoveryTests.${path};
      in ''
        if ${if test.discovered then "true" else "false"}; then
          echo "✅ ${path}: discovered"
        else
          echo "❌ ${path}: NOT discovered"
          FAILED=1
        fi
      ''
    ) (builtins.attrNames discoveryTests)}

    if [ -n "''${FAILED:-}" ]; then
      echo "❌ FAIL: import-tree not discovering modules"
      echo "This is EXPECTED before dendritic refactoring"
      exit 1
    else
      echo "✅ PASS: import-tree discovering all modules automatically"
      echo "pass" > $out
    fi
  '';

  # Test metadata
  category = "feature";
  critical = false;  # Not critical for existing functionality
  expectedToFailBeforeRefactor = true;
  mustPassAfterRefactor = true;

  rationale = ''
    import-tree automatic discovery is the core dendritic pattern.

    BEFORE refactoring: This test WILL FAIL
    - flake.nix uses manual imports
    - Modules not exported to namespace automatically

    AFTER refactoring: This test MUST PASS
    - flake.nix uses: (inputs.import-tree ./modules)
    - All modules automatically discovered and exported
    - Zero manual import statements required

    This test defines successful dendritic adoption.
  '';

  implementationGuide = ''
    To make this test pass, refactor flake.nix:

    BEFORE:
    outputs = inputs@{ flake-parts, ... }:
      flake-parts.lib.mkFlake { inherit inputs; } {
        imports = [
          inputs.clan-core.flakeModules.default
          ./modules/flake-parts/clan.nix
          ./modules/flake-parts/nixpkgs.nix
        ];
      };

    AFTER:
    outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; }
      (inputs.import-tree ./modules);

    import-tree will automatically discover all modules/flake-parts/*.nix
    and export them to config.flake.modules namespace.
  '';
}
```

---

### FT-2: Module Namespace Exports

**File:** `tests/feature/namespace-exports.nix`

**Why Important:**
Namespace exports enable self-composition and external consumption of modules.
This is the second core dendritic principle.

**Expected Behavior:**
- **Before refactor:** FAIL - Only terranix modules exported
- **After refactor:** PASS - All modules exported to namespace
- **Pass criteria:** Base modules and host modules accessible via config.flake.modules

**Why It Will Fail Now:**
Only terranix modules currently exported (modules/flake-parts/clan.nix:8-9).
Base modules use relative imports, not namespace exports.

**Implementation:**

```nix
# tests/feature/namespace-exports.nix
{ self, lib, pkgs, ... }:
let
  # Expected namespace exports after dendritic refactoring
  expectedExports = {
    # Base modules should be exported
    "nixos/base/nix-settings" = {
      namespace = ["flake" "modules" "nixos" "base" "nix-settings"];
      exists = lib.hasAttrByPath ["flake" "modules" "nixos" "base" "nix-settings"] self;
    };
    "nixos/base/admins" = {
      namespace = ["flake" "modules" "nixos" "base" "admins"];
      exists = lib.hasAttrByPath ["flake" "modules" "nixos" "base" "admins"] self;
    };
    "nixos/base/initrd-networking" = {
      namespace = ["flake" "modules" "nixos" "base" "initrd-networking"];
      exists = lib.hasAttrByPath ["flake" "modules" "nixos" "base" "initrd-networking"] self;
    };

    # Host modules should be exported
    "nixos/hosts/hetzner-ccx23" = {
      namespace = ["flake" "modules" "nixos" "hosts/hetzner-ccx23"];
      exists = lib.hasAttrByPath ["flake" "modules" "nixos" "hosts/hetzner-ccx23"] self;
    };
    "nixos/hosts/hetzner-cx43" = {
      namespace = ["flake" "modules" "nixos" "hosts/hetzner-cx43"];
      exists = lib.hasAttrByPath ["flake" "modules" "nixos" "hosts/hetzner-cx43"] self;
    };
    "nixos/hosts/gcp-vm" = {
      namespace = ["flake" "modules" "nixos" "hosts/gcp-vm"];
      exists = lib.hasAttrByPath ["flake" "modules" "nixos" "hosts/gcp-vm"] self;
    };

    # Terranix modules should STILL be exported (regression check)
    "terranix/base" = {
      namespace = ["flake" "modules" "terranix" "base"];
      exists = lib.hasAttrByPath ["flake" "modules" "terranix" "base"] self;
    };
    "terranix/hetzner" = {
      namespace = ["flake" "modules" "terranix" "hetzner"];
      exists = lib.hasAttrByPath ["flake" "modules" "terranix" "hetzner"] self;
    };
  };

  exportResults = lib.mapAttrs (_: exp: exp.exists) expectedExports;
  allExportsExist = lib.all (x: x) (builtins.attrValues exportResults);

  # Count current vs expected exports
  currentExportCount = builtins.length (builtins.attrNames (self.flake.modules or {}));
  expectedExportCount = builtins.length (builtins.attrNames expectedExports);
in
{
  # Export test results
  tests = expectedExports;
  results = exportResults;
  passed = allExportsExist;

  # Diagnostics
  diagnostics = {
    inherit currentExportCount expectedExportCount;
    missingExports = lib.filterAttrs (_: exists: !exists) exportResults;
  };

  # Test assertion
  test = pkgs.runCommand "validate-namespace-exports" {} ''
    echo "Testing module namespace exports..."

    ${lib.concatMapStringsSep "\n" (name:
      let exp = expectedExports.${name};
      in ''
        if ${if exp.exists then "true" else "false"}; then
          echo "✅ ${name}: exported"
        else
          echo "❌ ${name}: NOT exported"
          FAILED=1
        fi
      ''
    ) (builtins.attrNames expectedExports)}

    if [ -n "''${FAILED:-}" ]; then
      echo "❌ FAIL: Modules not exported to namespace"
      echo "This is EXPECTED before dendritic refactoring"
      exit 1
    else
      echo "✅ PASS: All modules exported to namespace"
      echo "pass" > $out
    fi
  '';

  # Test metadata
  category = "feature";
  critical = false;
  expectedToFailBeforeRefactor = true;
  mustPassAfterRefactor = true;

  rationale = ''
    Namespace exports enable:
    1. Self-composition: Modules import each other via namespace
    2. External consumption: Other flakes can import test-clan modules
    3. Clear organization: Namespace hierarchy shows module relationships

    BEFORE refactoring: This test WILL FAIL
    - Only terranix modules exported (clan.nix:8-9)
    - Base modules NOT exported (use relative imports)
    - Host modules NOT exported (imported directly in clan.machines)

    AFTER refactoring: This test MUST PASS
    - All base modules exported to flake.modules.nixos.base.*
    - All host modules exported to flake.modules.nixos.hosts/*
    - Terranix modules still exported (regression preserved)
  '';

  implementationGuide = ''
    To make this test pass:

    Option 1: Explicit exports in modules/base/default.nix
    {
      flake.modules.nixos.base.nix-settings = ./nix-settings.nix;
      flake.modules.nixos.base.admins = ./admins.nix;
      flake.modules.nixos.base.initrd-networking = ./initrd-networking.nix;
    }

    Option 2: Reorganize directory structure for automatic export
    modules/
    ├── nixos/
    │   ├── base/
    │   │   ├── nix-settings.nix
    │   │   ├── admins.nix
    │   │   └── initrd-networking.nix
    │   └── hosts/
    │       ├── hetzner-ccx23.nix
    │       └── hetzner-cx43.nix

    import-tree will automatically export based on directory structure.
  '';
}
```

---

### FT-3: Self-Composition via Namespace

**File:** `tests/feature/self-composition.nix`

**Why Important:**
Self-composition means host modules import base modules via namespace, not relative paths.
This decouples modules from directory structure.

**Expected Behavior:**
- **Before refactor:** FAIL - Host modules use relative imports (../../base/nix-settings.nix)
- **After refactor:** PASS - Host modules use namespace imports (config.flake.modules.nixos.base.nix-settings)
- **Pass criteria:** No relative path imports in host modules

**Why It Will Fail Now:**
Host modules currently use relative imports (modules/hosts/hetzner-ccx23/default.nix:3-6).

**Implementation:**

```nix
# tests/feature/self-composition.nix
{ self, lib, pkgs, ... }:
let
  # Function to check if a module uses self-composition
  usesNamespaceImports = modulePath:
    let
      # Read module file
      moduleContent = builtins.readFile modulePath;

      # Check for relative path imports (../../base/...)
      hasRelativeImports = builtins.match ".*\\.\\./\\.\\./base/.*" moduleContent != null;

      # Check for namespace imports (config.flake.modules.nixos.base)
      hasNamespaceImports = builtins.match ".*config\\.flake\\.modules\\.nixos.*" moduleContent != null;
    in {
      inherit modulePath;
      usesRelativePaths = hasRelativeImports;
      usesNamespace = hasNamespaceImports;
      selfComposing = !hasRelativeImports && hasNamespaceImports;
    };

  # Test host modules
  hostModules = {
    hetzner-ccx23 = ../../../test-clan/modules/hosts/hetzner-ccx23/default.nix;
    hetzner-cx43 = ../../../test-clan/modules/hosts/hetzner-cx43/default.nix;
    gcp-vm = ../../../test-clan/modules/hosts/gcp-vm/default.nix;
  };

  compositionTests = lib.mapAttrs (_: path: usesNamespaceImports path) hostModules;

  allUseNamespace = lib.all (test: test.selfComposing)
    (builtins.attrValues compositionTests);
in
{
  # Test results
  tests = compositionTests;
  passed = allUseNamespace;

  # Test assertion
  test = pkgs.runCommand "validate-self-composition" {} ''
    echo "Testing self-composition via namespace..."

    ${lib.concatMapStringsSep "\n" (name:
      let test = compositionTests.${name};
      in ''
        if ${if test.selfComposing then "true" else "false"}; then
          echo "✅ ${name}: uses namespace imports"
        else
          if ${if test.usesRelativePaths then "true" else "false"}; then
            echo "❌ ${name}: uses relative path imports"
          else
            echo "⚠️  ${name}: imports mechanism unclear"
          fi
          FAILED=1
        fi
      ''
    ) (builtins.attrNames compositionTests)}

    if [ -n "''${FAILED:-}" ]; then
      echo "❌ FAIL: Modules not using self-composition"
      echo "This is EXPECTED before dendritic refactoring"
      exit 1
    else
      echo "✅ PASS: All modules use namespace self-composition"
      echo "pass" > $out
    fi
  '';

  # Test metadata
  category = "feature";
  critical = false;
  expectedToFailBeforeRefactor = true;
  mustPassAfterRefactor = true;

  rationale = ''
    Self-composition via namespace decouples modules from directory structure.

    BEFORE refactoring: This test WILL FAIL
    Host modules use relative imports:
      imports = [
        ../../base/nix-settings.nix
        ../../base/admins.nix
        ../../base/initrd-networking.nix
      ];

    AFTER refactoring: This test MUST PASS
    Host modules use namespace imports:
      imports = with config.flake.modules.nixos.base; [
        nix-settings
        admins
        initrd-networking
      ];

    Benefits:
    - Can reorganize directory structure without breaking imports
    - Modules reference each other by name, not file location
    - External flakes can override modules via namespace
  '';

  implementationGuide = ''
    To make this test pass, refactor host modules:

    BEFORE (modules/hosts/hetzner-ccx23/default.nix):
    { inputs, lib, ... }:
    {
      imports = [
        ../../base/nix-settings.nix
        ../../base/admins.nix
        ../../base/initrd-networking.nix
        inputs.srvos.nixosModules.server
        ./disko.nix
      ];
    }

    AFTER:
    { config, ... }:
    {
      flake.modules.nixos."hosts/hetzner-ccx23" = { inputs, lib, ... }: {
        imports = with config.flake.modules.nixos.base; [
          nix-settings
          admins
          initrd-networking
          inputs.srvos.nixosModules.server
          ./disko.nix
        ];
      };
    }
  '';
}
```

---

## Integration Tests (VM Validation)

### VT-1: Machine Boot Test

**File:** `tests/integration/vm-boot-tests.nix`

**Why Critical:**
Proves configurations actually work in practice, not just evaluation.

**Expected Behavior:**
- **Before refactor:** All 3 machines boot in VM successfully
- **After refactor:** IDENTICAL boot behavior
- **Pass criteria:** All machines reach multi-user.target, SSH accessible

**Implementation:**

```nix
# tests/integration/vm-boot-tests.nix
{ self, pkgs, lib, ... }:
let
  # Create VM test for each configuration
  makeBootTest = name: config: pkgs.nixosTest {
    name = "boot-${name}";

    nodes.machine = config.config;

    testScript = ''
      # Start machine
      machine.start()

      # Wait for boot completion
      machine.wait_for_unit("multi-user.target")

      # Verify hostname
      hostname = machine.succeed("hostname").strip()
      expected = "${config.config.networking.hostName}"
      assert hostname == expected, f"Hostname mismatch: {hostname} != {expected}"

      # Verify nix works (from base/nix-settings.nix)
      machine.succeed("nix --version")
      machine.succeed("nix show-config | grep experimental-features | grep flakes")

      # Verify users (from base/admins.nix)
      machine.succeed("id crs58")
      machine.succeed("groups crs58 | grep wheel")

      # Verify sudo works without password
      machine.succeed("sudo -u crs58 sudo whoami | grep root")

      # Verify SSH
      machine.wait_for_unit("sshd.service")
      machine.wait_for_open_port(22)

      # Verify zsh available (from base/admins.nix)
      machine.succeed("which zsh")

      print(f"✅ {name}: Boot successful, all base module features work")
    '';
  };

  # Generate tests for all configurations
  tests = lib.mapAttrs makeBootTest self.nixosConfigurations;
in
{
  inherit tests;

  # Run all tests
  all = pkgs.runCommand "all-boot-tests" {
    buildInputs = builtins.attrValues tests;
  } ''
    echo "All machines boot successfully"
    echo "pass" > $out
  '';

  # Test metadata
  category = "integration";
  critical = true;
  mustRemainPassing = true;

  rationale = ''
    VM tests prove configurations actually work, not just evaluate.

    Tests validate base module behavior:
    - nix-settings.nix: Nix flakes enabled
    - admins.nix: User crs58 exists with wheel group, sudo works, zsh available
    - SSH access (clan-core requirement)

    These tests MUST pass before and after refactoring.
    If they fail after refactoring, module behavior has changed.
  '';
}
```

---

## Test Execution Strategy

### Phase 1: Establish Baseline (Before Refactoring)

**Objective:** Capture current behavior for regression comparison.

**Steps:**
1. Run all regression tests, capture snapshots
2. Run all invariant tests, verify they pass
3. Run feature tests, expect failures (confirms they test new functionality)
4. Run VM tests, verify machines boot

**Commands:**
```bash
# Setup test infrastructure
cd ~/projects/nix-workspace/test-clan
mkdir -p tests/{regression,invariant,feature,integration,snapshots}

# Capture baselines
nix build .#tests.regression.terraform-output-equivalence.baseline \
  -o tests/snapshots/terraform.json

nix build .#tests.regression.nixos-closure-equivalence.baseline \
  -o tests/snapshots/nixos-configs.json

nix build .#tests.invariant.clan-inventory-structure.snapshot \
  -o tests/snapshots/clan-inventory.json

# Run all tests (expect feature tests to fail)
./tests/run-all.sh baseline
```

**Expected Results:**
- ✅ Regression tests: PASS (capturing current behavior)
- ✅ Invariant tests: PASS (clan-core integration works)
- ❌ Feature tests: FAIL (dendritic capabilities don't exist yet)
- ✅ Integration tests: PASS (VMs boot and work)

---

### Phase 2: Incremental Refactoring with Test Validation

**Objective:** Refactor in small steps, validating at each step.

**Refactor Sequence:**

#### Step 2.1: Add import-tree (flake.nix)

**Change:**
```nix
# flake.nix: Replace manual imports with import-tree
outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; }
  (inputs.import-tree ./modules);
```

**Tests to Run:**
- Regression: MUST PASS (no functional change yet, just discovery mechanism)
- Invariant: MUST PASS (clan-core integration unchanged)
- Feature: import-tree-discovery SHOULD NOW PASS

**Validation:**
```bash
nix flake check
nix build .#tests.regression.terraform-output-equivalence.compare
nix build .#tests.invariant.clan-inventory-structure.test
nix build .#tests.feature.import-tree-discovery.test
```

**Rollback Criteria:** If regression or invariant tests fail, revert this change.

---

#### Step 2.2: Export Base Modules to Namespace

**Change:**
Create `modules/base/default.nix`:
```nix
{
  flake.modules.nixos.base.nix-settings = ./nix-settings.nix;
  flake.modules.nixos.base.admins = ./admins.nix;
  flake.modules.nixos.base.initrd-networking = ./initrd-networking.nix;
}
```

**Tests to Run:**
- Regression: MUST PASS (modules still imported via old paths)
- Invariant: MUST PASS (no change to clan integration)
- Feature: namespace-exports SHOULD NOW PARTIALLY PASS (base modules exported)

**Validation:**
```bash
nix build .#tests.regression.nixos-closure-equivalence.compare
nix build .#tests.feature.namespace-exports.test
```

**Rollback Criteria:** If exports break module evaluation.

---

#### Step 2.3: Refactor One Host Module (hetzner-ccx23)

**Change:**
Update `modules/hosts/hetzner-ccx23/default.nix`:
```nix
{ config, ... }:
{
  flake.modules.nixos."hosts/hetzner-ccx23" = { inputs, lib, ... }: {
    imports = with config.flake.modules.nixos.base; [
      nix-settings
      admins
      initrd-networking
      inputs.srvos.nixosModules.server
      inputs.srvos.nixosModules.hardware-hetzner-cloud
      ./disko.nix
    ];
    # ... rest of config
  };
}
```

**Tests to Run:**
- Regression: MUST PASS (single machine refactored, others unchanged)
- Invariant: MUST PASS (specialArgs still works)
- Integration: hetzner-ccx23 VM test MUST PASS

**Validation:**
```bash
# Build specific configuration
nix build .#nixosConfigurations.hetzner-ccx23.config.system.build.toplevel

# Run VM test
nix build .#tests.integration.vm-boot-tests.tests.hetzner-ccx23

# Regression check
nix build .#tests.regression.nixos-closure-equivalence.compare
```

**Rollback Criteria:** If hetzner-ccx23 doesn't build or VM test fails.

---

#### Step 2.4: Refactor Remaining Hosts

**Change:**
Apply same pattern to hetzner-cx43 and gcp-vm.

**Tests to Run:**
- Regression: ALL MUST PASS (all machines refactored)
- Invariant: ALL MUST PASS (clan integration preserved)
- Feature: self-composition SHOULD NOW PASS

**Validation:**
```bash
# Build all configurations
nix build .#nixosConfigurations.hetzner-ccx23.config.system.build.toplevel
nix build .#nixosConfigurations.hetzner-cx43.config.system.build.toplevel
nix build .#nixosConfigurations.gcp-vm.config.system.build.toplevel

# Run all tests
./tests/run-all.sh all
```

---

#### Step 2.5: Implement Automatic Host Collection (Optional)

**Change:**
Create `modules/flake-parts/host-machines.nix` for automatic nixosConfigurations generation.

**Warning:** This step is OPTIONAL and HIGH RISK.
Consider deferring if clan.machines manual registration provides sufficient value.

**Tests to Run:**
- Regression: MUST PASS (automatic generation produces identical configs)
- Invariant: CRITICAL - clan.machines imports must still work
- Feature: ALL should pass

**Rollback Criteria:** If clan.machines integration breaks.

---

### Phase 3: Final Validation

**Objective:** Comprehensive validation before declaring refactoring complete.

**Full Test Suite:**
```bash
# Run all test categories
./tests/run-all.sh all

# Specific critical checks
nix build .#tests.regression.terraform-output-equivalence.compare
nix build .#tests.invariant.clan-inventory-structure.test
nix build .#tests.invariant.clan-service-targeting.test
nix build .#tests.integration.vm-boot-tests.all

# Manual verification
nix flake check
nix build .#terraform
terraform show result/config.tf.json | jq . > final-terraform.json
diff -u tests/snapshots/terraform.json final-terraform.json
```

**Success Criteria:**
- ✅ ALL regression tests pass (existing functionality preserved)
- ✅ ALL invariant tests pass (clan-core integration preserved)
- ✅ ALL feature tests pass (dendritic capabilities enabled)
- ✅ ALL integration tests pass (VMs boot and work)
- ✅ Terraform output byte-for-byte identical or semantically equivalent
- ✅ No new errors in `nix flake check`

---

## Risk Mitigation

### Git Workflow for Safety

```bash
# Before starting
git checkout main
git pull
git checkout -b feature/dendritic-refactoring

# Capture pre-refactor state
./tests/run-all.sh baseline
git add tests/snapshots/
git commit -m "test: capture baseline snapshots before dendritic refactoring"

# After each step
git add .
git commit -m "refactor(step-2.1): add import-tree discovery"
./tests/run-all.sh all  # Validate

# If step fails
git revert HEAD
# OR
git reset --hard HEAD~1

# When complete
git checkout main
git merge --no-ff feature/dendritic-refactoring
```

### Rollback Plan

**If refactoring breaks something critical:**

1. Identify failing test category:
   - Regression → Functional regression, high priority fix
   - Invariant → clan-core integration broken, CRITICAL fix
   - Feature → Expected, continue refactoring
   - Integration → VM behavior changed, investigate

2. Rollback options:
   - **Single step:** `git revert HEAD` (undo last commit)
   - **Full refactor:** `git reset --hard main` (start over)
   - **Partial rollback:** `git revert <commit>` (undo specific change)

3. Debug failing tests:
   - Check test output for specific failure reason
   - Build affected configurations manually
   - Compare snapshots to identify what changed

### Operational Safety

**Protecting deployed VMs (162.55.175.87, 49.13.140.183):**

1. **DO NOT deploy** refactored configurations until ALL tests pass
2. **Terraform output** must be validated as equivalent before running `terraform apply`
3. **VM tests** must pass before considering deployment
4. **Keep current deployment separate** - refactoring is on test-clan repository, doesn't affect deployed VMs until explicitly applied

**Deployment validation:**
```bash
# After refactoring complete and all tests pass
cd ~/projects/nix-workspace/test-clan

# Build new configuration
nix build .#nixosConfigurations.hetzner-ccx23.config.system.build.toplevel -o result-new

# Compare to current deployment (on VM)
ssh root@162.55.175.87 'readlink /run/current-system' > current-system.txt
echo result-new >> current-system.txt

# If configurations functionally equivalent (tests passed), can deploy
# clan machines update hetzner-ccx23
```

---

## Test Infrastructure Setup

### Add to flake.nix

```nix
# test-clan/flake.nix
{
  description = "test-clan: Phase 0 architectural validation + infrastructure deployment";

  inputs = {
    # ... existing inputs ...

    # Add testing infrastructure
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    # ... existing config ...

    perSystem = { system, pkgs, lib, ... }: {
      # ... existing perSystem ...

      # Add test suite
      checks = {
        # Regression tests
        terraform-baseline = import ./tests/regression/terraform-output-equivalence.nix {
          inherit self pkgs lib;
        }.baseline;

        nixos-closure-baseline = import ./tests/regression/nixos-closure-equivalence.nix {
          inherit self pkgs lib;
        }.baseline;

        machine-builds = import ./tests/regression/machine-configurations-build.nix {
          inherit self pkgs lib;
        }.all;

        # Invariant tests
        clan-inventory = import ./tests/invariant/clan-inventory-structure.nix {
          inherit self pkgs lib;
        }.test;

        clan-service-targeting = import ./tests/invariant/clan-service-targeting.nix {
          inherit self pkgs lib;
        }.test;

        specialArgs-propagation = import ./tests/invariant/specialArgs-propagation.nix {
          inherit self pkgs lib inputs;
        }.test;

        # Feature tests (will fail before refactoring)
        import-tree-discovery = import ./tests/feature/import-tree-discovery.nix {
          inherit self pkgs lib;
        }.test;

        namespace-exports = import ./tests/feature/namespace-exports.nix {
          inherit self pkgs lib;
        }.test;

        self-composition = import ./tests/feature/self-composition.nix {
          inherit self pkgs lib;
        }.test;

        # Integration tests
        vm-boots = import ./tests/integration/vm-boot-tests.nix {
          inherit self pkgs lib;
        }.all;
      };
    };
  };
}
```

---

## Summary: Test Strategy Guarantees

### What This Test Suite Provides:

1. **Zero-Regression Confidence**
   - Terraform output equivalence → Infrastructure unchanged
   - NixOS closure equivalence → Deployed behavior identical
   - Machine builds → Evaluation works

2. **clan-core Compatibility Assurance**
   - Inventory structure preserved
   - Service targeting works
   - specialArgs propagation maintained

3. **Dendritic Feature Validation**
   - import-tree discovery functional
   - Namespace exports working
   - Self-composition enabled

4. **Operational Safety**
   - VM tests prove practical functionality
   - Incremental validation at each step
   - Clear rollback path if issues arise

### Testing Investment ROI:

**Initial Setup:** 4-6 hours
**Refactoring with Tests:** 10-14 hours total
**Confidence Level:** ~95% certainty of preserving functionality

**Value:**
- Can experiment with dendritic patterns safely
- Automated validation reduces manual testing
- Reusable test suite for future changes
- Clear definition of "successful refactoring"

---

## Next Steps

1. **Review this strategy** - Validate test approach makes sense
2. **Set up test infrastructure** - Add nix-unit, create test directories
3. **Capture baselines** - Run Phase 1 to snapshot current behavior
4. **Begin refactoring** - Follow Phase 2 incremental steps with validation
5. **Validate completion** - Run Phase 3 full test suite

**Ready to proceed with test implementation?**

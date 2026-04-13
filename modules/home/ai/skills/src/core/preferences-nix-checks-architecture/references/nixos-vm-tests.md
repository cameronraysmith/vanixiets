# NixOS VM tests

NixOS VM tests run full virtual machines with real init systems, network stacks, and disk layouts to validate system-level behavior that cannot be tested in pure derivations.
This reference covers the framework architecture, driver API, multi-machine patterns, debugging techniques, and clan-core extensions.

## Architecture

The NixOS test framework transforms a test definition into a runnable derivation through a 6-stage pipeline.

### Entry point

`runNixOSTest` (or the legacy `nixosTest`) accepts a test definition containing `nodes` (machine configurations), `testScript` (Python code), and optional metadata.
`runNixOSTest` is the preferred entry point as it provides better error messages and supports the `class = "nixosTest"` module system.

```nix
checks.mytest = pkgs.testers.runNixOSTest {
  name = "mytest";

  nodes = {
    server = { config, pkgs, ... }: {
      services.nginx.enable = true;
      networking.firewall.allowedTCPPorts = [ 80 ];
    };
    client = { config, pkgs, ... }: {
      # minimal client config
    };
  };

  testScript = ''
    start_all()
    server.wait_for_unit("nginx.service")
    server.wait_for_open_port(80)
    client.succeed("curl -f http://server")
  '';
};
```

### Module evaluation

`lib.evalModules` with `class = "nixosTest"` evaluates the test definition.
Each node gets its own NixOS module evaluation with the `test-instrumentation.nix` module injected.
This module configures the backdoor service, sets panic-on-OOM, uses a deterministic clock, and disables network gateways for isolation.

### Node VM derivations

`qemu-vm.nix` produces a QEMU virtual machine derivation for each node.
Each VM gets a virtio-serial device connected to a UNIX domain socket for the backdoor channel.
The VM boots with a minimal kernel configuration optimized for test speed: no unnecessary modules, small memory footprint, and fast boot parameters.

### Driver construction

`driver.nix` wraps all node VMs and the test script into the `nixos-test-driver` derivation.
The driver is a Python program that manages VM lifecycle, network setup, and test execution.
VLANs are created using `vde_switch` instances managed by the `VLan` class.

### Test derivation

`run.nix` produces the final test derivation.
This derivation requires two sandbox features: `kvm` for hardware-accelerated virtualization and `nixos-test` for the test framework's special sandbox permissions.
The derivation runs the driver, which boots the VMs, executes the test script, and produces a result directory.

### Python driver runtime

At runtime, the driver creates QEMU virtual machine processes connected via virtio-serial sockets.
Each `QemuMachine` object manages one VM's lifecycle and communicates with it through the backdoor socket.
Network connectivity between VMs uses `vde_switch` instances that simulate Ethernet segments.


## The virtio-console backdoor

The backdoor is the primary mechanism for test interaction with VMs.
`test-instrumentation.nix` configures a systemd service that opens `/dev/hvc0` (the first virtio console) and connects it to a root shell.
The Python driver connects to the corresponding UNIX socket on the host side.

All driver commands (`succeed()`, `fail()`, `execute()`) send shell commands through this channel and read back stdout, stderr, and the exit code.
The backdoor bypasses the VM's network stack entirely, so commands work even when networking is misconfigured or unavailable.

This channel is also used for file transfer between the host and guest.
The driver can copy files into the VM for test fixtures and extract files (logs, screenshots) from the VM for test output.


## Python test driver API

The driver provides methods on each machine object and global functions for test orchestration.

`start_all()` boots all defined VMs in parallel and waits for them to reach multi-user target.
Individual machines can be started with `machine.start()`.

`machine.succeed(command)` executes a shell command in the VM and asserts a zero exit code.
Returns stdout.
Multiple commands can be chained with semicolons.

`machine.fail(command)` executes a command and asserts a non-zero exit code.
Useful for testing that unauthorized access is denied or that invalid configurations are rejected.

`machine.wait_for_unit(unit)` blocks until the named systemd unit reaches active state.
This is the standard way to wait for services to be ready after boot.

`machine.wait_for_open_port(port)` polls until a TCP connection to the specified port succeeds.
Combines with `wait_for_unit` for services that need time after unit activation to bind their port.

`machine.screenshot(name)` captures the VM's framebuffer as a PNG image.
Useful for debugging graphical applications or capturing error screens.

`machine.get_screen_text()` runs OCR on the current framebuffer content.
Useful for asserting on text displayed in a console or graphical interface without using the backdoor.

`machine.send_key(key)` sends a keyboard input to the VM.
Useful for interacting with boot menus, login prompts, or graphical applications.

`subtest(name, function)` groups assertions into a named section for structured test output.
Subtests appear in the test log with their name, making failures easier to locate.

`retry(function, timeout=N)` retries a function until it succeeds or the timeout expires.
Useful for assertions on eventually-consistent state.


## Multi-machine patterns

Tests can define multiple nodes that communicate over virtual networks.
Each node is a fully independent NixOS VM with its own configuration.

VLANs connect nodes into network segments.
The `vlans` attribute on a node configuration specifies which VLANs the machine is connected to.
Multiple VLANs allow testing network segmentation, routing, and firewall rules.

```nix
nodes = {
  router = { config, ... }: {
    virtualisation.vlans = [ 1 2 ];
    networking.nat = {
      enable = true;
      internalInterfaces = [ "eth2" ];
      externalInterface = "eth1";
    };
  };
  internal = { config, ... }: {
    virtualisation.vlans = [ 2 ];
  };
  external = { config, ... }: {
    virtualisation.vlans = [ 1 ];
  };
};
```

The nixpkgs test suite contains extensive multi-machine examples.
The WireGuard test uses 5 nodes with multiple VLANs to validate mesh networking, including key exchange, peer discovery, and routing through intermediate nodes.
The borgbackup test uses a client/server topology to validate backup creation, repository initialization, and restore workflows.
The data-mesher test validates distributed system behavior across multiple nodes, exercising consensus and replication.

Machine names in the test definition become Python variables in the test script.
A node named `server` in the `nodes` attribute set becomes a `server` object in the test script with the full driver API available.
Naming machines descriptively (e.g., `coordinator`, `worker1`, `worker2` rather than `machine1`, `machine2`, `machine3`) makes test scripts more readable.

Network addressing follows a convention: each VLAN is a `/24` network, and machines receive addresses based on their definition order within that VLAN.
The first machine on VLAN 1 gets `192.168.1.1`, the second gets `192.168.1.2`, and so on.
The `networking.interfaces` module configures these addresses automatically based on the `vlans` attribute.


## Resource requirements

VM tests require specific sandbox features and hardware capabilities.

`kvm` provides hardware-accelerated virtualization.
On Linux, this requires access to `/dev/kvm` (Intel VT-x or AMD-V).
On macOS, QEMU uses HVF (Hypervisor.framework) for acceleration.
Without hardware acceleration, VM tests are prohibitively slow.

`nixos-test` grants the test framework special sandbox permissions needed for VDE switch creation and QEMU device management.

Both features must be enabled in the nix daemon configuration:

```nix
nix.settings.system-features = [ "kvm" "nixos-test" ];
```

`test-instrumentation.nix` configures several isolation and reliability measures.
Panic-on-OOM forces an immediate kernel panic rather than allowing the OOM killer to make unpredictable choices.
A deterministic clock prevents timing-dependent test flakiness.
Network gateway removal ensures VMs communicate only through defined VLANs, preventing accidental internet access.

Memory allocation defaults to 1024 MB per VM.
Tests with multiple large nodes can consume significant host memory.
The `virtualisation.memorySize` option adjusts per-VM allocation.
Similarly, `virtualisation.diskSize` controls the root filesystem size, and `virtualisation.cores` sets the number of virtual CPUs.

For tests that require additional disk space (e.g., testing backup systems or large data processing), `virtualisation.emptyDiskImages` creates additional virtual disks attached to the VM.
These disks can be partitioned and mounted within the test script.


## clan-core wrappers

clan-core extends the NixOS test framework with several utilities that simplify test authoring and reduce resource consumption.

### Shared test runner

`clan-nixos-test.nix` provides a shared test runner that integrates with clan's module system.
Tests defined through this runner automatically get clan-specific module imports (inventory, vars, networking) and can test multi-machine clan deployments.

### Container test driver

The container test driver uses systemd-nspawn instead of QEMU for lighter-weight testing.
Container tests boot faster and use less memory than VM tests because they share the host kernel.
The tradeoff is that container tests cannot validate kernel-level behavior, custom kernel modules, or boot sequences.

Container tests are appropriate for service-level integration testing where the kernel is not under test.

### Utilities

`minify.nix` reduces VM image size by stripping unnecessary components.
This speeds up VM creation and reduces disk I/O during tests.

`age.nix` and `sops.nix` provide test helpers for secrets management.
They configure test keys and decryption in the VM environment so that services requiring secrets can be tested without real secret material.

`mkEvalCheck.nix` produces evaluation-only checks that validate NixOS module configuration without building or booting a VM.
These catch type errors and infinite recursion in module definitions at minimal cost.

### flake-module wiring

`flake-module.nix` in clan-core's checks directory demonstrates how to expose VM tests as flake checks.
The module iterates over test definitions and produces `checks.<system>.<test-name>` attributes that `nix flake check` evaluates.


## Hermetic test debugging

Debugging failures in hermetic (sandboxed) VM tests requires specific techniques because the test environment has no network access.
The following patterns are sourced from Mic92's clan blog post "Debugging Offline Nix Builds" (2026-01-29).

### closureInfo for pre-populating the nix store

When a test needs nix store paths inside the sandbox (for example, testing `nix build` within a VM), `closureInfo` computes the full closure of those paths.
The `rootPaths` attribute specifies which store paths to include.

Missing a single dependency in `rootPaths` causes a cascading failure: the sandboxed test attempts to fetch the missing path, fails because there is no network, and the build error is often confusing because it manifests as a download failure rather than a missing input.

### Diagnostic technique

`nix build --dry-run` on the test derivation reports "paths to be fetched from substituters."
This list identifies store paths that the sandbox expects to download, which will fail in a hermetic build.
Each path in this list must be added to `rootPaths` or produced by a build step within the sandbox.

### The `.drvPath` footgun

Including a derivation's `.drvPath` in the test closure pulls in the full build-time closure of that derivation: all source code, compilers, and build tools.
This makes VM startup slow and wastes bandwidth fetching build tools that the test does not need.
Use `.drvPath` sparingly and only when the test genuinely needs to build something inside the sandbox.

### Interactive VM debugging

Building the test driver without running the test:

```bash
nix build .#checks.x86_64-linux.mytest.driver
./result/bin/nixos-test-driver
```

The driver runs outside the nix sandbox, so it has full network access.
VMs started in this mode can download packages, access the internet, and be inspected interactively.
This is useful for exploring failures that are difficult to diagnose from test output alone.

The interactive driver drops into a Python REPL where machine objects are available.
You can manually call `server.succeed("systemctl status nginx")` to inspect service state, `server.screenshot("debug")` to capture the screen, or `server.shell_interact()` to get a direct shell into the VM.
This interactive debugging loop is the most effective way to understand why a test assertion fails, because you can inspect the full system state at the point of failure.

The `--keep-machine-state` flag preserves VM disk images between runs.
This is useful when debugging tests that depend on state accumulated over multiple boot cycles, such as database migration tests or persistent storage tests.

### Container test debugging

For container-based tests, `wait_for_signal()` pauses the test execution at a specific point.
While paused, `inject_network.py` creates a veth pair and uses nsenter to inject network connectivity into the sandbox namespace.
With network injected, `nix build --dry-run` can be run inside the sandbox to identify missing store paths.


## Reference paths

### nixpkgs

The test framework implementation lives in several key locations within the nixpkgs repository.

`nixos/lib/testing/` contains the core framework modules: `run.nix` (test derivation), `driver.nix` (driver construction), `nodes.nix` (VM derivation generation).

`nixos/modules/virtualisation/qemu-vm.nix` defines the QEMU VM module that produces bootable VM derivations with virtio devices, disk images, and kernel configuration.

`nixos/lib/test-driver/` contains the Python driver source code with the `Machine`, `VLan`, and test script execution logic.

`nixos/doc/manual/development/writing-nixos-tests.section.md` is the official documentation for writing NixOS tests, maintained alongside the framework source.

### clan-core

`lib/flake-parts/clan-nixos-test.nix` provides the shared test runner and clan-specific module integration.

`lib/test/` contains test utilities, container driver, minification, and secrets helpers.

`checks/flake-module.nix` demonstrates the pattern for wiring VM tests into flake checks output.


## Choosing between VM tests and pure derivation checks

VM tests are the right tool when validation requires a running operating system.
The following properties require VM tests: systemd service activation ordering, firewall and network configuration, multi-machine communication, secrets decryption during system activation, disk layout and mount point configuration, and boot sequence behavior.

Pure derivation checks are sufficient and preferred for: library function correctness, CLI tool output, data transformation logic, type checking, formatting, linting, and any validation that can run in a single-process sandbox.

The cost differential is significant.
A pure derivation check might take seconds to build and produces a small, cacheable output.
A VM test takes tens of seconds to minutes, requires KVM acceleration, and produces a larger result directory.
When designing a test suite, start with pure derivation checks and add VM tests only for properties that genuinely require system-level validation.

Container-based tests (via clan-core's nspawn driver) occupy a middle ground.
They boot faster and use less memory than QEMU-based VM tests, but share the host kernel, which means they cannot test kernel-level behavior.
Container tests are appropriate for service-level integration testing: verifying that systemd units start, ports bind, and services respond to requests, without needing custom kernel modules or network namespace isolation beyond what nspawn provides.

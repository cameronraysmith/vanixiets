# Nix-native effects

This reference documents the effect system used by buildbot-nix, derived from the hercules-ci-effects library.
It covers the `mkEffect` and `modularEffect` APIs, the bubblewrap execution environment, secret injection, common effect types, the `runIf` gating pattern, flake-parts integration, the `herculesCI` flake output interface, and local testing.


## `mkEffect` API

`mkEffect` wraps `stdenvNoCC.mkDerivation` with effect-specific behavior.
The resulting derivation has `isEffect = true` in its passthru attributes, which buildbot-nix uses to distinguish effects from regular derivations during post-build discovery.

The derivation's build phases follow a structured lifecycle:

1. `initPhase` sets up the effect environment (working directory, environment variables, secrets access).
2. `unpackPhase` unpacks any source inputs.
3. `patchPhase` applies patches to unpacked sources.
4. `getStatePhase` retrieves persistent state from a previous effect run (for stateful effects like deployment tracking).
5. `userSetupPhase` executes user-defined setup commands (installing additional tools, configuring credentials).
6. `effectPhase` executes the primary effect logic (the deploy command, the publish script, the notification).
7. `putStatePhase` persists state for future effect runs.

The `effectSetupHook` added by `mkEffect` provides bash helper functions for secret access (documented below) and sets up the environment variables that effects expect.

`mkEffect` accepts all standard `mkDerivation` arguments plus:

- `secretsMap` (attrset): maps logical secret names to agent-side secret keys
- `effectScript` (string): convenience alias for setting `effectPhase` directly
- `inputs` (list): additional build inputs available during effect execution
- `userSetupPhase` (string): commands to run after init but before the effect


## `modularEffect` API

`modularEffect` wraps `mkEffect` in the NixOS module system via `lib.evalModules`.
This provides typed options, composable configuration, and option documentation for effect parameters.

```nix
modularEffect {
  imports = [ ./deploy-module.nix ];
  ssh.destination = "root@cinnabar.zerotier";
  deploy.profile = config.system.build.toplevel;
}
```

Module authors define options with `lib.mkOption` and implement them by producing `mkEffect` arguments.
The module system handles type checking, default values, and option merging, which is useful for complex effects with many configuration parameters.


## Bubblewrap execution environment

buildbot-nix executes effects in a bubblewrap (`bwrap`) sandbox.
The sandbox provides namespace isolation while granting the network and nix daemon access that effects require.

The bwrap invocation uses:

- `--unshare-all --share-net`: new namespaces for pid, mount, user, ipc, uts, and cgroup, but the network namespace is shared with the host. Effects can make network connections (SSH, HTTP, registry pushes).
- `--ro-bind /nix/store /nix/store`: the nix store is available read-only. Effects can reference store paths but cannot modify the store directly.
- `--bind /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket`: the nix daemon socket is accessible. Effects can invoke `nix build`, `nix copy`, and `nix-copy-closure` inside the sandbox.
- `--uid 0 --gid 0`: the process runs as root inside the user namespace. This is necessary for effects that invoke system-level commands (e.g., `switch-to-configuration`).
- `--hostname hercules-ci`: the hostname is set for compatibility with scripts that check `$HOSTNAME` for environment detection.

Environment variables set inside the sandbox:

- `IN_HERCULES_CI_EFFECT=true`: signals to scripts that they are running inside an effect sandbox.
- `HERCULES_CI_SECRETS_JSON=/run/secrets.json`: path to the mounted secrets file.

The sandbox does not provide persistent storage between effect runs.
State persistence uses the `getStatePhase`/`putStatePhase` mechanism, which stores state in the buildbot master's database.


## Secret injection patterns

Secrets are provided to effects via JSON files mounted at the path specified by `HERCULES_CI_SECRETS_JSON`.

The `secretsMap` attribute in the nix effect definition maps logical names to agent-side secret keys:

```nix
mkEffect {
  secretsMap = {
    deploy-ssh = "deploy-ssh-key";
    registry-token = "docker-registry-token";
  };
  effectScript = ''
    writeSSHKey deploy-ssh
    readSecretString registry-token .token | docker login --password-stdin
    # ... deployment commands
  '';
}
```

Bash helper functions provided by the `effectSetupHook`:

- `readSecretString secretName jqPath` extracts a string value from the secrets JSON. The `jqPath` argument is a jq expression applied to the secret's value (e.g., `.token`, `.password`, `.["api-key"]`).
- `readSecretJSON secretName` extracts the full JSON value of a secret, useful when a secret contains structured data.
- `writeSSHKey secretName` writes the secret's private key to `~/.ssh/` with appropriate permissions and adds it to the SSH agent.
- `writeAWSSecret secretName` writes AWS credentials to `~/.aws/credentials`.
- `writeDockerKey secretName` configures Docker authentication for a registry.
- `writeGPGKey secretName` imports a GPG private key into the keyring.

The `git-auth` module provides a higher-level abstraction for git authentication.
It injects a token into `~/.git-credentials`, making git operations (clone, push) work without manual credential setup:

```nix
modularEffect {
  imports = [ hercules-ci-effects.modules.git-auth ];
  git.checkout.remote.url = "https://github.com/org/repo.git";
  secretsMap.git-token = "github-token";
}
```


## Common effect types

### `runNixOS` and `runNixDarwin`

SSH-based deployment effects that activate a NixOS or nix-darwin system configuration on a remote machine.
The effect builds the system closure (or uses `buildOnDestination = true` to build on the target), copies it to the target via `nix-copy-closure`, and runs `switch-to-configuration switch`.

```nix
effects.deploy-cinnabar = runNixOS {
  ssh.destination = "root@cinnabar.zerotier";
  system = self.nixosConfigurations.cinnabar.config.system.build.toplevel;
  secretsMap.ssh = "deploy-ssh-key";
};
```

`buildOnDestination` (boolean, default `false`) offloads the build to the target machine.
This is useful when the target has hardware-specific features (GPU, specific CPU extensions) that the buildbot worker lacks.

### `flakeUpdate`

Scheduled flake.lock update with PR creation.
Evaluates the flake with updated inputs, creates a branch with the lock update, and opens a PR.
Typically used with `onSchedule` for weekly or daily updates.

### `cargoPublish`

Publishes Rust crates to crates.io.
Handles authentication via `secretsMap`, supports workspace-aware publishing order (dependencies before dependents), and dry-run validation.

### `netlifyDeploy`

Deploys a site to Netlify.
Takes a directory of static files and a Netlify site ID.
Supports deploy previews on PRs and production deploys on the default branch.

### `gitWriteBranch`

Writes content to a git branch.
The canonical use case is GitHub Pages: build the site as a nix derivation, then write the output to the `gh-pages` branch.

### `runPutUrl`

Simple HTTP PUT upload.
Takes a file and a URL.
Useful for artifact publishing to S3-compatible storage, Artifactory, or custom endpoints.

### `ssh`

Low-level SSH effect providing `nix-copy-closure` and arbitrary command execution on a remote host.
`runNixOS` and `runNixDarwin` are built on top of this.


## The `runIf` gating pattern

`runIf condition effect` is the mechanism for conditional effect execution with the "verify even when gated off" property.

When `condition` evaluates to `true`, the effect is returned unmodified.
buildbot-nix discovers and executes it normally.

When `condition` evaluates to `false`, the effect's `inputDerivation` is returned with two passthru overrides: `isEffect = false` (so buildbot-nix does not execute it) and `buildDependenciesOnly = true`.
The `inputDerivation` attribute of a derivation represents its full build-dependency closure without the derivation's own build.
By exposing this as a non-effect, buildbot-nix builds the entire dependency closure, verifying that the deployment *would* succeed, without executing the side-effecting operation.

The `prebuilt` passthru attribute is preserved regardless of the condition.
This makes the built artifacts accessible even when the effect is gated off.

Typical usage gates deployment on branch identity:

```nix
effects.deploy = runIf
  (herculesCI.config.repo.branch == "main")
  (runNixOS {
    ssh.destination = "root@cinnabar.zerotier";
    system = config.system.build.toplevel;
  });
```

On a pull request, `branch` is not `"main"`, so the deployment does not execute.
But the NixOS system closure is still built and cached, catching configuration errors before merge.


## Flake-parts integration

The `hercules-ci-effects` library provides a flake-parts module that simplifies effect definition in `perSystem` and top-level flake contexts.

Import the module:

```nix
imports = [ hercules-ci-effects.flakeModule ];
```

This provides:

- `hci-effects` as a `perSystem` module argument, instantiated with the system's `pkgs`. Replaces the need to manually call `hercules-ci-effects.lib.mkEffect` with the correct `pkgs`.
- `herculesCI` option on the top-level flake module, which becomes the `flake.herculesCI` function output.
- `defaultEffectSystem` option (string, e.g., `"x86_64-linux"`) specifying which system's effects are evaluated.

Higher-level options provided by the module:

- `hercules-ci.github-pages` configures a GitHub Pages deployment effect with a single option pointing to the site derivation.
- `hercules-ci.github-releases` configures artifact upload to GitHub Releases.
- `hercules-ci.flake-update` configures scheduled flake.lock updates with PR creation.

These higher-level options compose the underlying `mkEffect` calls with appropriate secret mappings and gating logic.


## The `herculesCI` flake output interface

The `herculesCI` flake output is a function (not a plain attribute set) called by the agent (or buildbot-nix) with context about the repository:

```nix
herculesCI = { primaryRepo, herculesCI, ... }: {
  onPush.default.outputs = {
    checks = self'.checks;
    effects = { ... };
  };
  onSchedule.update-flake = {
    when = {
      hour = [ 4 ];
      dayOfWeek = [ "Mon" ];
    };
    outputs = { ... };
  };
  ciSystems = [ "x86_64-linux" "aarch64-linux" ];
};
```

The function argument provides:

- `primaryRepo.ref`: the git ref (e.g., `"refs/heads/main"`)
- `primaryRepo.branch`: the branch name (e.g., `"main"`, or `null` for tag pushes)
- `primaryRepo.tag`: the tag name (or `null` for branch pushes)
- `primaryRepo.rev`: the git revision (commit hash)
- `primaryRepo.remoteHttpUrl`: the repository's HTTP URL

`onPush.<job>.outputs` defines what to build and which effects to run on push events.
`onSchedule.<job>` defines scheduled operations with `when` (cron-like schedule) and `outputs` (what to build/run).
`ciSystems` restricts which systems are evaluated (overrides the default of all systems in the flake).

buildbot-nix looks for the `herculesCI` output first.
If absent, it falls back to looking for an `effects` output directly.
The `herculesCI` interface is preferred because it provides the full context (branch, tag, forge type) that effects use for gating decisions.


## Local testing

The `buildbot-effects run` CLI command executes effects locally in the same bubblewrap sandbox used by buildbot-nix.
This allows validating effect scripts before pushing, catching issues like missing dependencies, incorrect secret references, and broken deployment logic.

```bash
buildbot-effects run \
  --secrets ./local-secrets.json \
  .#herculesCI.onPush.default.outputs.effects.deploy-cinnabar
```

The `--secrets` flag provides a local secrets JSON file with the same structure as the agent-side secrets.
Secret values for local testing can be dummy values (for dry-run effects) or real credentials (for testing against staging environments).

The local sandbox uses the same bwrap flags as the server, so effects that work locally will work on the buildbot worker.
The exception is network-dependent effects: the local machine may have different network access (VPN, firewall rules) than the buildbot worker.


## Reference repositories

`~/projects/nix-workspace/buildbot-nix` contains the buildbot-nix source, including the effect runner, the NixOS modules for master and worker, the GitHub and Gitea forge backends, and the `buildbot-effects` CLI.
The `GITHUB.md` file documents the GitHub App setup procedure.

`~/projects/nix-workspace/hercules-ci-effects` contains the upstream effect library: `mkEffect`, `modularEffect`, all common effect types (`runNixOS`, `runNixDarwin`, `flakeUpdate`, etc.), the flake-parts module, and the `secretsMap` infrastructure.
The `effects/` directory contains the implementation of each effect type.
The `flake-module.nix` file contains the flake-parts integration.

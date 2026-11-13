## MODIFIED Requirements

### Requirement: The signer principal is the author address

Each human profile's `allowed_signers` content SHALL use `config.vcs.author.email` as its principal, and its public keys SHALL be that profile's `meta.signingKey` and the entries of its `meta.retiredSigningKeys`, rendered by `flake.lib.allowedSigners`.
Each Omnigent worker's `allowed_signers` principal SHALL remain `credentials.expected.gitEmail`, and `credentials.expected.gitEmail` SHALL equal the worker home's `vcs.author.email`.

#### Scenario: Janette's human signers file is rendered

- **WHEN** `xdg.configFile."git/allowed_signers".text` is evaluated for `homeConfigurations."janettesmith@x86_64-linux"`
- **THEN** its first line is `125711642+janetteasmith@users.noreply.github.com namespaces="git"` followed by `flake.users.janettesmith.meta.signingKey`

#### Scenario: A worker's expected email drifts from its author

- **WHEN** a worker's `credentials.expected.gitEmail` differs from its home's `vcs.author.email`
- **THEN** the `authorBinding` fleet obligation fails on that worker's machine check, and the `authorBoundExpectedDrift` case of `checks.x86_64-linux.omnigent-worker-inventory` shows `authorBound` fails for that shape

### Requirement: A worker's author is its owner's profile, set by the host

The NixOS and Darwin Omnigent adapters SHALL set each worker home's `vcs.author` to `flake.lib.vcsAuthor flake.users.${worker.owner}.meta`, computed at system level, so that the worker home receives two non-secret strings and never reads `flake.users`.
The inventory's worker credentials SHALL derive `expected` from `flake.users.${owner}.meta`, keeping `expected.gitEmail = meta.gitEmail`, `expected.signingPublicKey = meta.signingKey` and `expected.omnigentEmail = meta.email`.
`modules/home/ai/omnigent/credentials.nix` SHALL NOT set `user.email` or `user.name` for git or jj, and the inventory SHALL NOT pass author settings through `extraHomeModules`.

#### Scenario: A worker home is evaluated with a throwing user set

- **WHEN** `checks.<system>.omnigent-worker-capabilities` evaluates a worker home whose `flake` special argument makes `users` throw, with `vcs.author` set by the fixture
- **THEN** evaluation succeeds, showing that nothing in the worker home forces `flake.users`

#### Scenario: Cameron's worker on magnetite is evaluated

- **WHEN** `nixosConfigurations.magnetite.config.home-manager.users.omnigent-cameron.programs.{git,jujutsu}.settings.user` is evaluated
- **THEN** both are `{ name = "Cameron Smith"; email = "cameron.ray.smith@gmail.com"; }`

#### Scenario: Cameron's worker's declared signing key is evaluated

- **WHEN** `nixosConfigurations.magnetite.config.services.omnigent-host.workers.cameron.credentials.expected.signingPublicKey` is evaluated
- **THEN** it equals `flake.users.cameron.meta.signingKey` and is not `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+`

#### Scenario: A worker without a delivered signing key

- **WHEN** a worker's credentials enable no signing key
- **THEN** its home's git and jj `user.email` still equal its owner's author address

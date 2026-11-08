## ADDED Requirements

### Requirement: The author interface's trust boundary is evaluated and delivered configuration

The properties in this capability SHALL be read as holding of evaluated NixOS, nix-darwin and home-manager configurations and of the files activation delivers from them, and of nothing beyond that boundary.
They SHALL NOT be cited as establishing that a person's recorded name or address is correct, that a forge accepts the address, that a configuration has been deployed to a given host, that no repository-local or environment author setting overrides the delivered one (assumption A85), or that commits recorded before delivery carry a non-empty author (assumption A84).
stibnite's Omnigent worker home is a standalone home-manager generation that `checks.aarch64-darwin.darwin-stibnite` cannot read, so its author SHALL be claimed only through the shared `vcs-author` module and adapter code that the Linux workers' checks exercise.
That no module other than `vcs-author` sets a human home's git or jj `user` is a review convention that no check verifies, and SHALL NOT be cited as checked.

#### Scenario: A delivered author is claimed from evaluation alone

- **WHEN** a review cites a passing `checks.x86_64-linux.nixos-magnetite` as evidence that the omnigent-cameron account on magnetite records commits as `Cameron Smith`
- **THEN** the citation is incomplete until the delivered `~/.config/jj/config.toml` and `git config --global user.name` of that account are read after magnetite's activation, and until no repository-local `user.name` remains in the checkout used

### Requirement: One rule derives an author from a profile

`flake.lib.vcsAuthor` SHALL be the function `meta: { name = meta.fullname; email = meta.gitEmail; }` over a `flake.users.<key>.meta` record, and every git and jj author the fleet configures SHALL be computed by it.
`meta.gitEmail` SHALL keep its default of `meta.email`.

#### Scenario: The author address differs from the primary address

- **WHEN** `flake.lib.vcsAuthor` is applied to a meta fixture with `fullname = "Fixture"`, `email = "primary@example.invalid"` and `gitEmail = "author@example.invalid"`
- **THEN** it returns `{ name = "Fixture"; email = "author@example.invalid"; }`, and a variant returning `primary@example.invalid` fails the `omnigent-worker-inventory` case that asserts this literal

#### Scenario: Janette's profile is projected

- **WHEN** `nix eval --impure --json --expr "let f = builtins.getFlake \"git+file://$PWD\"; in f.lib.vcsAuthor f.users.janettesmith.meta"` is run at the repository root
- **THEN** the result is `{ email = "125711642+janetteasmith@users.noreply.github.com"; name = "Janette Smith"; }`

### Requirement: Every home sets git and jj author from one non-empty pair

`flake.modules.homeManager.vcs-author` SHALL declare `vcs.author.name` and `vcs.author.email`, each of type `nonEmptyStr`, and SHALL set both `programs.git.settings.user` and `programs.jujutsu.settings.user` to exactly that pair.
Each option's default SHALL be the corresponding field of `flake.lib.vcsAuthor flake.users.${config.home.username}.meta`, read through the home-manager `flake` special argument.
The `development` aggregate and `flake.modules.homeManager.omnigent-worker` SHALL import it.
No other module SHALL set `user.name` or `user.email` in `programs.git.settings` or `programs.jujutsu.settings` for a fleet account; for human homes this is a review convention that no check verifies, while worker homes are regulated by `authorBinding`.
A second definition differing without `mkForce` would fail evaluation with a conflicting-definition error, but that is a property of the nixpkgs module system, so no fixture in this repository asserts it.
`vcs-author` SHALL NOT set any `signing` option.

#### Scenario: Every home configuration is evaluated

- **WHEN** `programs.git.settings.user` and `programs.jujutsu.settings.user` are evaluated for every `homeConfigurations` entry
- **THEN** in each entry the two are equal, their `name` is non-empty, and they equal `flake.lib.vcsAuthor` of that entry's user's meta, including `raquel`, `tara`, `christophersmith`, `ubuntu` and `janettesmith`, whose jj `user.name` evaluated to the empty string before this change

#### Scenario: A profile's name is empty

- **WHEN** a `flake.users.<key>.meta.fullname` is set to `""` and that user's home configuration is evaluated
- **THEN** evaluation fails with a type error naming `vcs.author.name`, so `checks.<system>.home-manager-<key>` for that user fails

### Requirement: The signer principal is the author address

Each human profile's `allowed_signers` content SHALL use `config.vcs.author.email` as its principal, while the source of its public key stays per profile (a sops placeholder, or ubuntu's literal key).
Each Omnigent worker's `allowed_signers` principal SHALL remain `credentials.expected.gitEmail`, and `credentials.expected.gitEmail` SHALL equal the worker home's `vcs.author.email`.

#### Scenario: Janette's human signers file is rendered

- **WHEN** `sops.templates.allowed_signers.content` is evaluated for `homeConfigurations."janettesmith@x86_64-linux"`
- **THEN** its line begins `125711642+janetteasmith@users.noreply.github.com namespaces="git"`

#### Scenario: A worker's expected email drifts from its author

- **WHEN** a worker's `credentials.expected.gitEmail` differs from its home's `vcs.author.email`
- **THEN** the `authorBinding` fleet obligation fails on that worker's machine check, and the `authorBoundExpectedDrift` case of `checks.x86_64-linux.omnigent-worker-inventory` shows `authorBound` fails for that shape

### Requirement: A worker's owner is a profile key

`services.omnigent-host.workers.<name>.owner` in `modules/system/omnigent-worker-options.nix`, and `workers.<name>.owner` in the omnigent clan service's host role interface, SHALL have type `enum (attrNames config.flake.users)`.
The clan host settings SHALL remain JSON-serializable and SHALL NOT expose `extraHomeModules`.

#### Scenario: An owner outside the profiles is declared

- **WHEN** the clan host interface is evaluated with a worker whose `owner = "nobody"`
- **THEN** forcing that owner fails, and the `omnigent-worker-inventory` case that asserts this failure passes

#### Scenario: Current inventory owners are evaluated

- **WHEN** every host's clan settings are round-tripped through JSON in `omnigent-worker-inventory`
- **THEN** the round trip is identical and every owner (`cameron`, `janettesmith`) is a `flake.users` key

### Requirement: A worker's author is its owner's profile, set by the host

The NixOS and Darwin Omnigent adapters SHALL set each worker home's `vcs.author` to `flake.lib.vcsAuthor flake.users.${worker.owner}.meta`, computed at system level, so that the worker home receives two non-secret strings and never reads `flake.users`.
The inventory's worker credentials SHALL derive `expected` from `flake.users.${owner}.meta`, keeping `expected.gitEmail = meta.gitEmail`, `expected.signingPublicKey = head meta.sshKeys` and `expected.omnigentEmail = meta.email`.
`modules/home/ai/omnigent/credentials.nix` SHALL NOT set `user.email` or `user.name` for git or jj, and the inventory SHALL NOT pass author settings through `extraHomeModules`.

#### Scenario: A worker home is evaluated with a throwing user set

- **WHEN** `checks.<system>.omnigent-worker-capabilities` evaluates a worker home whose `flake` special argument makes `users` throw, with `vcs.author` set by the fixture
- **THEN** evaluation succeeds, showing that nothing in the worker home forces `flake.users`

#### Scenario: Cameron's worker on magnetite is evaluated

- **WHEN** `nixosConfigurations.magnetite.config.home-manager.users.omnigent-cameron.programs.{git,jujutsu}.settings.user` is evaluated
- **THEN** both are `{ name = "Cameron Smith"; email = "cameron.ray.smith@gmail.com"; }`, where before this change git had no `name` and jj had `name = ""`

#### Scenario: A worker without a delivered signing key

- **WHEN** a worker's credentials enable no signing key
- **THEN** its home's git and jj `user.email` still equal its owner's author address

### Requirement: The sign-in address is unchanged

Each worker's `credentials.expected.omnigentEmail` SHALL remain its owner's `meta.email`, independent of `meta.gitEmail`.

#### Scenario: Janette's worker credentials are evaluated

- **WHEN** the janettesmith worker's `credentials.expected` is evaluated on magnetite
- **THEN** `omnigentEmail` is `janette.a.smith@gmail.com` and `gitEmail` is `125711642+janetteasmith@users.noreply.github.com`

### Requirement: Every Linux worker's author is regulated against its owner's profile

`flake.lib.omnigentFleetObligations` SHALL contain one case, `authorBinding`, that holds on a Linux host only if every worker's home has git `user.name` and `user.email` equal to jj `user.name` and `user.email`, equal to `meta.fullname` and `meta.gitEmail` of `flake.users.${worker.owner}.meta` read directly, with a non-empty name, and with `credentials.expected.gitEmail` equal to that email.
The predicate SHALL be exposed as `flake.lib.omnigentFleetObligations.authorBound`.
`checks.x86_64-linux.omnigent-worker-inventory` SHALL apply `authorBound` to one correct synthetic worker and to five mutants (a wrong author name, an empty name, a jj email differing from git's, a git author with an email and no name, and an expected `gitEmail` differing from the author email), requiring the correct one to hold and each mutant to fail.
No check attribute SHALL be added for this obligation; it SHALL ride on the existing per-machine checks, and the mutants SHALL be evaluated only within the `x86_64-linux` inventory check.
On Darwin hosts the case SHALL NOT be evaluated, so `failures` neither checks nor reports it there.

#### Scenario: Cameron's worker loses its name

- **WHEN** the `vcs.author` the NixOS adapter sets is replaced by one with an empty or different name for the cameron worker
- **THEN** `checks.x86_64-linux.nixos-magnetite` fails with `Fleet obligations unmet on magnetite: omnigentFleetObligations [authorBinding]`, or with the `vcs.author.name` type error for an empty name

#### Scenario: The mutants are evaluated

- **WHEN** `checks.x86_64-linux.omnigent-worker-inventory` is built
- **THEN** its correct-author control holds and its wrong-name, empty-name, git-jj-mismatch, missing-git-name and expected-drift mutants each fail `authorBound`, and the check fails if any of those six outcomes is inverted

#### Scenario: The check key set is compared

- **WHEN** `nix eval --json '.#.checks.x86_64-linux' --apply builtins.attrNames` and `nix eval --json '.#.checks.aarch64-darwin' --apply builtins.attrNames` are each compared before and after this change
- **THEN** the two `x86_64-linux` lists are identical and the two `aarch64-darwin` lists are identical

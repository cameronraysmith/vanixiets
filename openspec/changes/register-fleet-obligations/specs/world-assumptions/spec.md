## ADDED Requirements

### Requirement: A330 — In the locked nixpkgs, allowUnfree and permittedInsecurePackages only decide whether evaluating a marked package throws

It is true of nixpkgs at the locked revision that `allowUnfree` and `permittedInsecurePackages` are read only by the meta check, which throws on a rejected package and returns an accepted one unchanged. Neither enters a derivation's inputs, so instances differing only in them give equal derivations for every package both accept.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: nixpkgs `2074cc672349f14240fb7ea90d509e0b643e9dd4`, read 2026-11-26. `pkgs/stdenv/generic/check-meta.nix:78` reads `allowUnfree`; `:211-214` turns `permittedInsecurePackages` into `allowInsecurePredicate`; `:622-650` (`handle`) either throws `Refusing to evaluate package …`, calls `handleEvalIssue`, or passes, and returns nothing that `make-derivation.nix` adds to the derivation's attributes.

#### Scenario: Read at the source on 2026-11-26

- **WHEN** the files above were read at the locked revision on 2026-11-26
- **THEN** the two keys fed only the validity check and its error path

#### Scenario: nixpkgs makes either key affect a derivation

- **WHEN** a nixpkgs update makes `allowUnfree` or `permittedInsecurePackages` change a derivation's attributes (for example by selecting a different source or build flag), which the cross-revision identity oracle shows as a difference in a `vmTests` or check attribute whose only change is its package set
- **THEN** this assumption is void; every `fleet-package-set-interface` requirement that names A330 loses its claim that the attributes moved to the fleet package set keep their derivations, and each differing attribute is re-examined

### Requirement: A331 — An attribute nothing reads is never evaluated, so an import of a derivation's output bound to it is never built

It is true of the Nix language, in stock Nix and the alternative evaluator alike, that an attribute's value is computed only when demanded. An `import` of a derivation's output bound to an overlay attribute nothing reads therefore triggers no build during evaluation, and removing that attribute changes no other attribute's derivation.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: the Nix reference manual's description of lazy evaluation and of import from derivation, which happens "when the result is needed"; `modules/nixpkgs/overlays/channels.nix:41-45` binds `patched = import (prev.applyPatches { … }) …`, and `rg '\.patched\b' modules pkgs` found no reader on 2026-11-26.

#### Scenario: Read on 2026-11-26

- **WHEN** the overlay and its readers were searched on 2026-11-26
- **THEN** no expression in `modules/` or `pkgs/` read `patched`

#### Scenario: An evaluator forces overlay attributes eagerly

- **WHEN** an evaluator, or a tool run over the flake, such as one that walks every `legacyPackages` attribute, forces `patched` and builds its source during evaluation
- **THEN** this assumption is void; the `fleet-package-set-interface` requirement "The channels overlay offers no patched channel" no longer rests on removing dead code alone, and the removal's drvPath neutrality is re-checked

### Requirement: A332 — An evaluation-time assertion leaves the asserted value's derivation unchanged

It is true of the Nix language that `assert c; e` evaluates to `e` when `c` holds, and fails evaluation otherwise. `lib.assertMsg` returns `true` or throws. A derivation guarded by passing assertions therefore has the same derivation path as the unguarded one.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: the Nix reference manual's language section on assertions; `nixpkgs/lib/asserts.nix` (`assertMsg = pred: msg: pred || throw msg`) at the locked revision.

#### Scenario: Read on 2026-11-26

- **WHEN** the manual and `lib/asserts.nix` were read on 2026-11-26
- **THEN** an assertion returned its body unchanged

#### Scenario: Wiring changes a derivation

- **WHEN** the cross-revision identity oracle shows a machine check or a judge fixture check whose drvPath changed in a revision that changed only how its assertions are wired
- **THEN** this assumption is void for that construction; the `fleet-obligation-registry-interface` requirements "Every machine check asserts every judge registered for its class" and "A judge-over-fixtures check reports each wrong case" lose their unchanged-derivation discharge until the cause is found

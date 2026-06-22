# Confirming the toolchain and standing up the Lean backend

The refine → lift → check loop assumes that each leg's tool is present and that the lift and check tools are version-matched.
This reference is where that assumption is made good before the first cycle runs on a machine.
It covers confirming each tool, a tier-0 smoke test that the lift is wired end to end, and the one-time Lean backend setup the check leg presupposes.
The methodology stays "one CLI call per step" only once this setup is in place; this file is the setup, not part of the steady-state loop.

## Contents

- [Confirm the toolchain before starting](#confirm-the-toolchain-before-starting)
- [The general substrate and the round-trip specialization](#the-general-substrate-and-the-round-trip-specialization)
- [Tier-0 translation-validation smoke test](#tier-0-translation-validation-smoke-test)
- [Lean backend setup for the check tier](#lean-backend-setup-for-the-check-tier)
- [Why elan is required](#why-elan-is-required)

## Confirm the toolchain before starting

Before the first refine → lift → check cycle, verify each leg of the pipeline independently, because a failure is far cheaper to localize when you already know which tools were working.
A useful fact narrows the search immediately: the two lift sub-steps are pure text generation and need no Lean toolchain at all.
Charon and Aeneas read Rust and LLBC and write LLBC and Lean text; only the spec leg (Step 1) and the check leg (Step 4) invoke `elan`, `lean`, or `lake`.
When a lift fails, the Lean toolchain is therefore never the cause — look to Charon, to Aeneas, or to their version pins instead.

Charon's own version is queried with the `version` subcommand: `charon version` prints Charon's version, and `charon toolchain-version` prints the pinned rustc toolchain it embeds.
The GNU-style `charon --version` is not accepted and errors, so reach for the subcommand form.
Aeneas runs as `aeneas -backend <backend> ...`, with single-dash flags following the OCaml `Arg` convention rather than GNU double-dash flags.
The first Charon run performs a one-time `cargo miri setup` to provision its pinned nightly; a non-fatal toolchain-setup warning may appear on some platforms, and translation still succeeds — do not abort on it.

## The general substrate and the round-trip specialization

It is worth separating two layers of Lean setup that this file touches.
The general substrate is `elan`, a `lean-toolchain` file, and `lake`: that triple is what any type-checkable Lean spec needs, including a standalone spec kept beside a non-Rust implementation.
That general "keep a type-checkable Lean spec beside the implementation" stance, and the Lean-spec-beside-a-non-Rust-implementation case (for example a Lean spec beside a Python implementation), are owned by `preferences-theoretical-foundations`.
This file specializes the substrate for the Rust round trip's check tier: on top of the general triple it adds the `require` on the Aeneas Lean library, pins the toolchain to the Aeneas backend's exact release-candidate string, and provisions the mathlib object cache that the lifted-model proofs pull in.
A standalone Lean spec that is never lifted needs only the general substrate plus its own dependencies; the additions below are specific to comparing a spec against an Aeneas-lifted model in Lean.

## Tier-0 translation-validation smoke test

The cheapest end-to-end check that the lift is wired is to re-lift an upstream example whose golden Lean is committed and diff the result against it.
Inside an Aeneas checkout, lift the Rust source `tests/src/switch_test.rs` through Charon and then Aeneas and compare the produced Lean against the committed `tests/lean/SwitchTest.lean`.
Run Charon from the crate or clone root and pass the source as a cwd-relative path, because Charon records the source file's path and line numbers and Aeneas threads them into the generated Lean `Source:` comment.
That makes the relative cwd from which you invoke Charon control part of the output byte-for-byte.
The consequence for the diff is precise: an absolute or differently-rooted invocation perturbs only the `Source:` comment, so a diff that touches only that comment is still a pass, while any other difference is a real divergence worth investigating.
The time scales of the two halves of the loop diverge sharply here, and it is worth internalizing the contrast: the lift itself is sub-second pure text generation, whereas the check build below — once the Lean backend is set up — is on the order of minutes.

## Lean backend setup for the check tier

The check leg builds a Lean project that imports the Aeneas backend library, the lifted model, and the bridging theorems, and standing that project up is a one-time, machine-independent recipe.
The Aeneas README states it as an "Important" notice; generalized away from any one machine, the steps are these.

1. Create a Lean package with `lake new <name>` (or hand-write a minimal `lakefile` plus a `lean-toolchain` file and the sources).
2. Set the project's `lean-toolchain` to exactly the string in the Aeneas repository's `backends/lean/lean-toolchain`; read the backend's file and copy that string rather than any version named in this skill, because Lake requires an exact match between the project and its dependencies' toolchains.
3. Require the Aeneas Lean library. The clone-independent default is the github form, pinning the `rev` to a version-matched commit:

```toml
[[require]]
name = "aeneas"
git = "https://github.com/AeneasVerif/aeneas"
subDir = "backends/lean"
rev = "<commit>"
```

   When a local clone already exists, the path form is an optimization that avoids re-fetching:

```toml
[[require]]
name = "aeneas"
path = "<aeneas-repo>/backends/lean"
```

4. Run `lake update` to resolve the transitive dependencies — mathlib at the pinned revision, plus aesop, batteries, Qq, Cli, plausible, and their companions.
5. Run `lake exe cache get` to download the prebuilt mathlib object cache; this is mandatory in practice, because skipping it risks a multi-hour from-source mathlib compile.
6. Run `lake build <TARGET>` scoped to your target. Do not run a bare `lake build` in a multi-target tree — the Aeneas clone's `tests/lean`, for instance, holds dozens of libraries — and do not drive the build with `make`.

The github `require` form is preferred as the default because it needs no checkout and resolves a version-matched pair on the spot; the path form is the optimization for when a pinned local clone is already present.
Pinning the `rev` to a version-matched commit is what keeps the backend's `charon_version` gate and its mathlib revision consistent with the Charon and toolchain you lift with.

## Why elan is required

`elan` is required for the spec and check legs, not merely convenient.
The Lean backend pins a release-candidate Lean toolchain, and whatever default Lean is on PATH will not satisfy that pin.
`elan` reads the nearest `lean-toolchain` file and auto-installs and selects that exact toolchain per-directory, which is precisely what lets a backend-pinned project build under a different default Lean.
This per-directory toolchain selection is the mechanism behind step 2 above: the `lean-toolchain` string you copy from the Aeneas backend is the string `elan` resolves and provisions when `lake` runs inside the project.

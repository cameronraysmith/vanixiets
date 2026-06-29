# GitHub overview

This reference frames the GitHub surface — pull requests, buildbot, and Mergify — as one realization of a change's terminal artifact rather than as a separate work-tracking layer.
It documents where the forge fits in the PM model; the mechanical PR workflow lives in preferences-git-version-control and nix-flake-pr-cycle.

## The terminal artifact

The terminal artifact of a change is the archived OpenSpec change.
That is the durable, reviewable unit the lifecycle produces: a change directory that has passed verify and been archived, carrying its proposal, design, specs, tasks, and verification record.

A pull request into the monorepo is one realization of that terminal artifact, not a distinct artifact.
The PR diff already contains the complete archived cycle, and archive precedes the PR, so the PR is the forge's rendering of the same terminal artifact rather than a second thing to track.
This is why the lifecycle binds Done to archive, not to the PR; see openspec-linear-sync for that binding.

The PR includes any docs/handbook delta the change produces.
A change that touches the handbook lands those edits in the same PR as the rest of the diff, so the handbook content is part of the one realization, not a separate review track.

## The forge surface

The repository's default integration policy is fast-forward merge, with a pull request used when change visibility, collaboration, or CI validation warrants it; see preferences-git-version-control for that selection and the PR safety protocol.

buildbot is the CI backend for nix evaluation and build checks, surfaced as the `buildbot/nix-eval` and `buildbot/nix-build` status checks on a PR.
The full validate-to-merge cycle — enumerating flake checks, probing them, opening a draft PR, monitoring buildbot, marking ready, and triggering auto-merge — is the nix-flake-pr-cycle skill; this hub routes to it rather than restating it.

Mergify is the auto-merge gate that fast-forwards a PR to main once its required checks are green.
It enforces the fast-forward-only policy at the merge boundary.

The unit of work remains the forge-agnostic board state and the archived OpenSpec change; GitHub is where that terminal artifact becomes a reviewable, mergeable PR, and the board is independent of any single forge.

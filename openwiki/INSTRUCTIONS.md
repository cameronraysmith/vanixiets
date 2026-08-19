# OpenWiki instructions for vanixiets

This file is the user-authored brief for the OpenWiki agent that maintains the `openwiki/` wiki in this repository.
OpenWiki reads it for scope and priorities and does not rewrite it during a normal run, so it is the right place to steer the wiki.

## What this repository is

vanixiets is a Nix flake that configures nix-darwin workstations and NixOS servers through clan, using flake-parts with import-tree so modules are discovered from the filesystem.
It also publishes an apm marketplace of agent-skill plugins that is installable independently of the Nix configurations.
`AGENTS.md` at the repository root is the hand-written project context and is authoritative wherever it and the wiki disagree.

## What to document

Prioritise the parts of the tree whose behaviour is not evident from a single file:

- how import-tree discovery, flake-parts, and clan's deferred module composition combine to produce a machine configuration, and where the seams between them are
- how a skill travels from `modules/home/ai/plugins/<group>/.apm/skills/` through `pkgs/by-name/apm-skills-compose/` to a delivered read-only store symlink
- how `modules/terranix/` declarations become Terraform and how the per-machine `enabled` toggle changes what is provisioned
- what each check under `modules/checks/` actually validates, and which `just` recipe reaches it
- how the Kubernetes layer composes terranix, clan, easykubenix, and nixidy, and where the boundary between infrastructure and applications falls

Prefer diagrams for anything whose difficulty is ordering or layering rather than detail.

## What to leave alone

Do not document, infer, or reproduce:

- which person uses which machine, or any other detail about the people the workstations belong to
- whether any particular machine is currently provisioned, reachable, or running; that is account state, not repository content, and it is wrong as soon as it is written
- anything read out of `secrets/`, `sops/`, or `vars/` beyond the fact that those paths hold encrypted material and how the encryption is wired

This repository is public.
Treat anything that would only make sense to someone with access to the private infrastructure as out of scope rather than as something to summarise carefully.

## House style

Follow the conventions the repository's own documentation uses: one sentence per line, sentence-case headings, prose in preference to bullet lists where the content is a narrative, and no emoji.
Prefer a pointer to the authoritative file or command over a copy of what it contains, because a copy is what goes stale.
State counts and versions only where they are load-bearing, and name the file they were read from so the next refresh can re-derive them.

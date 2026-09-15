## Context

Generation 13 provides the existing niri/DMS desktop.
Only pyrite currently imports the DMS aggregate.

## Goals / Non-Goals

Prepare declarative bar auto-hide and install-only Zen in two independently verified commits.
Exclude browser defaults, profiles, extensions, autostart, widgets, activation and hardware changes.

## Decisions

Add `autoHide = true` to the default bar rather than replacing its list or writing runtime settings.
Use the upstream wrapped package through a dedicated Home Manager aggregate because upstream exports packages, not a Home Manager module.
Import it at the host's cameron composition boundary to avoid Linux-only package evaluation on Darwin.
Follow root nixpkgs and pin the approved upstream revision rather than introducing another nixpkgs version.

## Risks / Trade-offs

Upstream binary packaging compatibility with root nixpkgs requires a native build.
A valid desktop entry does not prove physical launch or Wayland behavior.

## Migration Plan

Return frozen source and build evidence for independent review.
Activation and physical acceptance require a later operator decision; generation 13 remains active.

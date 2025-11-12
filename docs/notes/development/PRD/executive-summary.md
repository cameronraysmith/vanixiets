# Executive Summary

The nix-config infrastructure migration to dendritic flake-parts pattern with clan-core integration addresses critical architectural limitations in the current nixos-unified implementation across 1 VPS and 4 darwin workstations.
The migration delivers improved type safety through consistent module system usage, clearer organizational patterns via the dendritic `flake.modules.*` namespace, and robust multi-machine coordination capabilities via clan-core's inventory system, vars management, and service instances with roles.

The critical architectural challenge is that no proven examples exist combining dendritic flake-parts with clan patterns.
This necessitates a validation-first approach: Phase 0 validates the architectural combination in a minimal test-clan repository, then immediately deploys real infrastructure (Hetzner VPS + GCP VM) using clan-infra's proven terranix pattern to validate multi-machine coordination before darwin migration.
This combined validation + infrastructure deployment approach de-risks both the architectural integration and the infrastructure deployment pattern before touching any darwin hosts.
Following infrastructure validation, Phase 1 integrates production services and hardening on the deployed VMs, proving the complete production-ready stack before darwin migration.
Phases 2-4 progressively migrate darwin workstations (blackphos → rosegold → argentum) with 1-2 week stability gates between each host.
Phase 5 migrates the primary workstation (stibnite) only after 4-6 weeks of proven stability across all other hosts.
Phase 6 removes legacy nixos-unified infrastructure.

## What Makes This Special

**Validation-first de-risking**: Phase 0 validates an untested architectural combination (dendritic + clan) in a disposable test environment, then immediately deploys real infrastructure (Hetzner VPS + GCP VM) to validate multi-machine coordination and infrastructure deployment patterns before darwin migration, eliminating the risk of discovering fundamental incompatibilities or infrastructure issues after committing to darwin host changes.

**Type safety through progressive optimization**: Leverages flake-parts module system to bring compile-time type checking to infrastructure configuration, addressing Nix's lack of native type system while maintaining pragmatism—clan functionality is non-negotiable, dendritic optimization applied where feasible without compromise.

**VPS-first foundation**: Deploys always-on cloud infrastructure (cinnabar) before darwin hosts, providing stable zerotier controller independent of workstation power state and validating patterns on NixOS (clan's native platform) before tackling darwin-specific integration challenges.

**Progressive validation gates with explicit go/no-go frameworks**: Each phase has measurable success criteria and rollback procedures, with 1-2 week stability windows and host-by-host validation preventing cascading failures.

**Brownfield pragmatism**: Accepts hybrid approaches where pure patterns conflict with clan functionality, documented and justified rather than hidden, prioritizing operational success over architectural orthodoxy.

---

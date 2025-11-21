# Clan Inventory + Dendritic Home-Manager Research

Research into how clan inventory `extraModules` can reference dendritic flake-exported home-manager modules, determining feasibility of consolidating all user configuration in inventory services.

## Documents

### 1. Quick Reference (`clan-inventory-quickref.md`)
**Start here.** Concise overview with answer to critical question and four valid patterns.
- Best for: Quick lookup, implementation decisions
- Length: ~95 lines
- Contents: Patterns, JSON boundary, test-clan proof, implementation guide

### 2. Full Research (`clan-inventory-extramodules-research.md`)
**Comprehensive deep dive.** Detailed analysis of all patterns, architectural constraints, and implementation evidence.
- Best for: Understanding the "why", full context
- Length: ~623 lines
- Contents: All patterns explained, JSON serialization deep dive, architectural constraints, consolidation feasibility, evidence from 4 implementations

### 3. Summary (`clan-inventory-research-summary.txt`)
**Executive summary.** Key findings organized by research objective and evidence examined.
- Best for: Reporting, documentation references
- Length: ~180 lines
- Contents: Objectives, answer, findings, consolidation feasibility, recommended patterns, evidence sources

## Critical Question

**Can clan inventory service extraModules reference flake-exported modules?**

**ANSWER: Partial Yes with constraints**

Cannot directly reference `inputs.self.modules.homeManager.*` in inventory context due to JSON serialization requirement. However, CAN access via `extraSpecialArgs` pass-through in NixOS module layer. This pattern is proven working in test-clan.

## Key Findings

1. **JSON Serialization Boundary**: Inventory must be JSON-serializable, but inline NixOS modules (which are JSON-serializable) can contain non-serializable expressions

2. **Four Valid Patterns**:
   - File path imports (simplest, no dendritic access)
   - Self-referenced modules (limited, json-serializable only)
   - Inline modules (flexible, still no dendritic access)
   - Inline + extraSpecialArgs (full consolidation, test-clan pattern)

3. **Test-Clan Proof**: Both cameron.nix and crs58.nix successfully consolidate all dendritic aggregates via Pattern 4

4. **Consolidation is Feasible**: YES - test-clan demonstrates it works, all prerequisites met

## Recommended Pattern for Consolidation

Use Pattern 4 (Inline + extraSpecialArgs):

```nix
roles.default.extraModules = [
  inputs.home-manager.nixosModules.home-manager
  (
    { pkgs, ... }:
    {
      # NixOS layer config
      users.users.cameron.shell = pkgs.zsh;
      
      # Bridge to home-manager
      home-manager = {
        extraSpecialArgs = {
          flake = inputs.self // { inherit inputs; };  # KEY: Pass flake context
        };
        
        # Home-manager layer - can now access dendritic modules
        users.cameron = {
          imports = [
            inputs.self.modules.homeManager."users/crs58"
            inputs.self.modules.homeManager.ai
            inputs.self.modules.homeManager.core
            # ... all aggregates
          ];
        };
      };
    }
  )
];
```

## Evidence Examined

### Test-Clan (Our Implementation - Validates Pattern Works)
- `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/inventory/services/users/cameron.nix`
- `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/inventory/services/users/crs58.nix`

### Reference Implementations
- qubasa-clan-infra: File-based pattern (Pattern 1)
- pinpox-clan-nixos: Programmatic file paths
- clan-infra: Traditional non-dendritic pattern

### Clan-Core Documentation
- Inventory guide: `~/projects/nix-workspace/clan-core/docs/site/guides/inventory/inventory.md`
- Services guide: `~/projects/nix-workspace/clan-core/docs/site/guides/services/introduction-to-services.md`
- Users service: `~/projects/nix-workspace/clan-core/docs/site/getting-started/add-users.md`

## Implementation Path for Infra

1. Review test-clan pattern in cameron.nix and crs58.nix
2. If creating user services in infra, use Pattern 2 (extraSpecialArgs)
3. Apply same consolidation approach as test-clan
4. Test on nixos first (users service limitation)
5. Darwin via extraModules workaround (existing test-clan pattern)

## Key Architectural Insights

1. **JSON Serialization is Not a Blocker**: Inline modules ARE JSON-serializable even if they contain non-serializable expressions (evaluated after serialization)

2. **extraSpecialArgs is the Bridge**: Flake context passed through extraSpecialArgs in NixOS layer becomes available in home-manager layer

3. **Single Source of Truth**: Pattern 4 enables dendritic modules to be referenced in both standalone home-manager AND clan inventory contexts

4. **Pattern is Proven Stable**: Test-clan demonstrates real-world usage with both users successfully importing all aggregates

## Files to Reference

For Quick Lookup:
- `clan-inventory-quickref.md` - All patterns and key insights in one place

For Deep Understanding:
- `clan-inventory-extramodules-research.md` - Full analysis with examples and constraints

For Implementation:
- Test-clan cameron.nix/crs58.nix - Real working pattern
- This README - Navigation and quick reference

## Conclusion

Clan inventory `extraModules` CAN reference dendritic flake modules through the `extraSpecialArgs` mechanism. This enables complete consolidation of user configuration across standalone home-manager contexts and clan inventory services. The pattern is proven stable and functional.

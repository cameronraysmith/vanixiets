{ inputs, ... }:
{
  clan = {
    meta.name = "test-clan";
    meta.description = "Phase 0: Architectural validation + infrastructure deployment";
    meta.domain = "clan";

    # Pass inputs to all machines via specialArgs
    specialArgs = { inherit inputs; };

    # Provide pre-configured nixpkgs with allowUnfree enabled
    # Clan will use these instead of creating fresh instances from raw nixpkgs
    # See: modules/nixpkgs/per-system.nix for allowUnfree configuration
    pkgsForSystem = system: inputs.self.legacyPackages.${system} or null;
  };
}

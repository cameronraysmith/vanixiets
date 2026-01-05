# Multi-architecture container builds using nix2container with unified pkgsCross
#
# This module provides:
# - Container packages for configurable target architectures
# - Multi-arch manifests for CI/CD registry distribution
#
# Architecture:
# - Uses pkgsCross for cross-compilation (auto-optimizes to native when host == target)
# - nix2container: Builds JSON manifests with pre-computed layer digests
# - mkMultiArchManifest: Creates multi-arch Docker manifests using skopeo and podman
#
# Platform behavior:
# - x86_64-linux host: x86_64 containers native, aarch64 containers cross-compiled
# - aarch64-linux host: aarch64 containers native, x86_64 containers cross-compiled
# - aarch64-darwin host: both via rosetta-builder (native execution in Linux VM)
#
# Performance:
# - pkgsCross auto-optimizes: when target == host, returns native pkgs (zero overhead)
# - Cross-compilation runs at native speed (no emulation during build)
# - Build time: O(manifest size) - JSON generation only
# - Push time: O(changed layers) - skopeo skips unchanged layers by digest
#
# See docs/about/contributing/multi-arch-containers.md for usage guide.
{
  inputs,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    let
      isLinux = lib.hasSuffix "-linux" system;
      isDarwin = lib.hasSuffix "-darwin" system;

      # Get nix2container for this system
      nix2container = inputs.nix2container.packages.${system}.nix2container;

      # Get nix2container's patched skopeo (required for nix: transport)
      skopeo-nix2container = inputs.nix2container.packages.${system}.skopeo-nix2container;

      # Import the multi-arch manifest builder from shared lib
      mkMultiArchManifest = pkgs.callPackage ../../lib/mk-multi-arch-manifest.nix { };

      # ============================================================================
      # Target Architecture Configuration
      # ============================================================================

      # All available target architectures
      # Each target defines: system name, pkgsCross instance, OCI arch label
      allTargets = {
        x86_64 = {
          system = "x86_64-linux";
          crossPkgs = pkgs.pkgsCross.gnu64;
          arch = "amd64";
        };
        aarch64 = {
          system = "aarch64-linux";
          crossPkgs = pkgs.pkgsCross.aarch64-multiplatform;
          arch = "arm64";
        };
      };

      # Default targets for multi-arch builds (can be overridden per-container)
      defaultTargetNames = [
        "x86_64"
        "aarch64"
      ];

      # Helper to filter targets by name list
      selectTargets = targetNames: lib.filterAttrs (n: _: lib.elem n targetNames) allTargets;

      # ============================================================================
      # Container Image Building
      # ============================================================================

      # Build base layer for a specific target architecture
      # Uses cross-compiled bash and coreutils for the target
      mkBaseLayerForTarget =
        target:
        nix2container.buildLayer {
          deps = [
            target.crossPkgs.bashInteractive
            target.crossPkgs.coreutils
          ];
        };

      # Build a container image for a specific target architecture
      #
      # Arguments:
      #   name: Container/image name (e.g., "fd")
      #   packages: List of package attribute names to include (e.g., ["fd"] or ["fd" "ripgrep"])
      #   entrypoint: Binary name for entrypoint (defaults to name)
      #   target: Target architecture definition from allTargets
      #   tag: Image tag (defaults to "latest")
      #
      # Layer strategy:
      # - Layer 0: baseLayer (bash, coreutils) - rarely changes, shared per arch
      # - Layer 1: application packages - changes independently per container
      mkContainerForTarget =
        {
          name,
          packages,
          entrypoint ? name,
          target,
          tag ? "latest",
        }:
        let
          # Resolve package names to actual packages from crossPkgs
          resolvedPackages = map (pkgName: target.crossPkgs.${pkgName}) packages;
          entrypointPackage = target.crossPkgs.${builtins.head packages};
          baseLayer = mkBaseLayerForTarget target;

          # Build PATH from all included packages
          packagePaths = lib.concatMapStringsSep ":" (pkg: "${pkg}/bin") resolvedPackages;
        in
        nix2container.buildImage {
          inherit name tag;

          # Explicit architecture for OCI manifest
          arch = target.arch;

          # Explicit layers: base packages in shared layer
          layers = [ baseLayer ];

          # All packages in main image layer (copyToRoot strips /nix/store prefix)
          copyToRoot = target.crossPkgs.buildEnv {
            name = "root";
            paths = resolvedPackages;
            pathsToLink = [ "/bin" ];
          };

          config = {
            entrypoint = [ "${entrypointPackage}/bin/${entrypoint}" ];
            Env = [
              "PATH=${packagePaths}:${target.crossPkgs.coreutils}/bin:${target.crossPkgs.bashInteractive}/bin"
            ];
            Labels = {
              "org.opencontainers.image.description" =
                "Container with ${lib.concatStringsSep ", " packages} (${target.arch})";
              "org.opencontainers.image.source" = "https://github.com/cameronraysmith/vanixiets";
            };
          };

          # Further split customization layer by popularity if beneficial
          maxLayers = 2;
        };

      # ============================================================================
      # Container Definitions
      # ============================================================================

      # Define containers with their package lists
      # Each container can include one or more packages
      containerDefs = {
        fd = {
          name = "fd";
          packages = [ "fd" ];
          entrypoint = "fd";
        };
        rg = {
          name = "rg";
          packages = [ "ripgrep" ];
          entrypoint = "rg";
        };
        # Example of future multi-package container:
        # devtools = {
        #   name = "devtools";
        #   packages = [ "fd" "ripgrep" "jq" "yq-go" ];
        #   entrypoint = "bash";
        # };
      };

      # ============================================================================
      # Package Generation
      # ============================================================================

      # Generate container packages for all containers and all targets
      # Creates: fdContainer-x86_64, fdContainer-aarch64, rgContainer-x86_64, etc.
      containerPackages = lib.listToAttrs (
        lib.flatten (
          lib.mapAttrsToList (
            containerName: def:
            lib.mapAttrsToList (targetName: target: {
              name = "${containerName}Container-${targetName}";
              value = mkContainerForTarget (def // { inherit target; });
            }) allTargets
          ) containerDefs
        )
      );

      # Helper to get env var with fallback (requires --impure for actual env var reading)
      getEnvOr =
        var: default:
        let
          val = builtins.getEnv var;
        in
        if val == "" then default else val;

      # ============================================================================
      # Manifest Generation (Unified)
      # ============================================================================

      # Generate a manifest for a container with specified target architectures
      # When targetNames has one element, creates single-arch manifest (no manifest list)
      # When targetNames has multiple elements, creates multi-arch manifest list
      #
      # Arguments:
      #   containerName: Name of the container (key in containerDefs)
      #   targetNames: List of target names to include (defaults to all)
      mkManifest =
        {
          containerName,
          targetNames ? defaultTargetNames,
        }:
        let
          selectedTargets = selectTargets targetNames;
        in
        mkMultiArchManifest {
          name = containerName;
          images = lib.mapAttrs' (
            targetName: target:
            lib.nameValuePair target.system containerPackages."${containerName}Container-${targetName}"
          ) selectedTargets;
          registry = {
            name = "ghcr.io";
            repo = "cameronraysmith/vanixiets/${containerName}";
            username = getEnvOr "GITHUB_ACTOR" "cameronraysmith";
            password = "$GITHUB_TOKEN";
          };
          version = getEnvOr "VERSION" "1.0.0";
          branch = getEnvOr "GITHUB_REF_NAME" "main";
          skopeo = skopeo-nix2container;
          podman = pkgs.podman;
        };

      # Generate all manifest variants for all containers
      # For each container: one multi-arch manifest + one single-arch manifest per target
      manifestPackages = lib.listToAttrs (
        lib.flatten (
          lib.mapAttrsToList (
            containerName: _:
            [
              # Multi-arch manifest (all targets)
              {
                name = "${containerName}Manifest";
                value = mkManifest { inherit containerName; };
              }
            ]
            ++
              # Single-arch manifests (one per target)
              lib.mapAttrsToList (targetName: _: {
                name = "${containerName}Manifest-${targetName}";
                value = mkManifest {
                  inherit containerName;
                  targetNames = [ targetName ];
                };
              }) allTargets
          ) containerDefs
        )
      );

    in
    {
      # All container and manifest packages available on Linux and Darwin
      # Use lib.mkMerge to properly merge with pkgs-by-name packages
      packages = lib.mkMerge [
        # Container images for all target architectures
        # Available on both Linux and Darwin (Darwin builds via rosetta-builder)
        (lib.optionalAttrs (isLinux || isDarwin) containerPackages)

        # Manifests for CI/CD registry distribution
        # Now works on Linux (via pkgsCross) and Darwin (via rosetta-builder)
        # Usage: VERSION=1.0.0 nix run --impure .#fdManifest
        (lib.optionalAttrs (isLinux || isDarwin) manifestPackages)
      ];
    };
}

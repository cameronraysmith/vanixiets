# Multi-architecture container builds using nix2container with unified pkgsCross
#
# This module provides:
# - Container packages for both x86_64-linux and aarch64-linux targets
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

      # Unified target definitions using pkgsCross
      # When host == target, pkgsCross auto-optimizes to return native pkgs
      # (verified: same derivation paths, zero overhead)
      targets = {
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

      # Build a minimal container image for a specific target architecture
      # Makes it work like: docker run <name>:latest --version
      #
      # Layer strategy:
      # - Layer 0: baseLayer (bash, coreutils) - rarely changes, shared per arch
      # - Layer 1: tool package - changes independently per tool
      mkToolContainerForTarget =
        {
          name,
          pkgName ? name,
          target,
          tag ? "latest",
        }:
        let
          package = target.crossPkgs.${pkgName};
          baseLayer = mkBaseLayerForTarget target;
        in
        nix2container.buildImage {
          inherit name tag;

          # Explicit architecture for OCI manifest
          arch = target.arch;

          # Explicit layers: base packages in shared layer
          layers = [ baseLayer ];

          # Tool package in main image layer (copyToRoot strips /nix/store prefix)
          copyToRoot = target.crossPkgs.buildEnv {
            name = "root";
            paths = [ package ];
            pathsToLink = [ "/bin" ];
          };

          config = {
            entrypoint = [ "${package}/bin/${name}" ];
            Env = [
              "PATH=${package}/bin:${target.crossPkgs.coreutils}/bin:${target.crossPkgs.bashInteractive}/bin"
            ];
            Labels = {
              "org.opencontainers.image.description" = "Minimal container with ${name} (${target.arch})";
              "org.opencontainers.image.source" = "https://github.com/cameronraysmith/vanixiets";
            };
          };

          # Further split customization layer by popularity if beneficial
          maxLayers = 2;
        };

      # Container definitions
      containerDefs = {
        fd = {
          name = "fd";
          pkgName = "fd";
        };
        rg = {
          name = "rg";
          pkgName = "ripgrep";
        };
      };

      # Generate container packages for all targets
      # Creates: fdContainer-x86_64, fdContainer-aarch64, rgContainer-x86_64, rgContainer-aarch64
      containerPackages = lib.listToAttrs (
        lib.flatten (
          lib.mapAttrsToList (
            containerName: def:
            lib.mapAttrsToList (targetName: target: {
              name = "${containerName}Container-${targetName}";
              value = mkToolContainerForTarget (def // { inherit target; });
            }) targets
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

      # Generate multi-arch manifest for a container
      # Works on any platform: Linux uses pkgsCross, Darwin uses rosetta-builder
      mkManifestForContainer =
        containerName:
        mkMultiArchManifest {
          name = containerName;
          images = lib.mapAttrs' (
            targetName: target:
            lib.nameValuePair target.system containerPackages."${containerName}Container-${targetName}"
          ) targets;
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

      # Generate single-arch manifest (no manifest list, direct push)
      mkSingleArchManifest =
        containerName: targetName:
        let
          target = targets.${targetName};
        in
        mkMultiArchManifest {
          name = containerName;
          images = {
            ${target.system} = containerPackages."${containerName}Container-${targetName}";
          };
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

      # Manifest packages
      manifestPackages = {
        # Multi-arch manifests (both architectures)
        fdManifest = mkManifestForContainer "fd";
        rgManifest = mkManifestForContainer "rg";

        # Single-arch variants (for testing or single-platform deployments)
        fdManifest-x86 = mkSingleArchManifest "fd" "x86_64";
        fdManifest-arm = mkSingleArchManifest "fd" "aarch64";
        rgManifest-x86 = mkSingleArchManifest "rg" "x86_64";
        rgManifest-arm = mkSingleArchManifest "rg" "aarch64";
      };

    in
    {
      # All container and manifest packages available on Linux and Darwin
      # Use lib.mkMerge to properly merge with pkgs-by-name packages
      packages = lib.mkMerge [
        # Container images for all target architectures
        # Available on both Linux and Darwin (Darwin builds via rosetta-builder)
        (lib.optionalAttrs (isLinux || isDarwin) containerPackages)

        # Multi-arch manifests for CI/CD registry distribution
        # Now works on Linux (via pkgsCross) and Darwin (via rosetta-builder)
        # Usage: VERSION=1.0.0 nix run --impure .#fdManifest
        (lib.optionalAttrs (isLinux || isDarwin) manifestPackages)
      ];
    };
}

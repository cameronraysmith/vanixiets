# Multi-architecture container builds using nix2container
#
# This module provides:
# - Container packages (fdContainer, rgContainer) for Linux systems
# - Multi-arch manifests (fdManifest, rgManifest) for CI/CD registry distribution
#
# Architecture:
# - nix2container: Builds JSON manifests with pre-computed layer digests
#   No tarballs written to Nix store; layers synthesized at push time by patched skopeo
# - mkMultiArchManifest: Creates multi-arch Docker manifests using skopeo and podman
#
# Performance characteristics:
# - Build time: O(manifest size) - JSON generation only, no tar creation
# - Store space: O(manifest size) - no layer tarball duplication
# - Push time: O(changed layers) - skopeo skips unchanged layers by digest
#
# See docs/about/contributing/multi-arch-containers.md for usage guide.
{ inputs, lib, ... }:
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

      # Import the multi-arch manifest builder
      mkMultiArchManifest = pkgs.callPackage ./mk-multi-arch-manifest.nix { };

      # Shared base layer: bash and coreutils
      # This layer is reused across all tool containers, maximizing cache hits
      baseLayer = nix2container.buildLayer {
        deps = [
          pkgs.bashInteractive
          pkgs.coreutils
        ];
      };

      # Build a minimal container image with a package
      # Makes it work like: docker run <name>:latest --version
      #
      # Layer strategy:
      # - Layer 0: baseLayer (bash, coreutils) - rarely changes, shared
      # - Layer 1: tool package - changes independently per tool
      #
      # Development workflow:
      # - Local test: nix run .#fdContainer.copyToDockerDaemon && docker run fd
      # - Single push: nix run .#fdContainer.copyToRegistry
      # - Multi-arch: nix run --impure .#fdManifest
      mkToolContainer =
        {
          name,
          package,
          tag ? "latest",
        }:
        nix2container.buildImage {
          inherit name tag;

          # Explicit layers: base packages in shared layer
          layers = [ baseLayer ];

          # Tool package in main image layer (copyToRoot strips /nix/store prefix)
          copyToRoot = pkgs.buildEnv {
            name = "root";
            paths = [ package ];
            pathsToLink = [ "/bin" ];
          };

          config = {
            entrypoint = [ "${package}/bin/${name}" ];
            Env = [
              "PATH=${package}/bin:${pkgs.coreutils}/bin:${pkgs.bashInteractive}/bin"
            ];
            Labels = {
              "org.opencontainers.image.description" = "Minimal container with ${name}";
              "org.opencontainers.image.source" = "https://github.com/cameronraysmith/vanixiets";
            };
          };

          # Further split customization layer by popularity if beneficial
          maxLayers = 2;
        };

      # Systems to build images for (both architectures)
      imageSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      # Container packages - Linux only (built via nix-rosetta-builder on Darwin)
      # Manifests available on all systems for CI/CD coordination
      # Use lib.mkMerge to properly merge with pkgs-by-name packages
      packages = lib.mkMerge [
        # Container images - Linux only
        (lib.optionalAttrs isLinux {
          fdContainer = mkToolContainer {
            name = "fd";
            package = pkgs.fd;
          };

          rgContainer = mkToolContainer {
            name = "rg";
            package = pkgs.ripgrep;
          };
        })

        # Multi-arch manifests for CI/CD registry distribution
        # Darwin-only: requires nix-rosetta-builder to build both Linux architectures
        # Usage: nix run --impure .#fdManifest
        # Requires: GITHUB_TOKEN environment variable in CI
        #
        # Note: Manifests are Darwin-only because they depend on both x86_64-linux
        # and aarch64-linux container images. Darwin hosts with nix-rosetta-builder
        # can build both, but single-arch Linux CI runners cannot.
        (lib.optionalAttrs isDarwin (
          let
            # Helper to get env var with fallback (requires --impure for actual env var reading)
            getEnvOr =
              var: default:
              let
                val = builtins.getEnv var;
              in
              if val == "" then default else val;
          in
          {
            fdManifest = mkMultiArchManifest {
              name = "fd";
              images = lib.genAttrs imageSystems (sys: inputs.self.packages.${sys}.fdContainer);
              registry = {
                name = "ghcr.io";
                repo = "cameronraysmith/vanixiets/fd";
                username = getEnvOr "GITHUB_ACTOR" "cameronraysmith";
                password = "$GITHUB_TOKEN";
              };
              version = getEnvOr "VERSION" "1.0.0";
              branch = getEnvOr "GITHUB_REF_NAME" "main";
              skopeo = skopeo-nix2container;
              podman = pkgs.podman;
            };

            rgManifest = mkMultiArchManifest {
              name = "rg";
              images = lib.genAttrs imageSystems (sys: inputs.self.packages.${sys}.rgContainer);
              registry = {
                name = "ghcr.io";
                repo = "cameronraysmith/vanixiets/rg";
                username = getEnvOr "GITHUB_ACTOR" "cameronraysmith";
                password = "$GITHUB_TOKEN";
              };
              version = getEnvOr "VERSION" "1.0.0";
              branch = getEnvOr "GITHUB_REF_NAME" "main";
              skopeo = skopeo-nix2container;
              podman = pkgs.podman;
            };
          }
        ))
      ];
    };
}

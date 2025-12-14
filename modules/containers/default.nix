# Multi-architecture container builds using flocken and nix-rosetta-builder
#
# This module provides:
# - Container packages (fdContainer, rgContainer) for Linux systems
# - Multi-arch manifests (fdManifest, rgManifest) for CI/CD registry distribution
#
# See docs/about/contributing/multi-arch-containers.md for usage guide.
{ inputs, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      isLinux = lib.hasSuffix "-linux" system;
      isDarwin = lib.hasSuffix "-darwin" system;

      # Build a minimal container image with a package
      # Makes it work like: docker run <name>:latest --version
      mkToolContainer =
        {
          name,
          package,
          tag ? "latest",
        }:
        pkgs.dockerTools.buildLayeredImage {
          inherit name tag;
          contents = [
            pkgs.bashInteractive
            pkgs.coreutils
            package
          ];
          config = {
            Entrypoint = [ "${package}/bin/${name}" ];
            Env = [
              "PATH=${package}/bin:${pkgs.coreutils}/bin:${pkgs.bashInteractive}/bin"
            ];
            Labels = {
              "org.opencontainers.image.description" = "Minimal container with ${name}";
              "org.opencontainers.image.source" = "https://github.com/cameronraysmith/infra";
            };
          };
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
            fdManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
              version = getEnvOr "VERSION" "1.0.0";
              branch = getEnvOr "GITHUB_REF_NAME" "main";
              imageFiles = map (sys: inputs.self.packages.${sys}.fdContainer) imageSystems;
              registries."ghcr.io" = {
                repo = "cameronraysmith/fd";
                username = getEnvOr "GITHUB_ACTOR" "cameronraysmith";
                password = "$GITHUB_TOKEN";
              };
            };

            rgManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
              version = getEnvOr "VERSION" "1.0.0";
              branch = getEnvOr "GITHUB_REF_NAME" "main";
              imageFiles = map (sys: inputs.self.packages.${sys}.rgContainer) imageSystems;
              registries."ghcr.io" = {
                repo = "cameronraysmith/rg";
                username = getEnvOr "GITHUB_ACTOR" "cameronraysmith";
                password = "$GITHUB_TOKEN";
              };
            };
          }
        ))
      ];
    };
}

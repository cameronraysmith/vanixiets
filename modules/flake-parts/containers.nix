{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      isLinux = pkgs.stdenv.isLinux;

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
              "org.opencontainers.image.source" = "https://github.com/cameronraysmith/nix-config";
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
      packages = lib.optionalAttrs isLinux {
        fdContainer = mkToolContainer {
          name = "fd";
          package = pkgs.fd;
        };

        rgContainer = mkToolContainer {
          name = "rg";
          package = pkgs.ripgrep;
        };
      };

      legacyPackages = {
        fdManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
          version = "latest";
          imageFiles = map (sys: inputs.self.packages.${sys}.fdContainer) imageSystems;
          registries = { };
          tags = [ "latest" ];
        };
      };
    };
}

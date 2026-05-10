# Multi-architecture container builds using nix2container with pkgsCross
#
# Architecture:
# - pkgsCross for cross-compilation (auto-optimizes to native when host == target)
# - nix2container builds JSON manifests with pre-computed layer digests
# - skopeo pushes via nix: transport, crane creates manifest lists
#
# Platform behavior:
# - x86_64-linux host: x86_64 native, aarch64 cross-compiled
# - aarch64-linux host: aarch64 native, x86_64 cross-compiled
# - aarch64-darwin host: both via rosetta-builder
#
# Performance: cross-compilation at native speed (no QEMU), push skips unchanged layers
{
  inputs,
  lib,
  ...
}:
let
  defaultTargetNames = [
    "x86_64"
    "aarch64"
  ];

  # Container definitions schema:
  #   name: Container/image name
  #   packages: List of package attribute names from nixpkgs
  #   entrypoint: Binary name for entrypoint (defaults to name)
  #   targets: Optional target list (defaults to defaultTargetNames)
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
  };
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      isLinux = lib.hasSuffix "-linux" system;
      isDarwin = lib.hasSuffix "-darwin" system;

      nix2container = inputs.nix2container.packages.${system}.nix2container;
      skopeo-nix2container = inputs.nix2container.packages.${system}.skopeo-nix2container; # has nix: transport
      mkMultiArchManifest = pkgs.callPackage ../../lib/mk-multi-arch-manifest.nix { };

      # Target architectures: system name, pkgsCross instance, OCI arch label
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

      selectTargets = targetNames: lib.filterAttrs (n: _: lib.elem n targetNames) allTargets;

      mkBaseLayerForTarget =
        target:
        nix2container.buildLayer {
          deps = [
            target.crossPkgs.bashInteractive
            target.crossPkgs.coreutils
          ];
        };

      # Layer strategy: base (bash, coreutils) rarely changes; app layer changes per container
      mkContainerForTarget =
        {
          name,
          packages,
          entrypoint ? name,
          target,
          tag ? "latest",
        }:
        let
          resolvedPackages = map (pkgName: target.crossPkgs.${pkgName}) packages;
          entrypointPackage = target.crossPkgs.${builtins.head packages};
          baseLayer = mkBaseLayerForTarget target;
          packagePaths = lib.concatMapStringsSep ":" (pkg: "${pkg}/bin") resolvedPackages;
        in
        nix2container.buildImage {
          inherit name tag;
          arch = target.arch;
          layers = [ baseLayer ];
          copyToRoot = target.crossPkgs.buildEnv {
            # strips /nix/store prefix
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
          maxLayers = 2;
        };

      getContainerTargets = def: def.targets or defaultTargetNames;

      # Generates: fdContainer-x86_64, fdContainer-aarch64, rgContainer-x86_64, etc.
      containerPackages = lib.listToAttrs (
        lib.flatten (
          lib.mapAttrsToList (
            containerName: def:
            let
              containerTargets = getContainerTargets def;
              selectedTargets = selectTargets containerTargets;
            in
            lib.mapAttrsToList (targetName: target: {
              name = "${containerName}Container-${targetName}";
              value = mkContainerForTarget (def // { inherit target; });
            }) selectedTargets
          ) containerDefs
        )
      );

      # Env var helpers (require --impure)
      getEnvOr =
        var: default:
        let
          val = builtins.getEnv var;
        in
        if val == "" then default else val;
      getEnvList =
        var:
        let
          val = builtins.getEnv var;
        in
        if val == "" then [ ] else lib.splitString "," val;

      # Manifest generation. Env vars: VERSION, TAGS (comma-separated), GITHUB_REF_NAME
      mkManifest =
        {
          containerName,
          targetNames ? null,
        }:
        let
          actualTargetNames =
            if targetNames != null then targetNames else getContainerTargets containerDefs.${containerName};
          selectedTargets = selectTargets actualTargetNames;
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
          tags = getEnvList "TAGS";
          branch = getEnvOr "GITHUB_REF_NAME" "main";
          skopeo = skopeo-nix2container;
        };

      manifestPackages = lib.listToAttrs (
        lib.flatten (
          lib.mapAttrsToList (
            containerName: def:
            let
              containerTargets = getContainerTargets def;
              selectedTargets = selectTargets containerTargets;
            in
            [
              {
                name = "${containerName}Manifest";
                value = mkManifest { inherit containerName; };
              }
            ]
            ++ lib.mapAttrsToList (targetName: _: {
              name = "${containerName}Manifest-${targetName}";
              value = mkManifest {
                inherit containerName;
                targetNames = [ targetName ];
              };
            }) selectedTargets
          ) containerDefs
        )
      );

    in
    {
      # Linux hosts expose container variants under packages.<system>.* so that
      # `nix flake check`, nix-fast-build, and buildbot-nix discover and (where
      # appropriate) realize them. These packages target *-linux derivations and
      # build natively on a matching Linux host.
      #
      # Darwin hosts expose the same attributes under legacyPackages.<system>.*
      # because every container's resolved package set forces aarch64-linux
      # cross-derivations whose installCheckPhase calls
      # `stdenv.hostPlatform.emulator buildPackages`, which throws on Darwin
      # without an aarch64-linux emulator. `nix flake check` walks packages.*
      # strictly (per `man nix3-flake-check`) but legacyPackages.* lazily, so
      # routing the Darwin exposure through legacyPackages avoids forcing
      # installCheckPhase at eval time. Realization is unaffected: Nix's
      # remote-builder selection keys off derivation.system, so rosetta-builder
      # serves these aarch64-linux derivations regardless of which output set
      # the attribute lives in. `nix build .#fdContainer-aarch64` continues to
      # resolve via the standard installable lookup chain
      # (packages.<sys>.X -> legacyPackages.<sys>.X -> X), so justfile recipes
      # need no edits.
      #
      # Usage: VERSION=1.0.0 nix run --impure .#fdManifest
      packages = lib.mkMerge [
        (lib.optionalAttrs isLinux containerPackages)
        (lib.optionalAttrs isLinux manifestPackages)
      ];
      legacyPackages = lib.mkMerge [
        (lib.optionalAttrs isDarwin containerPackages)
        (lib.optionalAttrs isDarwin manifestPackages)
      ];
    };

  # CI matrix data (pure evaluation): nix eval .#containerMatrix --json
  flake.containerMatrix = {
    build = lib.flatten (
      lib.mapAttrsToList (
        containerName: def:
        map (targetName: {
          container = containerName;
          target = targetName;
        }) (def.targets or defaultTargetNames)
      ) containerDefs
    );
    manifest = lib.attrNames containerDefs;
  };
}

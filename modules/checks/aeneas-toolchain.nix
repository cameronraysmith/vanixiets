# Parity check for the committed rust-toolchain marker against the aeneas bundles.
#
# modules/nixpkgs/overlays/aeneas.nix seeds a slim host nightly from the
# committed ./rust-toolchain marker beside it, while the prebuilt charon-driver
# inside each release bundle is already linked against the librustc_driver of
# the channel recorded in the bundle's own top-level rust-toolchain. The two
# must name the same channel, or charon-driver resolves a librustc_driver it was
# not linked against.
#
# On darwin the mismatch builds successfully — the rpath edit and re-sign apply
# to whatever toolchain the marker names — and surfaces only at runtime as a
# dyld "Library not loaded: @rpath/librustc_driver-<hash>.dylib". darwin checks
# are best-effort in CI (modules/checks/nixbot-best-effort-darwin.nix), so the
# check runs on x86_64-linux over every platform's bundle: the bundles are
# fixed-output downloads, so a Linux builder fetches the darwin tarball too and
# the darwin case gates.
#
# The comparison happens inside a derivation, unpacking each bundle's marker in
# a build rather than at eval time, because the repo avoids
# import-from-derivation.
{ lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        aeneas-toolchain-marker =
          pkgs.runCommand "aeneas-toolchain-marker"
            {
              inherit (pkgs.charon.passthru) rustChannel;
              bundles = lib.concatStringsSep " " (
                lib.mapAttrsToList (platform: bundle: "${platform}=${bundle}") pkgs.charon.passthru.bundles
              );
            }
            ''
              set -euo pipefail

              for entry in $bundles; do
                platform=''${entry%%=*}
                bundle=''${entry#*=}

                tar tzf "$bundle" > entries.txt
                marker=$(awk '/^(\.\/)?rust-toolchain$/ { print; exit }' entries.txt)
                if [ -z "$marker" ]; then
                  echo "aeneas-toolchain-marker: no top-level rust-toolchain in the $platform bundle $bundle" >&2
                  echo "The bundle layout changed; the version bump procedure at the top of" >&2
                  echo "modules/nixpkgs/overlays/aeneas.nix needs revisiting." >&2
                  exit 1
                fi

                tar xzOf "$bundle" "$marker" > bundle-marker.toml
                bundleChannel=$(awk -F'"' '/^[[:space:]]*channel[[:space:]]*=/ { print $2; exit }' bundle-marker.toml)
                if [ -z "$bundleChannel" ]; then
                  echo "aeneas-toolchain-marker: no channel key in the $platform bundle's $marker" >&2
                  cat bundle-marker.toml >&2
                  exit 1
                fi

                if [ "$bundleChannel" != "$rustChannel" ]; then
                  echo "aeneas-toolchain-marker: rust-toolchain channel drift ($platform)" >&2
                  echo "  committed modules/nixpkgs/overlays/rust-toolchain: $rustChannel" >&2
                  echo "  bundle $marker ($bundle): $bundleChannel" >&2
                  echo >&2
                  echo "The committed marker seeds the slim host toolchain supplying the" >&2
                  echo "librustc_driver that the prebuilt charon-driver links against, so a" >&2
                  echo "mismatch links the wrong library. On linux autoPatchelf fails the" >&2
                  echo "build; on darwin the build succeeds and charon fails at runtime with" >&2
                  echo "dyld: Library not loaded: @rpath/librustc_driver-<hash>.dylib" >&2
                  echo >&2
                  echo "Remediation: set channel = \"$bundleChannel\" in" >&2
                  echo "modules/nixpkgs/overlays/rust-toolchain, then re-verify charon-driver's" >&2
                  echo "rpath and re-signing wiring per the version bump procedure at the top of" >&2
                  echo "modules/nixpkgs/overlays/aeneas.nix." >&2
                  exit 1
                fi
              done

              echo "$rustChannel" > $out
            '';
      };
    };
}

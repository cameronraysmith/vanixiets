# buzz - shared source tree and vendored cargo dependencies.
#
# buzz-cli, buzz-git-credential-nostr and buzz-git-sign-nostr take
# `buzz-source` as a plain callPackage argument, so this pin drives all four.
#
# The tag is the newest non-prerelease trunk snapshot carrying a GitHub
# Release. It is not parity with the installed desktop app: upstream cuts
# releases on a desktop cadence, so pinning here couples our CLI packages to a
# train that carries no CLI-side semantics. The cargo workspace version is
# frozen at 0.1.0, so `version` is the release-train number rather than
# anything the built binaries report.
#
# No consumer uses versionCheckHook, because no binary here accepts a version
# flag. buzz-cli's clap command block registers no `version` key, so
# `--version` is an UnknownArgument that exits 1. git-credential-nostr has no
# argument parser at all beyond a first-positional match. git-sign-nostr
# silently ignores unrecognized arguments and then exits 1 on the usage error,
# so neither `--version` nor `--help` reaches a successful exit there.
#
# passthru.cargoDeps is the single vendored dependency set shared by all three
# consumers. A consumer inherits it and must never also set cargoHash: the
# precedence chain in build-rust-package/default.nix:104-113 tests
# cargoVendorDir, then cargoDeps, then cargoLock, then cargoHash, so a non-null
# cargoDeps short-circuits before cargoHash is read and a stale or fabricated
# hash sitting beside it would never produce an error.
#
# The version and both hashes are in pin.json, which realize-pin rewrites.
# passthru.src is this fetch itself: the realizer hashes `.#buzz-source.src`,
# and this package has no other src to name.
#
# Source: https://github.com/block/buzz
{
  lib,
  fetchFromGitHub,
  rustPlatform,
}:
let
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "buzz-source"; })
    pin
    pinPlan
    ;
  planned = (pinPlan pin.version).artifacts;
  inherit (pin.artifacts.src) sourceBuild;
  inherit (pin) version;

  # Self-reference is safe because `passthru` never becomes a derivation input:
  # fetchFromGitHub forwards it to the fetcher (fetchgithub/default.nix:210-213)
  # and mkDerivation excludes it from the derivation proper, so forcing
  # `self.passthru.cargoDeps` does not force a cycle through `self`.
  self = fetchFromGitHub (
    planned.src.sourceBuild.fetchFromGitHub
    // {
      name = "buzz-source-${version}";
      inherit (sourceBuild) hash;

      passthru = {
        inherit version pin pinPlan;
        src = self;

        cargoDeps = rustPlatform.fetchCargoVendor {
          src = self;
          inherit (sourceBuild.depsHash.cargo) hash;
        };
      };
    }
  );
in
self

# buzz - shared source tree and vendored cargo dependencies.
#
# Sibling packages in this directory take `source` as a plain callPackage
# argument; the nested pkgs-by-name scope resolves it to this derivation.
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
# Source: https://github.com/block/buzz
{
  fetchFromGitHub,
  rustPlatform,
}:
let
  version = "0.5.26";

  # Self-reference is safe because `passthru` never becomes a derivation input:
  # fetchFromGitHub forwards it to the fetcher (fetchgithub/default.nix:210-213)
  # and mkDerivation excludes it from the derivation proper, so forcing
  # `self.passthru.cargoDeps` does not force a cycle through `self`.
  self = fetchFromGitHub {
    name = "buzz-source-${version}";
    owner = "block";
    repo = "buzz";
    tag = "desktop-v${version}";
    hash = "sha256-w/CHknkyFT+iHv4jd5Anv1Q/5kOZ7H1DEKB9dwqQHiE=";

    passthru = {
      inherit version;
      rev = "2b4b138dc5cf2d9cc1a0ceb21d9063ff56fe8bf4";

      cargoDeps = rustPlatform.fetchCargoVendor {
        src = self;
        hash = "sha256-A/lpudjM3ZahSNiWHxW8UKFlBhdBuAEQL87c8Q+C7Q4=";
      };

      updateScript = ./update.sh;
    };
  };
in
self

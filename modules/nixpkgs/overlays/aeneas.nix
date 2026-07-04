# aeneas + the rust charon frontend, surfaced as top-level packages.
#
# These install the upstream AeneasVerif/aeneas PREBUILT release bundle rather than
# building charon/aeneas from source. The per-platform `aeneas-*.tar.gz` release asset
# is a self-contained bundle carrying `aeneas`, `charon`, `charon-driver`,
# `backends/{coq,fstar,hol4,lean}`, a `rust-toolchain` marker, and (on macOS) `libs/`.
# The Lean backend is intentionally NOT wired here; elan/lake own it on stibnite.
#
# Version bump procedure (all four values live where noted):
#   1. `tag` below            — the release tag (github:AeneasVerif/aeneas releases).
#   2. `assets.<system>.hash` — the three per-platform tarball sha256 (hex); a wrong
#                               value fails the fetch loudly. Confirm via
#                               `gh release view <tag> -R AeneasVerif/aeneas --json assets`.
#   3. ./rust-toolchain       — the committed nightly-channel marker beside this file
#                               (must equal the channel in the bundle's own `rust-toolchain`);
#                               its `channel` seeds the slim host toolchain whose
#                               librustc_driver must match charon-driver byte-for-byte.
# On a bump also re-verify the darwin re-signing/rpath wiring still applies (upstream
# could change how charon-driver is linked).
#
# Runtime wiring reused verbatim from the prior source-build overlay:
#   - `charon` (frontend) links libiconv only but panics demanding rustup unless
#     CHARON_TOOLCHAIN_IS_IN_PATH=1 and a complete matching nightly toolchain
#     (rustc + cargo + miri) are on PATH; the wrapper supplies both. CHARON_MIRI_SYSROOTS=""
#     makes charon-driver do a runtime `cargo miri setup` (driver.rs treats empty as
#     "no baked sysroot") rather than expecting a baked one.
#   - `charon-driver` references @rpath/librustc_driver-<hash>.dylib; the bundle bakes an
#     LC_RPATH to the build machine's rustc store path (absent on target). On darwin we
#     add an rpath to our slim toolchain's lib and re-sign (install_name_tool invalidates
#     the adhoc signature); on linux autoPatchelfHook resolves it from the toolchain.
#   - The bundle's charon/charon-driver bake two build-machine nix-store paths for
#     libiconv/libz; on darwin we re-point them into this derivation's own closure via
#     install_name_tool -change (discovered from otool output so a version bump needs no
#     path edits here) + re-sign; linux autoPatchelf handles it.
#
# The slim toolchain is host-only: charon-driver only links the host librustc_driver and
# the runtime `cargo miri setup` only needs the host target, so a host-only nightly is
# byte-identical for what gets linked while dropping the ~9 GiB of cross-target std/
# rustc-dev the bundle's own 8-target marker would otherwise pull. The channel is read
# from the committed ./rust-toolchain marker (the source-build overlay read charon's own
# rust-toolchain file, which disappears with the removed aeneas flake input).
{ inputs, ... }:
{
  nixpkgsOverlays = [
    (
      final: prev:
      let
        lib = prev.lib;

        tag = "nightly-2026.07.04-45061fa";
        assets = {
          aarch64-darwin = {
            name = "aeneas-macos-aarch64.tar.gz";
            hash = "8f228800ead5d45cf6c709ad9322a49e118ed6b2fef0bfd88dd4c5300849ce29";
          };
          x86_64-linux = {
            name = "aeneas-linux-x86_64.tar.gz";
            hash = "21e138b6367186257a3b1b8829b0def3a4ba09d66930db73b4e5fe276a0227e4";
          };
          aarch64-linux = {
            name = "aeneas-linux-aarch64.tar.gz";
            hash = "a581a0f190dc0d35d6e2c46ac6df0580996603678fa5c6d6c4c960998af44e61";
          };
        };

        inherit (prev.stdenv.hostPlatform) system;
        isDarwin = prev.stdenv.hostPlatform.isDarwin;
        asset = assets.${system} or (throw "aeneas: unsupported system ${system}");

        bundle = prev.fetchurl {
          url = "https://github.com/AeneasVerif/aeneas/releases/download/${tag}/${asset.name}";
          sha256 = asset.hash;
        };

        # Host-only slim nightly whose librustc_driver matches charon-driver byte-for-byte;
        # channel sourced from the committed marker beside this file.
        rustChannel = (builtins.fromTOML (builtins.readFile ./rust-toolchain)).toolchain.channel;
        rustDate = lib.removePrefix "nightly-" rustChannel;
        rustPkgs = prev.appendOverlays [ (import inputs.rust-overlay) ];
        slimRustToolchain = rustPkgs.rust-bin.nightly.${rustDate}.minimal.override {
          extensions = [
            "rustc-dev"
            "llvm-tools-preview"
            "rust-src"
            "miri"
          ];
          targets = [ prev.stdenv.hostPlatform.rust.rustcTarget ];
        };

        commonAttrs = {
          version = tag;
          src = bundle;
          sourceRoot = ".";
          dontConfigure = true;
          dontBuild = true;
        };

        aeneasPkg = prev.stdenv.mkDerivation (
          commonAttrs
          // {
            pname = "aeneas";
            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              cp aeneas $out/bin/aeneas
              # macOS aeneas resolves libgmp via @executable_path/libs; keep libs/ beside
              # the binary. linux aeneas is static-musl and ships no libs/.
              if [ -d libs ]; then
                cp -r libs $out/bin/libs
              fi
              runHook postInstall
            '';
          }
        );

        charonPkg = prev.stdenv.mkDerivation (
          commonAttrs
          // {
            pname = "charon";

            nativeBuildInputs = [
              prev.makeWrapper
            ]
            ++ lib.optionals isDarwin [
              prev.bintools
              prev.darwin.sigtool
            ]
            ++ lib.optionals prev.stdenv.hostPlatform.isLinux [ prev.autoPatchelfHook ];

            buildInputs = lib.optionals prev.stdenv.hostPlatform.isLinux [
              slimRustToolchain
              prev.stdenv.cc.cc.lib
              prev.zlib
            ];

            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              cp charon charon-driver $out/bin/
              chmod u+w $out/bin/charon $out/bin/charon-driver
            ''
            + lib.optionalString isDarwin ''
              # Re-point the bundle's baked build-machine libiconv/libz into this closure,
              # then re-add the toolchain rpath for charon-driver and re-sign (each
              # install_name_tool edit invalidates the adhoc signature).
              for bin in charon charon-driver; do
                otool -L "$out/bin/$bin" | awk 'NR>1{print $1}' | while read -r dep; do
                  case "$dep" in
                    /nix/store/*-libiconv-*/lib/libiconv*.dylib)
                      install_name_tool -change "$dep" "${prev.libiconv}/lib/libiconv.2.dylib" "$out/bin/$bin" ;;
                    /nix/store/*-zlib-*/lib/libz*.dylib)
                      install_name_tool -change "$dep" "${prev.zlib}/lib/libz.dylib" "$out/bin/$bin" ;;
                  esac
                done
              done
              install_name_tool -add_rpath "${slimRustToolchain}/lib" "$out/bin/charon-driver"
              codesign -f -s - "$out/bin/charon"
              codesign -f -s - "$out/bin/charon-driver"
            ''
            + ''
              wrapProgram $out/bin/charon \
                --set CHARON_TOOLCHAIN_IS_IN_PATH 1 \
                --set CHARON_MIRI_SYSROOTS "" \
                --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ slimRustToolchain ]}" \
                --prefix PATH : "${lib.makeBinPath [ slimRustToolchain ]}"
              runHook postInstall
            '';

            # charon-driver's librustc_driver is resolved from the slim toolchain.
            runtimeDependencies = lib.optionals prev.stdenv.hostPlatform.isLinux [ slimRustToolchain ];

            meta = {
              description = "Charon frontend (prebuilt) for the Aeneas verification toolchain";
              platforms = builtins.attrNames assets;
            };
          }
        );
      in
      {
        charon = charonPkg;

        aeneas =
          if isDarwin then
            # Co-locate charon for the stibnite consumer (which installs both, with charon
            # at hiPrio to win this collision), matching the prior overlay's structure.
            aeneasPkg.overrideAttrs (old: {
              installPhase = old.installPhase + ''
                ln -s ${charonPkg}/bin/charon $out/bin/charon
              '';
            })
          else
            aeneasPkg;
      }
    )
  ];
}

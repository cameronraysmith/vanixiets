# aeneas + the rust charon frontend, surfaced as top-level packages.
#
# Charon PR #1309 hoisted the runtime wrapper out of nix/charon.nix into flake.nix:
# packages.charon is now a runCommand that copies charon-unwrapped and re-runs
# wrapProgram, so it exposes no .override, and that wrapper unconditionally bakes
# fullMirSysroots, a fixed-output derivation that hardcodes the Linux sandbox path
# /build (unbuildable on macOS). On darwin we therefore rebuild from the still-
# overridable charon-unwrapped and re-apply upstream's flake.nix wrapper by hand,
# with three darwin workarounds; linux uses charonFlake's default charon.
#  1. drop the /build FOD: charon-unwrapped is overridden with miriSysroots="", and
#     our re-applied wrapper never references fullMirSysroots.
#  2. set CHARON_MIRI_SYSROOTS to an empty string rather than null: charon-driver
#     treats an empty value as no baked sysroot (driver.rs setup_miri_sysroot) and
#     does a runtime `cargo miri setup`. Since we author the wrapper ourselves the
#     old "null produces a dangling `\` in charon.nix's wrapProgram" rationale no
#     longer applies; charon.nix still gates its own CHARON_MIRI_SYSROOTS export on
#     miriSysroots != null.
#  3. charon-unwrapped's checkPhase `cargo test` invokes the binary, which needs a
#     sysroot it cannot build in the read-only sandbox (golden outputs are linux-
#     specific too). doCheck=false skips it; the binary is validated by upstream's
#     linux CI.
# The transitive charon input tracks aeneas's own charon pin, preserving llbc compat.
#
# On darwin the runtime closure is further slimmed by feeding our re-applied wrapper's
# LD_LIBRARY_PATH/PATH and the charon-driver rpath a host-only minimal toolchain
# instead of the 7-target nightly charon declares (rustc-dev/rust-std for x86_64/
# aarch64-darwin, x86_64/i686/powerpc64-linux, windows-msvc, riscv64 plus rust-docs).
# charon-driver only links the host librustc_driver and the runtime `cargo miri setup`
# only needs the host target, so a host-only toolchain is byte-identical for what gets
# linked while dropping ~9 GiB of unused cross-target std/rustc-dev and rust-docs. The
# tradeoff is no cross-target MIR extraction (irrelevant for host-platform verification).
# The slim toolchain feeds only the wrapper, so this does not recompile charon. The
# nightly channel is read from charon's own rust-toolchain file so the slim toolchain
# auto-tracks charon's bumps and stays byte-compatible.
{ inputs, ... }:
{
  nixpkgsOverlays = [
    (
      final: prev:
      let
        charonFlake = inputs.aeneas.inputs.charon;
        # Derive the nightly channel from charon's own rust-toolchain file so the slim
        # toolchain's librustc_driver matches byte-for-byte what charon-driver links;
        # auto-tracks charon's toolchain bumps. charon always pins a nightly (needs rustc-dev).
        rustChannel =
          (builtins.fromTOML (builtins.readFile "${charonFlake}/rust-toolchain")).toolchain.channel;
        rustDate = prev.lib.removePrefix "nightly-" rustChannel;
        rustPkgs = prev.appendOverlays [ (import charonFlake.inputs.rust-overlay) ];
        # host-only minimal toolchain: charon-driver only links the host librustc_driver and
        # the runtime `cargo miri setup` only needs the host target. The full 7-target
        # toolchain charon declares would add ~9 GiB (rustc-dev/rust-std x7 + rust-docs) to
        # the runtime closure via the re-applied wrapper below.
        slimRustToolchain = rustPkgs.rust-bin.nightly.${rustDate}.minimal.override {
          extensions = [
            "rustc-dev"
            "llvm-tools-preview"
            "rust-src"
            "miri"
          ];
          targets = [ prev.stdenv.hostPlatform.rust.rustcTarget ];
        };
        charonForPlatform =
          let
            charonPkgs = charonFlake.packages.${prev.stdenv.hostPlatform.system};
          in
          if prev.stdenv.hostPlatform.isDarwin then
            let
              charonUnwrapped =
                (charonPkgs.charon-unwrapped.override {
                  miriSysroots = "";
                }).overrideAttrs
                  (_: {
                    doCheck = false;
                  });
            in
            # Re-apply charon's flake.nix runCommand wrapper by hand, copying our
            # overridden charon-unwrapped and pointing the toolchain paths at the slim
            # host-only toolchain instead of the fullMirSysroots-baked upstream one.
            prev.runCommand "charon"
              {
                nativeBuildInputs = [
                  prev.makeWrapper
                  prev.bintools
                ];
                passthru = charonUnwrapped.passthru;
              }
              ''
                cp -r ${charonUnwrapped} $out
                chmod -R u+w $out

                wrapProgram $out/bin/charon \
                  --set CHARON_TOOLCHAIN_IS_IN_PATH 1 \
                  --set CHARON_MIRI_SYSROOTS "" \
                  --prefix LD_LIBRARY_PATH : "${prev.lib.makeLibraryPath [ slimRustToolchain ]}" \
                  --prefix PATH : "${prev.lib.makeBinPath [ slimRustToolchain ]}"

                install_name_tool -add_rpath "${slimRustToolchain}/lib" "$out/bin/charon-driver"
              ''
          else
            charonPkgs.charon;
      in
      {
        charon = charonForPlatform;

        aeneas =
          let
            a = inputs.aeneas.packages.${prev.stdenv.hostPlatform.system}.aeneas;
          in
          if prev.stdenv.hostPlatform.isDarwin then
            a.overrideAttrs (_: {
              postInstall = "ln -s ${charonForPlatform}/bin/charon $out/bin";
            })
          else
            a;
      }
    )
  ];
}

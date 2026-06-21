# aeneas + the rust charon frontend, surfaced as top-level packages.
#
# Charon's nix build (AeneasVerif/charon PR #1279) has three darwin breakages worked
# around here until fixed upstream; linux uses the defaults:
#  1. default charon bakes charon-full-mir-sysroots, a fixed-output derivation that
#     hardcodes the Linux sandbox path /build (unbuildable on macOS). A non-default
#     miriSysroots drops it.
#  2. charon.nix's wrapProgram dangles a `\` when the CHARON_MIRI_SYSROOTS line is empty
#     (which miriSysroots=null produces), breaking the wrapper. miriSysroots="" keeps the
#     line non-empty; charon-driver treats an empty CHARON_MIRI_SYSROOTS as no baked
#     sysroot (driver.rs setup_miri_sysroot) and does a runtime `cargo miri setup`.
#  3. charon's checkPhase `cargo test` invokes the binary, which needs a sysroot it cannot
#     build in the read-only sandbox (golden outputs are linux-specific too). doCheck=false
#     skips it; the binary is validated by upstream's linux CI.
# The transitive charon input tracks aeneas's own charon pin, preserving llbc compat.
#
# On darwin the runtime closure is further slimmed by overriding charon's rustToolchain
# with a host-only minimal toolchain. charon declares a 7-target nightly (rustc-dev/rust-std
# for x86_64/aarch64-darwin, x86_64/i686/powerpc64-linux, windows-msvc, riscv64 plus rust-docs),
# baked into the runtime closure by charon.nix's wrapper postFixup. charon-driver only links
# the host librustc_driver and the runtime `cargo miri setup` only needs the host target, so a
# host-only toolchain is byte-identical for what gets linked while dropping ~9 GiB of unused
# cross-target std/rustc-dev and rust-docs. The tradeoff is no cross-target MIR extraction
# (irrelevant for host-platform verification). rustToolchain feeds only the wrapper, so this
# does not recompile charon. The nightly channel is read from charon's own rust-toolchain file
# so the slim toolchain auto-tracks charon's bumps and stays byte-compatible.
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
        # the runtime closure via charon.nix's wrapper.
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
            c = charonFlake.packages.${prev.stdenv.hostPlatform.system}.charon;
          in
          if prev.stdenv.hostPlatform.isDarwin then
            (c.override {
              miriSysroots = "";
              rustToolchain = slimRustToolchain;
            }).overrideAttrs
              (_: {
                doCheck = false;
              })
          else
            c;
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

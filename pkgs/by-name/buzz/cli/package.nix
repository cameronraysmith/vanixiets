# buzz-cli - command-line client for a Buzz relay.
#
# reqwest 0.13's `rustls` feature implies `__rustls-aws-lc-rs`, so aws-lc-sys
# is in the build. Newer nixpkgs' cargo setup hook exports
# AWS_LC_SYS_USE_SYSTEM=1, so aws-lc-sys links the aws-lc in buildInputs,
# located through pkg-config. Where nixpkgs does not export it, aws-lc-sys
# compiles AWS-LC from source with its CcBuilder backend;
# AWS_LC_SYS_CMAKE_BUILDER forces the cmake backend instead, matching nixpkgs'
# own unconditional aws-lc-sys crate override (default-crate-overrides.nix:58-62),
# whose comment notes the cc backend fails at least on Darwin. cmake is
# therefore a build tool here rather than the build system, hence
# dontUseCmakeConfigure.
#
# The attribute and pname are buzz-cli while the binary is buzz. mainProgram is
# set, so lib.getExe resolves correctly and `nix run` works. Consumers should
# still prefer `lib.getExe' pkgs.buzz-cli "buzz"`, because getExe falls back to
# getName when mainProgram is absent (lib/meta.nix:525-537): an edit that drops
# mainProgram would leave a deprecation warning easily lost in a large
# evaluation and a path to a nonexistent /bin/buzz-cli, whereas getExe' names
# the binary at the call site and cannot drift.
#
# Source: https://github.com/block/buzz
{
  lib,
  rustPlatform,
  source,
  cmake,
  pkg-config,
  aws-lc,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "buzz-cli";
  inherit (source) version cargoDeps;
  src = source;

  # --bin names the expected binary explicitly. Redundant at this pin, where the
  # crate declares exactly one [[bin]], but it makes an upstream addition of a
  # second binary change the install set visibly instead of silently.
  cargoBuildFlags = [
    "-p"
    "buzz-cli"
    "--bin"
    "buzz"
  ];

  nativeBuildInputs = [
    cmake
    pkg-config
  ];
  buildInputs = [ aws-lc ];
  dontUseCmakeConfigure = true;

  env.AWS_LC_SYS_CMAKE_BUILDER = "1";

  doCheck = false;

  doInstallCheck = true;
  # --help exits 0 here. --version does not: the clap command block registers no
  # `version` key, so it is an UnknownArgument that exits 1.
  installCheckPhase = ''
    runHook preInstallCheck

    "$out/bin/buzz" --help > /dev/null

    runHook postInstallCheck
  '';

  meta = {
    homepage = "https://github.com/block/buzz";
    description = "Command-line client for a Buzz relay";
    changelog = "https://github.com/block/buzz/releases/tag/desktop-v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "buzz";
    maintainers = with lib.maintainers; [ cameronraysmith ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})

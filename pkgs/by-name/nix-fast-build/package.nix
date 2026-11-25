{
  lib,
  fetchFromGitHub,
  python3Packages,
  nix-eval-jobs,
  bashInteractive,
}:
let
  inherit
    ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "nix-fast-build"; })
    pin
    pinPlan
    ;
  planned = (pinPlan pin.version).artifacts;
in
python3Packages.buildPythonApplication (finalAttrs: {
  pname = "nix-fast-build";
  inherit (pin) version;
  pyproject = true;

  src = fetchFromGitHub (
    planned.src.sourceBuild.fetchFromGitHub // { inherit (pin.artifacts.src.sourceBuild) hash; }
  );

  build-system = [ python3Packages.setuptools ];

  # 2.x renders build logs itself and no longer uses nix-output-monitor.
  # Separate elements: with __structuredAttrs (buildPythonPackage's default since
  # nixpkgs 26.11) makeWrapperArgs is not word-split.
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [
      nix-eval-jobs
      nix-eval-jobs.nix
      bashInteractive
    ])
  ];

  # Don't run integration tests as they try to run nix
  # to build stuff, which we cannot do inside the sandbox.
  checkPhase = ''
    PYTHONPATH= $out/bin/nix-fast-build --help
  '';

  postFixup = ''
    # don't leak python into devshell
    rm $out/nix-support/propagated-build-inputs
  '';

  passthru = {
    inherit pin pinPlan;
  };

  meta = {
    description = "Speed up your Nix evaluation and building process with parallel evaluation and building";
    homepage = "https://github.com/Mic92/nix-fast-build";
    changelog = "https://github.com/Mic92/nix-fast-build/releases/tag/${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      getchoo
      mic92
    ];
    mainProgram = "nix-fast-build";
  };
})

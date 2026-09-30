{
  lib,
  fetchFromGitHub,
  python3Packages,
  nix-eval-jobs,
  nix-update-script,
  bashInteractive,
}:

python3Packages.buildPythonApplication (finalAttrs: {
  pname = "nix-fast-build";
  version = "2.0.4";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "Mic92";
    repo = "nix-fast-build";
    tag = finalAttrs.version;
    hash = "sha256-sc/NZIHkRhgyAzK8Xn6G++vGrl/Uf7QHh+J5fnZ/o4s=";
  };

  build-system = [ python3Packages.setuptools ];

  # 2.x renders build logs itself and no longer uses nix-output-monitor.
  makeWrapperArgs = [
    "--prefix PATH : ${
      lib.makeBinPath [
        nix-eval-jobs
        nix-eval-jobs.nix
        bashInteractive
      ]
    }"
  ];

  # Don't run integration tests as they try to run nix
  # to build stuff, which we cannot do inside the sandbox.
  checkPhase = ''
    PYTHONPATH= $out/bin/nix-fast-build --help
  '';

  passthru = {
    updateScript = nix-update-script { };
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

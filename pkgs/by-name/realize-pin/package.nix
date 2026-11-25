# realize-pin: rewrites a package's pin.json and its typed companion files for
# one version (automate-package-version-bumps design D4, D5). Renovate runs it
# as its post-upgrade task; `nix run .#realize-pin -- <package> <version>` runs
# it by hand from the repository root.
#
# The offline tests and the strict basedpyright run are
# checks.x86_64-linux.realize-pin-tests (modules/checks/realize-pin-tests.nix).
{
  lib,
  python3Packages,
  cacert,
  git,
  nix,
  nix-update,
}:
python3Packages.buildPythonApplication {
  pname = "realize-pin";
  version = "0.1.0";
  pyproject = true;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./src
    ];
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = [
    python3Packages.beartype
    python3Packages.expression
  ];

  # nix-update is prefixed: the fixed-output hasher needs 1.17.0 or later
  # (pkgs/by-name/nix-update until nixpkgs ships it), whatever the caller has.
  # nix and git are suffixed so that the caller's, which match its daemon and
  # configuration, take precedence. Separate elements: with __structuredAttrs
  # makeWrapperArgs is not word-split.
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [ nix-update ])
    "--suffix"
    "PATH"
    ":"
    (lib.makeBinPath [
      git
      nix
    ])
    "--set-default"
    "SSL_CERT_FILE"
    "${cacert}/etc/ssl/certs/ca-bundle.crt"
  ];

  pythonImportsCheck = [ "realize_pin.cli" ];

  meta = {
    description = "Realize one version of a package pin: rewrite pin.json and its typed companions";
    mainProgram = "realize-pin";
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
}

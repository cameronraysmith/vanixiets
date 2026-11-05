{
  inputs,
  lib,
  stdenv,
  runCommand,
  jq,
  # Not named `omp`: callPackage would fill that from nixpkgs' own omp, a
  # different version from the one the omp home module installs. The home
  # module overrides this with programs.omp.package so the extension's stamp
  # always matches the omp that runs the relay.
  ompPackage ? inputs.llm-agents.packages.${stdenv.hostPlatform.system}.omp,
}:
runCommand "omp-browser-relay-extension-${ompPackage.version}"
  {
    nativeBuildInputs = [
      ompPackage
      jq
    ];

    meta = {
      description = "omp's browser relay Chrome extension, as written by `omp browser-relay install`";
      inherit (ompPackage.meta) platforms;
    };
  }
  ''
    export HOME=$TMPDIR
    omp browser-relay install --dir "$out"

    expected='const OMP_INSTALL_VERSION = "${ompPackage.version}";'
    actual=$(head -n 1 "$out/background.js")
    if [ "$actual" != "$expected" ]; then
      echo "omp-browser-relay-extension: background.js stamp is '$actual', expected '$expected'" >&2
      exit 1
    fi

    versionName=$(jq -r .version_name "$out/manifest.json")
    if [ "$versionName" != ${lib.escapeShellArg ompPackage.version} ]; then
      echo "omp-browser-relay-extension: manifest.json version_name is '$versionName', expected '${ompPackage.version}'" >&2
      exit 1
    fi
  ''

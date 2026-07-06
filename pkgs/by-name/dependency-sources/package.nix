{
  lib,
  writeShellApplication,
  jq,
  coreutils,
  python3,
}:
writeShellApplication {
  name = "dependency-sources";
  runtimeInputs = [
    jq
    coreutils
    python3
  ];
  text = builtins.readFile ./dependency-sources.sh;
  meta = {
    description = "Extract normalized git-forge source URLs of a workspace's first-order dependencies for ghq get";
    license = lib.licenses.mit;
    mainProgram = "dependency-sources";
  };
}

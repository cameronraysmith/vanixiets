{
  lib,
  writeShellApplication,
  ghq,
  git,
  coreutils,
  zoxide,
}:
writeShellApplication {
  name = "ghq-sync";
  runtimeInputs = [
    ghq
    git
    coreutils
    zoxide
  ];
  text = builtins.readFile ./ghq-sync.sh;
  meta = {
    description = "Lazy, partial-clone-aware ghq wrapper for fetching, updating, deepening, and promoting reference repositories";
    license = lib.licenses.mit;
    mainProgram = "ghq-sync";
  };
}

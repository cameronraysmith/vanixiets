{
  lib,
  writeShellApplication,
  ghq,
  git,
  coreutils,
  zoxide,
  delegate ? null,
}:
writeShellApplication {
  name = "ghq-sync";
  runtimeInputs = [
    ghq
    git
    coreutils
    zoxide
  ];
  text =
    lib.optionalString (delegate != null) ''
      GHQ_SYNC_DELEGATE=${lib.escapeShellArg delegate}
    ''
    + builtins.readFile ./ghq-sync.sh;
  meta = {
    description = "Lazy, partial-clone-aware ghq wrapper for fetching, updating, deepening, and promoting reference repositories";
    license = lib.licenses.mit;
    mainProgram = "ghq-sync";
  };
}

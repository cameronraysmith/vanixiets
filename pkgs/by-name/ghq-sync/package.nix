{
  lib,
  writeShellApplication,
  ghq,
  git,
  coreutils,
  jq,
  zoxide,
  delegate ? null,
}:
writeShellApplication {
  name = "ghq-sync";
  # gh is deliberately not here: --audit runs the account's own gh, with its token.
  runtimeInputs = [
    ghq
    git
    coreutils
    jq
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

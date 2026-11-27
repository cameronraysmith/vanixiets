# One of the handler's two test scripts, which share handler_fixtures.py: script
# names it, test_handler.py (request protocol, refusals, tags, LFS, hydrate,
# default branch, locks, time limits, failure logging and maintenance) or
# test_handler_history.py (the history fetch).
{
  lib,
  runCommand,
  python3,
  git,
  coreutils,
  ghq-shared,
  script,
}:
let
  scripts = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./handler_fixtures.py
      ./${script}
    ];
  };
in
runCommand "ghq-shared-${lib.removeSuffix ".py" (builtins.replaceStrings [ "_" ] [ "-" ] script)}"
  {
    nativeBuildInputs = [
      python3
      git
      coreutils
    ];
  }
  ''
    python3 ${scripts}/${script} ${ghq-shared}/libexec/ghq-shared/ghq-writer-handler
    touch $out
  ''

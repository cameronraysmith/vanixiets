{
  runCommand,
  python3,
  git,
  coreutils,
  ghq-shared,
}:
runCommand "ghq-shared-test-handler"
  {
    nativeBuildInputs = [
      python3
      git
      coreutils
    ];
  }
  ''
    python3 ${./test_handler.py} ${ghq-shared}/libexec/ghq-shared/ghq-writer-handler
    touch $out
  ''

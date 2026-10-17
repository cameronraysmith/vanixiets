{
  lib,
  stdenv,
  runCommand,
  python3,
  acl,
  ghq-shared,
}:
runCommand "ghq-shared-test-acl"
  {
    nativeBuildInputs = [ python3 ] ++ lib.optional stdenv.hostPlatform.isLinux acl;
  }
  ''
    python3 ${./test_acl.py} ${ghq-shared}/bin/ghq-shared-migrate
    touch $out
  ''

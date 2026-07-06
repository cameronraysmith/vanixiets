{
  lib,
  writeShellApplication,
  git,
  jujutsu,
  fd,
  gawk,
  coreutils,
}:
writeShellApplication {
  name = "repo-sync";
  runtimeInputs = [
    git
    jujutsu
    fd
    gawk
    coreutils
  ];
  text = builtins.readFile ./repo-sync.sh;
  meta = {
    description = "Conservatively fetch and fast-forward git and jj repositories discovered beneath given paths";
    license = lib.licenses.mit;
    mainProgram = "repo-sync";
  };
}

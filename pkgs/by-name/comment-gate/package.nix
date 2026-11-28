{
  lib,
  writers,
  makeWrapper,
  symlinkJoin,
  runCommand,
  git,
  uncomment-bin,
}:
let
  unwrapped = writers.writePython3Bin "comment-gate" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./comment_gate.py);

  comment-gate = symlinkJoin {
    name = "comment-gate";
    paths = [ unwrapped ];
    nativeBuildInputs = [ makeWrapper ];
    postBuild = ''
      mkdir -p $out/share/comment-gate
      cp -r ${./fixtures} $out/share/comment-gate/fixtures
      wrapProgram $out/bin/comment-gate \
        --prefix PATH : ${
          lib.makeBinPath [
            git
            uncomment-bin
          ]
        } \
        --set COMMENT_GATE_FIXTURES $out/share/comment-gate/fixtures
    '';
    passthru.tests.self-test = runCommand "comment-gate-self-test" { } ''
      ${lib.getExe comment-gate} self-test
      touch $out
    '';
    meta = {
      description = "Fail a change whose added comments carry ids, dates, measurements, history or banners";
      license = lib.licenses.mit;
      mainProgram = "comment-gate";
    };
  };
in
comment-gate

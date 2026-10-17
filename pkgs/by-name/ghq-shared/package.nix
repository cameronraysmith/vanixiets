{
  lib,
  stdenvNoCC,
  bash,
  python3,
  ghq,
  ghq-sync,
  git,
  coreutils,
  shellcheck,
  callPackage,
}:
let
  socket =
    if stdenvNoCC.hostPlatform.isDarwin then "/var/run/ghq-writer.sock" else "/run/ghq-writer.sock";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ghq-shared";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./ghq.sh
      ./ghq-shared-migrate.py
      ./ghq-writer-client.py
      ./ghq-writer-handler.py
    ];
  };

  installPhase = ''
    runHook preInstall
    libexec=$out/libexec/ghq-shared
    install -Dm755 ghq-writer-handler.py $libexec/ghq-writer-handler
    install -Dm755 ghq-writer-client.py $libexec/ghq-writer-client
    install -Dm755 ghq.sh $out/bin/ghq
    install -Dm755 ghq-shared-migrate.py $out/bin/ghq-shared-migrate
    sed -i '1i #!${python3}/bin/python3' $libexec/ghq-writer-handler $libexec/ghq-writer-client $out/bin/ghq-shared-migrate
    sed -i '1i #!${bash}/bin/bash\nset -euo pipefail' $out/bin/ghq
    substituteInPlace $libexec/ghq-writer-handler \
      --replace-fail @ghq@ ${ghq}/bin/ghq \
      --replace-fail @ghqSync@ ${ghq-sync}/bin/ghq-sync \
      --replace-fail @toolPath@ ${
        lib.makeBinPath [
          git
          coreutils
        ]
      }
    substituteInPlace $libexec/ghq-writer-client --replace-fail @socket@ ${socket}
    substituteInPlace $out/bin/ghq-shared-migrate \
      --replace-fail @git@ ${git}/bin/git \
      --replace-fail @cp@ ${coreutils}/bin/cp
    substituteInPlace $out/bin/ghq \
      --replace-fail @ghq@ ${ghq}/bin/ghq \
      --replace-fail @client@ $libexec/ghq-writer-client
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    shellcheck
    python3
  ];
  installCheckPhase = ''
    shellcheck $out/bin/ghq
    python3 -c 'import ast, sys; [ast.parse(open(f).read()) for f in sys.argv[1:]]' \
      $out/libexec/ghq-shared/ghq-writer-handler $out/libexec/ghq-shared/ghq-writer-client \
      $out/bin/ghq-shared-migrate
  '';

  passthru = {
    inherit socket;
    tests.handler = callPackage ./test-handler.nix { ghq-shared = finalAttrs.finalPackage; };
  };

  meta = {
    description = "Read-only ghq wrapper, single-writer request handler and migration tool for a host-shared ghq tree";
    license = lib.licenses.mit;
    mainProgram = "ghq";
    platforms = lib.platforms.unix;
  };
})

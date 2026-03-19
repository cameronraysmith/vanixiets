{
  lib,
  buildNpmPackage,
  makeWrapper,
  nodejs_22,
  beads,
  fetchFromGitHub,
}:

buildNpmPackage {
  pname = "beads-ui";
  version = "0.11.3";

  src = fetchFromGitHub {
    owner = "mantoni";
    repo = "beads-ui";
    tag = "v0.11.3";
    hash = "sha256-tdw4S87n+JWY85w6m8tFPi2euAzp0/NWvwDajKJxOos=";
  };

  nodejs = nodejs_22;

  # Upstream lockfile omits resolved/integrity fields for dev dependencies,
  # causing prefetch-npm-deps to skip them. Use a regenerated lockfile with
  # complete registry metadata (generated with npm 10 / nodejs_22).
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-9Zk0aGzSxrxve0J4OueHMORLTiTRJYhccbU6wT0VQcI=";

  makeCacheWritable = true;

  nativeBuildInputs = [ makeWrapper ];

  npmBuildScript = "build";

  dontNpmInstall = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/node_modules/beads-ui
    cp -r app server bin package.json node_modules $out/lib/node_modules/beads-ui/

    mkdir -p $out/bin
    makeWrapper ${nodejs_22}/bin/node $out/bin/bdui \
      --add-flags "$out/lib/node_modules/beads-ui/bin/bdui.js" \
      --prefix PATH : ${lib.makeBinPath [ beads ]}

    runHook postInstall
  '';

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Local UI for Beads issue tracker";
    homepage = "https://github.com/mantoni/beads-ui";
    license = lib.licenses.mit;
    mainProgram = "bdui";
    platforms = lib.platforms.unix;
  };
}

# beads-kanban-ui - Kanban board UI for the beads issue tracker
#
# A Next.js frontend with an embedded Rust (Axum) backend server
# that serves static assets and provides API endpoints for beads
# issue management with SQLite persistence.
#
# Source: https://github.com/AvivK5498/Beads-Kanban-UI
{
  lib,
  buildNpmPackage,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
  nix-update-script,
}:
let
  version = "0.4.2";
  pname = "beads-kanban-ui";

  src = fetchFromGitHub {
    owner = "AvivK5498";
    repo = "Beads-Kanban-UI";
    tag = "v${version}";
    hash = "sha256-VBvicJQ/cpbdppwLYsB/i1UX06O/Spg7XavqcuWcHwA=";
  };

  frontend = buildNpmPackage {
    inherit version src;
    pname = "${pname}-frontend";

    # Replace Google Fonts with system font stack (network blocked in Nix sandbox)
    # and disable ESLint/TypeScript checking during build (upstream has pre-existing lint errors)
    postPatch = ''
      substituteInPlace package.json --replace-fail \
        '"prepare": "bash scripts/install-hooks.sh"' \
        '"prepare": "true"'

      substituteInPlace next.config.js --replace-fail \
        'module.exports = nextConfig;' \
        'nextConfig.eslint = { ignoreDuringBuilds: true }; nextConfig.typescript = { ignoreBuildErrors: true }; module.exports = nextConfig;'

      cp ${./layout.tsx} src/app/layout.tsx
    '';

    npmDepsHash = "sha256-+eHchwoDfQ8Dt1e4DSJfVCFImT0cbf7bCddYhn4SBkA=";

    # next build produces static export in out/ via output: 'export' in next.config.js
    buildPhase = ''
      runHook preBuild
      npm run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp -r out $out
      runHook postInstall
    '';
  };
in
rustPlatform.buildRustPackage (finalAttrs: {
  inherit pname version src;

  cargoRoot = "server";
  buildAndTestSubdir = "server";

  cargoHash = "sha256-vE61rnUiQjA4VPxU5G/QDc3XFg+5+Nsx8RR7RE8wJwM=";

  preBuild = ''
    cp -r ${frontend} out
  '';

  nativeBuildInputs = [ makeWrapper ];

  # Tests require runtime setup (SQLite database)
  doCheck = false;

  postInstall = ''
    makeWrapper $out/bin/beads-server $out/bin/beads-kanban-ui \
      --set PORT 3008
  '';

  passthru = {
    inherit frontend;
    updateScript = nix-update-script { };
  };

  meta = {
    description = "Kanban board UI for the beads issue tracker with embedded server";
    homepage = "https://github.com/AvivK5498/Beads-Kanban-UI";
    license = lib.licenses.unfree;
    mainProgram = "beads-kanban-ui";
    maintainers = with lib.maintainers; [ cameronraysmith ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})

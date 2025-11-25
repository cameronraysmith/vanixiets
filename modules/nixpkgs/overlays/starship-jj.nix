# starship-jj overlay - DISABLED BY DEFAULT
# Toggle: Uncomment the overlay content below to enable starship-jj
# Note: Requires Rust compilation (~10-30 minutes on first build)
#
# starship-jj provides enhanced jujutsu integration for starship prompt.
# Package source: docs/notes/development/archived-overlays/packages/starship-jj.nix
{ ... }:
{
  # TOGGLE: Change `false` to `true` to enable starship-jj overlay
  flake.overlays.starship-jj =
    final: prev:
    if false then
      {
        starship-jj = final.callPackage (
          {
            lib,
            rustPlatform,
            fetchCrate,
            nix-update-script,
            pkg-config,
            openssl,
          }:
          let
            pname = "starship-jj";
            version = "0.5.1";
          in
          rustPlatform.buildRustPackage {
            inherit pname version;

            src = fetchCrate {
              inherit pname version;
              hash = "sha256-tQEEsjKXhWt52ZiickDA/CYL+1lDtosLYyUcpSQ+wMo=";
            };

            cargoHash = "sha256-+rLejMMWJyzoKcjO7hcZEDHz5IzKeAGk1NinyJon4PY=";

            nativeBuildInputs = [ pkg-config ];
            buildInputs = [ openssl ];

            doCheck = false;
            doInstallCheck = true;
            installCheckPhase = ''
              $out/bin/starship-jj --version 2>&1 | grep ${version};
            '';

            passthru.updateScript = nix-update-script { };

            meta = with lib; {
              homepage = "https://gitlab.com/lanastara_foss/starship-jj";
              description = "starship plugin for jj";
              mainProgram = "starship-jj";
              license = licenses.mit;
              maintainers = with maintainers; [ cameronraysmith ];
            };
          }
        ) { };
      }
    else
      { };
}

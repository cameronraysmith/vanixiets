{
  fetchFromGitHub,
  icu,
  lib,
  buildGoModule,
  go_1_26,
  nix-update-script,
}:

(buildGoModule.override { go = go_1_26; }) (finalAttrs: {
  pname = "dolt";
  version = "1.82.6";

  src = fetchFromGitHub {
    owner = "dolthub";
    repo = "dolt";
    tag = "v${finalAttrs.version}";
    hash = "sha256-kI/7MoLz0U5sp8OJDmo0ERkOiVms7jwNNs0IhbFA+CY=";
  };

  modRoot = "./go";
  subPackages = [ "cmd/dolt" ];
  vendorHash = "sha256-X8G4VEOudPTdbSENppYX3+6+Yx3Eh+dslzq0K7U628I=";
  proxyVendor = true;
  doCheck = false;

  buildInputs = [ icu ];

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Relational database with version control and CLI a-la Git";
    mainProgram = "dolt";
    homepage = "https://github.com/dolthub/dolt";
    license = lib.licenses.asl20;
  };
})

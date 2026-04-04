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
  version = "1.85.0";

  src = fetchFromGitHub {
    owner = "dolthub";
    repo = "dolt";
    tag = "v${finalAttrs.version}";
    hash = "sha256-UVSyEe1plTdselZvYNoZ8HWPVWuNeCLpBV67dNqZ/bA=";
  };

  modRoot = "./go";
  subPackages = [ "cmd/dolt" ];
  vendorHash = "sha256-Jq8Qxp/DpANJzZ/1jmIMJO0f0sBzqHHSwtNYUS4bqXk=";
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

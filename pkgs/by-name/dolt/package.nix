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
  version = "1.82.4";

  src = fetchFromGitHub {
    owner = "dolthub";
    repo = "dolt";
    tag = "v${finalAttrs.version}";
    hash = "sha256-mavL3y+Kv25hzFlDFXk7W/jeKVKlCBjlc67GkL3Jcwk=";
  };

  modRoot = "./go";
  subPackages = [ "cmd/dolt" ];
  vendorHash = "sha256-K1KzsqptZxO5OraWKIXeqKuVSzb6E/Mjy3c5PQ7Rs9k=";
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

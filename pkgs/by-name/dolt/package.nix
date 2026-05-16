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
  version = "1.88.1";

  src = fetchFromGitHub {
    owner = "dolthub";
    repo = "dolt";
    tag = "v${finalAttrs.version}";
    hash = "sha256-XinWRzNXrGCvpVN4i6BGvtVNP+gltBa05+8yQeNa7z4=";
  };

  modRoot = "./go";
  subPackages = [ "cmd/dolt" ];
  vendorHash = "sha256-SbgjbR10VTMtPyGfTw/85/dTW74nW2HUw77slXEympc=";
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

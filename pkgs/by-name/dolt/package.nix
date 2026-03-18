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
  version = "1.83.7";

  src = fetchFromGitHub {
    owner = "dolthub";
    repo = "dolt";
    tag = "v${finalAttrs.version}";
    hash = "sha256-44bwvP6NZaaWXhpWSv5Fq0wgTb8NJGi5E9XhhsUI2Fc=";
  };

  modRoot = "./go";
  subPackages = [ "cmd/dolt" ];
  vendorHash = "sha256-O1lqggGgXoILRKRNmN3Nm9k55/ZLrySBGMvJHxiMT1s=";
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

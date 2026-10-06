{
  lib,
  buildPythonPackage,
  fetchPypi,
  omnigent-client,
  prompt-toolkit,
  pyyaml,
  rich,
  version,
}:
buildPythonPackage {
  pname = "omnigent-ui-sdk";
  inherit version;
  format = "wheel";

  src = fetchPypi {
    pname = "omnigent_ui_sdk";
    inherit version;
    format = "wheel";
    python = "py3";
    dist = "py3";
    platform = "any";
    hash = "sha256-2I9JWM64pqFNawr6exvQRJ1uOvZ+6J6NZ37JBy2OLFA=";
  };

  dependencies = [
    omnigent-client
    prompt-toolkit
    pyyaml
    rich
  ];

  meta = {
    description = "Terminal UI SDK for Omnigent";
    homepage = "https://omnigent.ai";
    license = lib.licenses.asl20;
  };
}

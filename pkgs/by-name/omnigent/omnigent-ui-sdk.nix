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
    hash = "sha256-c5o6xbJuH+YoM8E2Tn0OhX4vDxJzFYgLZN6ZLcWko38=";
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

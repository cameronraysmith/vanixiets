{
  lib,
  buildPythonPackage,
  fetchPypi,
  httpx,
  pydantic,
  version,
}:
buildPythonPackage {
  pname = "omnigent-client";
  inherit version;
  format = "wheel";

  src = fetchPypi {
    pname = "omnigent_client";
    inherit version;
    format = "wheel";
    python = "py3";
    dist = "py3";
    platform = "any";
    hash = "sha256-JYrFi4E70R4hP487CUQkXaO6Wt0jrDqRJCFf3cBmAPM=";
  };

  # Break the circular dependency; the application supplies omnigent and checks imports.
  pythonRemoveDeps = [ "omnigent" ];
  dependencies = [
    httpx
    pydantic
  ];

  meta = {
    description = "Python client for the Omnigent server API";
    homepage = "https://omnigent.ai";
    license = lib.licenses.asl20;
  };
}

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
    hash = "sha256-d9Xy1/6Y04jk/HVt+eJgj+6hWXHoOetZri+lphtJCFo=";
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

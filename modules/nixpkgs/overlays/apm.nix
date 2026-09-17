{ inputs, ... }:
{
  nixpkgsOverlays = [
    (_final: prev: {
      apm = inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system}.apm;
    })
  ];
}

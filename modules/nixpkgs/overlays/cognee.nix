{ inputs, ... }:
{
  nixpkgsOverlays = [
    inputs.cognee-nix.overlays.default
    # GCC 16 stopped including <cstdint> transitively, and ladybug's vendored
    # thrift headers use uint32_t without including it themselves.
    # stdint.h declares those types in the global namespace the headers expect
    # and is valid in both the C and C++ translation units this build compiles.
    (_final: prev: {
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (_pythonFinal: pythonPrev: {
          ladybug = pythonPrev.ladybug.overrideAttrs (old: {
            env = (old.env or { }) // {
              NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -include stdint.h";
            };
          });
        })
      ];
    })
  ];
}

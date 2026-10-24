{ inputs, ... }:
{
  nixpkgsOverlays = [
    inputs.cognee-nix.overlays.default
    (_final: prev: {
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (_pythonFinal: pythonPrev: {
          # fastapi-users exists in the python set only through cognee-nix's
          # overlay, so this reaches cognee alone. It pins pwdlib==0.3.0;
          # nixpkgs ships 0.3.1, whose runtime change is a type-hint-only
          # `Self` return on PasswordHash.recommended, and the hashers it
          # imports are unchanged. Remove once cognee-nix relaxes or bumps it.
          fastapi-users = pythonPrev.fastapi-users.overridePythonAttrs (old: {
            pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "pwdlib" ];
          });
          # GCC 16 stopped including <cstdint> transitively, and ladybug's vendored
          # thrift headers use uint32_t without including it themselves.
          # stdint.h declares those types in the global namespace the headers expect
          # and is valid in both the C and C++ translation units this build compiles.
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

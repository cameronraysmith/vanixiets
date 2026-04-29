{ config, lib, ... }:
{
  flake.lib.requireRegistryKey =
    class: name:
    if config.flake.modules.${class} ? ${name} then
      config.flake.modules.${class}.${name}
    else
      throw ''
        vanixiets: no registered flake.modules.${class} entry at key '${name}'.
        Available: ${lib.concatStringsSep ", " (lib.attrNames config.flake.modules.${class})}
      '';
}

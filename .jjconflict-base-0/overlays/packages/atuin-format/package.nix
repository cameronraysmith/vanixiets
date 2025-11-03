{ nuenv, atuin, ... }:

nuenv.writeShellApplication {
  name = "atuin-format";
  runtimeInputs = [ atuin ];
  meta.description = ''
    Format atuin history with beautiful Catppuccin Mocha colored table output.
    Supports search queries, filtering, multiple output formats (table/json/csv),
    and detailed row inspection.
  '';
  text = ''
    #!/usr/bin/env nu

    ${builtins.readFile ./atuin-format.nu}
  '';
}

# nix-unit invariants for the agents-md home-manager module
# (modules/home/modules/agents-md.nix).
#
# The module's `config.enable = true` branch composes two filesets via
# module-system merging: home.file (4 paths) and xdg.configFile (2 paths),
# producing the documented six AGENTS-style files for Claude Code, Codex,
# Droid, Gemini, Crush, and Opencode.
#
# Catches accidental rename or removal of any vendor's config file path
# during refactoring — failures of that kind would silently drop a vendor's
# config without any other check noticing.
{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.eval-agents-md = config.flake.lib.mkEvalCheck pkgs {
        name = "agents-md";
        testFile = pkgs.writeText "agents-md.tests.nix" ''
          let
            lib = import ${pkgs.path}/lib;
            mdFormatType = (import ${../../lib/md-format.nix} { inherit lib; }).flake.lib.mdFormat;
            agentsMdSpec =
              (import ${./agents-md.nix} {
                config = { flake.lib.mdFormat = mdFormatType; };
              }).flake.modules.homeManager.agents-md;

            evalAgentsMd =
              userConfig:
              (lib.evalModules {
                modules = [
                  agentsMdSpec
                  (
                    { lib, ... }:
                    {
                      options.xdg.configFile = lib.mkOption {
                        type = lib.types.attrsOf lib.types.anything;
                        default = { };
                      };
                      options.home.file = lib.mkOption {
                        type = lib.types.attrsOf lib.types.anything;
                        default = { };
                      };
                    }
                  )
                  userConfig
                ];
              }).config;

            enabled = evalAgentsMd {
              programs.agents-md.enable = true;
              programs.agents-md.settings.body = "stub";
            };

            disabled = evalAgentsMd {
              programs.agents-md.enable = false;
            };
          in
          {
            testEnabledRegistersFourHomeFiles = {
              expr = builtins.sort builtins.lessThan (builtins.attrNames enabled.home.file);
              expected = [
                ".claude/CLAUDE.md"
                ".codex/AGENTS.md"
                ".factory/AGENTS.md"
                ".gemini/GEMINI.md"
              ];
            };

            testEnabledRegistersTwoXdgConfigFiles = {
              expr = builtins.sort builtins.lessThan (builtins.attrNames enabled.xdg.configFile);
              expected = [
                "crush/CRUSH.md"
                "opencode/AGENTS.md"
              ];
            };

            testDisabledRegistersNoFiles = {
              expr = (disabled.home.file == { }) && (disabled.xdg.configFile == { });
              expected = true;
            };

            testEnabledFilesShareSingleTextSource = {
              expr =
                let
                  homeTexts = builtins.attrValues (lib.mapAttrs (_: v: v.text) enabled.home.file);
                  xdgTexts = builtins.attrValues (lib.mapAttrs (_: v: v.text) enabled.xdg.configFile);
                  all = homeTexts ++ xdgTexts;
                in
                builtins.length (lib.unique all) == 1;
              expected = true;
            };
          }
        '';
      };
    };
}

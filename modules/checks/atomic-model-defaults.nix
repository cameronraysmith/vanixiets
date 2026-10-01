{
  config,
  inputs,
  lib,
  self,
  ...
}:
{
  perSystem =
    { system, ... }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ config.flake.overlays.default ];
      };
      worker = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          flake = config.flake // {
            inherit inputs;
          };
          osConfig = null;
        };
        modules = [
          config.flake.modules.homeManager.omnigent-worker
          {
            home.username = "omnigent-fixture";
            home.homeDirectory =
              if pkgs.stdenv.hostPlatform.isDarwin then "/Users/omnigent-fixture" else "/home/omnigent-fixture";
            home.stateVersion = "25.11";
          }
        ];
      };
      human = self.homeConfigurations."crs58@${system}";
      program = config.flake.lib.managedConfigProgram pkgs;
      spec =
        name: home:
        let
          entry = home.config.managedConfigs.atomic-settings;
        in
        pkgs.writeText "${name}-atomic-spec.json" (
          builtins.toJSON {
            name = "atomic-settings";
            inherit (entry)
              target
              format
              fileMode
              appOwned
              externalPaths
              ;
            declared = (pkgs.formats.json { }).generate "${name}-atomic-settings.json" entry.settings;
          }
        );
    in
    {
      checks.atomic-model-defaults = pkgs.runCommand "atomic-model-defaults" { } ''
        ${pkgs.python3.interpreter} - ${lib.getExe program} ${spec "human" human} ${spec "worker" worker} <<'PY'
        import json
        import pathlib
        import subprocess
        import sys

        program = sys.argv[1]
        for index, template in enumerate(sys.argv[2:]):
            spec = json.loads(pathlib.Path(template).read_text())
            assert spec["target"].endswith("/.atomic/agent/settings.json")
            declared = json.loads(pathlib.Path(spec["declared"]).read_text())
            assert declared["defaultProvider"] == "openai-codex"
            assert declared["defaultModel"] == "gpt-6-astra"
            assert declared["defaultThinkingLevel"] == "medium"
            assert declared["modelThinkingLevels"]["openai-codex/gpt-6-astra"] == "medium"
            assert declared["fallbackModels"][0] == "openai-codex/gpt-6-astra:high"
            assert declared["subagents"]["agentOverrides"]["worker"]["model"] == "openai-codex/gpt-6-astra:medium"
            target = pathlib.Path.cwd() / f"settings-{index}.json"
            spec["target"] = str(target)
            local = pathlib.Path(f"spec-{index}.json")
            local.write_text(json.dumps(spec))
            retained = {"onboardedVersion": "fixture"}
            target.write_text(json.dumps(retained | {"unmanaged": {"nested": "sentinel-value"}, "defaultModel": "old", "defaultThinkingLevel": "high"}))
            result = subprocess.run([program, str(local)], check=True, capture_output=True, text=True)
            assert json.loads(target.read_text()) == declared | retained
            assert "unmanaged.nested" in result.stderr and "sentinel-value" not in result.stderr, result.stderr
            previous = target.read_bytes()
            subprocess.run([program, str(local)], check=True)
            assert target.read_bytes() == previous
        PY
        touch "$out"
      '';
    };
}

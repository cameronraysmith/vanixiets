{
  config,
  inputs,
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
      activation =
        name: home:
        pkgs.writeText "${name}-atomic-activation" home.config.home.activation.atomicMergeSettings.data;
    in
    {
      checks.atomic-model-defaults = pkgs.runCommand "atomic-model-defaults" { } ''
        ${pkgs.python3.interpreter} - ${activation "human" human} ${activation "worker" worker} <<'PY'
        import json
        import pathlib
        import shlex
        import subprocess
        import sys

        for index, activation in enumerate(sys.argv[1:]):
            dry_run, executable, declaration, destination = shlex.split(pathlib.Path(activation).read_text())
            assert dry_run == "$DRY_RUN_CMD"
            declared = json.loads(pathlib.Path(declaration).read_text())
            assert declared["defaultProvider"] == "openai-codex"
            assert declared["defaultModel"] == "gpt-6-astra"
            assert declared["defaultThinkingLevel"] == "medium"
            assert declared["modelThinkingLevels"]["openai-codex/gpt-6-astra"] == "medium"
            assert declared["fallbackModels"][0] == "openai-codex/gpt-6-astra:high"
            assert declared["subagents"]["agentOverrides"]["worker"]["model"] == "openai-codex/gpt-6-astra:medium"
            target = pathlib.Path(f"settings-{index}.json")
            retained = {"onboardedVersion": "fixture", "unmanaged": {"nested": True}}
            target.write_text(json.dumps(retained | {"defaultModel": "old", "defaultThinkingLevel": "high"}))
            subprocess.run([executable, declaration, str(target)], check=True)
            assert json.loads(target.read_text()) == retained | declared
            previous = target.read_bytes()
            subprocess.run([executable, declaration, str(target)], check=True)
            assert target.read_bytes() == previous
        PY
        touch "$out"
      '';
    };
}

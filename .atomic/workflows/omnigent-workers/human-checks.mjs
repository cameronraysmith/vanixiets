import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

export async function humanChecks(gates) {
  const root = `.atomic/workflows/runs/omnigent-workers-human-${Date.now()}`;
  const rev = execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  const evaluate = (expression) => JSON.parse(execFileSync("nix", ["eval", "--offline", "--no-write-lock-file", "--option", "allow-import-from-derivation", "false", "--impure", "--json", "--expr", expression], { encoding: "utf8", timeout: 120_000, maxBuffer: 8 * 1024 * 1024 }));
  const inputs = evaluate(`let f = builtins.getFlake "git+file://${process.cwd()}?rev=${rev}"; in { nixpkgs = toString f.inputs.nixpkgs; hm = toString f.inputs.home-manager; sops = toString f.inputs.sops-nix; }`);
  const fixture = async (name, changes = {}) => {
    const dir = resolve(root, name);
    await mkdir(dir, { recursive: true });
    await writeFile(`${dir}/public-sops.yaml`, changes.ciphertext ?? "canary: public fixture, never a credential\n");
    await writeFile(`${dir}/unrelated`, name);
    const schemaPath = changes.schemaPath ?? "schema";
    await mkdir(`${dir}/${schemaPath}`, { recursive: true });
    await writeFile(`${dir}/${schemaPath}/schema.yaml`, changes.schema ?? "name: preserved-schema\n");
    await writeFile(`${dir}/flake.nix`, `{
      outputs = { self }: let
        nixpkgs = ${inputs.nixpkgs};
        d = import (nixpkgs + "/nixos/lib/eval-config.nix") {
          system = "x86_64-linux";
          modules = [ ${inputs.hm}/nixos {
            system.stateVersion = "25.11";
            home-manager.useGlobalPkgs = true;
            users.users.fixture = { isNormalUser = true; home = "/home/fixture"; };
            home-manager.users.fixture = { pkgs, ... }: {
              imports = [ ${inputs.sops}/modules/home-manager/sops.nix ];
              home.username = "fixture"; home.homeDirectory = "/home/fixture"; home.stateVersion = "25.11";
              home.packages = [ pkgs.${changes.package ?? "hello"} ];
              home.file."approved-schema".source = self + "/${schemaPath}";
              xdg.configFile."claude-cerebras/settings.json".enable = ${changes.enableUndefined ?? false};
              xdg.configFile."human-settings".text = "${changes.text ?? "preserved human settings"}";
              xdg.configFile."human-schema".source = self + "/${schemaPath}";
              home.activation.mutableSettings = let settings = pkgs.writeText "mutable-settings.json" "${changes.mutableText ?? "preserved mutable settings"}"; in {
                after = [ "writeBoundary" ]; before = []; data = "install -Dm644 \${settings} /home/fixture/.config/claude-cerebras/settings.json";
              };
              programs.git = { enable = true; settings.user.name = "${changes.gitName ?? "Fixture Human"}"; };
              sops.defaultSopsFile = self + "/public-sops.yaml";
              sops.age.keyFile = "/home/fixture/private-age-key";
              sops.secrets.canary = {};
              systemd.user.services.human-service = {
                Unit.Description = "Preserved human service";
                Service.ExecStart = "${changes.service ?? "/bin/true"}";
              };
            };
            systemd.services.omnigent.serviceConfig.ExecStart = "/bin/true";
          } ];
        };
      in { nixosConfigurations = { magnetite = d; pyrite = d; }; darwinConfigurations.stibnite = d; };
    }`);
    return evaluate(gates.baselineExpr(`path:${dir}`));
  };
  const before = await fixture("before"), relocated = await fixture("relocated");
  assert.deepEqual(relocated.humans, before.humans, "F1 identical human behavior must survive source-root-only relocation");
  for (const [name, changes] of Object.entries({ package: { package: "jq" }, git: { gitName: "Changed Human" }, service: { service: "/bin/false" }, ciphertext: { ciphertext: "canary: changed public fixture\n" }, schema: { schema: "name: changed-schema\n" }, text: { text: "changed human settings" }, mutable: { mutableText: "changed mutable settings" }, location: { schemaPath: "moved/schema" } })) {
    assert.notDeepEqual((await fixture(name, changes)).humans, before.humans, `F1 must reject actual ${name} behavior/input change`);
  }
  await assert.rejects(fixture("enabled-undefined", { enableUndefined: true }), /source.*accessed but has no value defined/s, "Enabled files without a source must still fail");
  console.log("PASS F1 pinned HM/sops: disabled XDG source accepted; relocation accepted; package, Git, service, input content/location, XDG text and mutable activation changes rejected; enabled undefined source rejected (no builds)");
}

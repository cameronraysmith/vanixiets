import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

export async function humanChecks(gates) {
  const historicalSource = "git+file:///Users/crs58/projects/vanixiets?rev=2a6a89ce9706886cf3cf504ee0b6d3fcfdbe81bc";
  for (const phase of ["capabilities", "linux", "darwin", "inventory"]) {
    assert.equal(createHash("sha256").update(JSON.stringify(gates.baselineExpr(historicalSource, phase))).digest("hex"), "ee8dd66537e61147e59c7c942284e596782d415345dfcdc05986a24766575e2c", `${phase} expression must remain byte-identical to the sealed baseline`);
  }
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
            users.users.janettesmith = { isNormalUser = true; home = "/home/janettesmith"; };
            home-manager.users.janettesmith = { pkgs, ... }: {
              imports = [ ${inputs.sops}/modules/home-manager/sops.nix ];
              home.username = "janettesmith"; home.homeDirectory = "/home/janettesmith"; home.stateVersion = "25.11";
              home.packages = [ pkgs.${changes.package ?? "hello"} ];
              home.file."approved-schema".source = self + "/${schemaPath}";
              xdg.configFile."claude-cerebras/settings.json".enable = ${changes.enableUndefined ?? false};
              xdg.configFile."human-settings".text = "${changes.text ?? "preserved human settings"}";
              xdg.configFile."human-schema".source = self + "/${schemaPath}";
              home.activation.mutableSettings = let settings = pkgs.writeText "mutable-settings.json" "${changes.mutableText ?? "preserved mutable settings"}"; in {
                after = [ "writeBoundary" ]; before = []; data = "install -Dm644 \${settings} /home/fixture/.config/claude-cerebras/settings.json";
              };
              programs.git = { enable = true; settings = { user = { name = "${changes.gitName ?? "Fixture Human"}"; email = "${changes.gitEmail ?? "old@example.com"}"; }; ${changes.githubUser === undefined ? "" : `github.user = "${changes.githubUser}";`} }; };
              programs.jujutsu = { enable = true; settings.user.email = "${changes.gitEmail ?? "old@example.com"}"; };
              sops.templates.allowed_signers = { mode = "${changes.signerMode ?? "0400"}"; content = ''${changes.gitEmail ?? "old@example.com"} namespaces="git" ${changes.signerKey ?? "public-fixture-key"}
              ''; };
              sops.defaultSopsFile = self + "/public-sops.yaml";
              sops.age.keyFile = "/home/fixture/private-age-key";
              sops.secrets.canary = {};
              systemd.user.services.human-service = {
                Unit.Description = "Preserved human service";
                Service.ExecStart = "${changes.service ?? "/bin/true"}";
              };
            };
            systemd.services.omnigent.serviceConfig.ExecStart = "/bin/true";
            environment.etc."omnigent/workers/cameron".source = d.pkgs.runCommand "worker-home" {} "mkdir $out";
          } ];
        };
      in { nixosConfigurations = { magnetite = d; pyrite = d; }; darwinConfigurations = { stibnite = d; rosegold = d; }; };
    }`);
    return evaluate(gates.baselineExpr(`path:${dir}`, changes.phase ?? "inventory"));
  };
  const before = await fixture("before"), relocated = await fixture("relocated");
  assert.deepEqual(relocated.humans, before.humans, "F1 identical human behavior must survive source-root-only relocation");
  for (const [name, changes] of Object.entries({ package: { package: "jq" }, git: { gitName: "Changed Human" }, service: { service: "/bin/false" }, ciphertext: { ciphertext: "canary: changed public fixture\n" }, schema: { schema: "name: changed-schema\n" }, text: { text: "changed human settings" }, mutable: { mutableText: "changed mutable settings" }, location: { schemaPath: "moved/schema" } })) {
    assert.notDeepEqual((await fixture(name, changes)).humans, before.humans, `F1 must reject actual ${name} behavior/input change`);
  }
  await assert.rejects(fixture("enabled-undefined", { enableUndefined: true }), /source.*accessed but has no value defined/s, "Enabled files without a source must still fail");
  const identityBefore = await fixture("identity-before", { phase: "identity" });
  assert(identityBefore.janette?.human && identityBefore.stibniteWorker?.generation, "Identity must project Janette's human home and the standalone Darwin generation");
  assert.deepEqual({ humans: identityBefore.humans, server: identityBefore.server }, before, "Supplemental keys must not change any historical projection value");
  const canonical = "125711642+janetteasmith@users.noreply.github.com";
  const identityOnly = await fixture("identity-four-fields", { phase: "identity", gitEmail: canonical, githubUser: "janetteasmith" });
  assert.notDeepEqual(identityBefore.janette.human, identityOnly.janette.human, "The real author and GitHub artifacts must change");
  assert(gates.compareProtected("identity", identityBefore, identityOnly).janetteUnchanged, "Identity accepts the four canonical mail/principal/GitHub fields and their derived artifacts");
  assert(!gates.compareProtected("credentials", identityOnly, identityBefore).janetteUnchanged, "Credentials rejects a four-field change against the completed identity baseline");
  assert(gates.compareProtected("credentials", identityOnly, identityOnly).janetteUnchanged);
  for (const [name, changes] of Object.entries({ package: { package: "jq" }, gitName: { gitName: "Changed Human" }, service: { service: "/bin/false" }, text: { text: "changed human settings" }, mutable: { mutableText: "changed mutable settings" }, signerKey: { signerKey: "different-public-key" }, signerMode: { signerMode: "0444" } })) {
    const changed = await fixture(`identity-${name}`, { phase: "identity", gitEmail: canonical, githubUser: "janetteasmith", ...changes });
    assert(!gates.compareProtected("identity", identityBefore, changed).janetteUnchanged, `Identity must reject Janette's fifth ${name} change alongside the four approved fields`);
  }
  const changedWorker = { ...identityOnly, stibniteWorker: { generation: "different-generation", output: "different-output" } };
  for (const phase of ["identity", "credentials", "magnetite", "pyrite", "stibnite", "closure"]) {
    assert(!gates.compareProtected(phase, identityOnly, changedWorker).stibniteWorkerUnchanged);
    assert(!gates.compareProtected(phase, identityOnly, identityBefore).janetteUnchanged);
  }
  assert.throws(() => gates.compareProtected("identity", before, before), /Missing Janette/);
  console.log("PASS supplemental protection: pre-identity expression bytes/payload unchanged; identity four-field diff accepted; fifth Janette behavior/key/mode change rejected; credentials and later four-field/standalone-generation drift rejected");
  console.log("PASS F1 pinned HM/sops: disabled XDG source accepted; relocation accepted; package, Git, service, input content/location, XDG text and mutable activation changes rejected; enabled undefined source rejected (no builds)");
}

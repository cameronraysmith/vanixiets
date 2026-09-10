import { quote } from "../bump/tools.js";
import { phases, hosts, Stop, type Phase, type Host, type Source } from "./contract.js";
import type { Operations } from "./operations.js";

const config = (host: Host) => `${host === "stibnite" ? "darwin" : "nixos"}Configurations.${host}.config`;
export function expectedEnabled(phase: Phase): Host[] {
  const index = phases.indexOf(phase);
  return hosts.filter((host) => phases.indexOf(host) <= index);
}
export const baselineExpr = (source: string) => `let
  f = builtins.getFlake ${JSON.stringify(source)};
  project = d: let
    lib = d.pkgs.lib;
    original = d.config.home-manager.users;
    rooted = p: p != null && lib.hasPrefix (toString f.outPath + "/") (toString p);
    canonical = p: builtins.path { path = p; name = builtins.unsafeDiscardStringContext (builtins.baseNameOf p); };
    input = p: {
      location = lib.removePrefix (toString f.outPath + "/") (toString p);
      content = toString (canonical p);
    };
    sourceFiles = h: lib.filterAttrs (_: file: rooted file.source) h.home.file;
    secretFiles = h: lib.filterAttrs (_: secret: rooted secret.sopsFile) (h.sops.secrets or {});
    overrides = builtins.mapAttrs (_: h: { lib, ... }: {
      home.file = builtins.mapAttrs (_: file: { source = lib.mkForce (canonical file.source); }) (sourceFiles h);
    } // lib.optionalAttrs (h ? sops) {
      sops = lib.optionalAttrs (rooted h.sops.defaultSopsFile) {
        defaultSopsFile = lib.mkForce (canonical h.sops.defaultSopsFile);
      } // {
        secrets = builtins.mapAttrs (_: secret: { sopsFile = lib.mkForce (canonical secret.sopsFile); }) (secretFiles h);
      };
    }) original;
    normalized = (d.extendModules { modules = [ { home-manager.users = overrides; } ]; }).config.home-manager.users;
  in builtins.mapAttrs (name: h: {
    sourceInputs = {
      files = builtins.mapAttrs (_: file: input file.source) (sourceFiles original.\${name});
      secrets = builtins.mapAttrs (_: secret: input secret.sopsFile) (secretFiles original.\${name});
      defaultSopsFile = let p = original.\${name}.sops.defaultSopsFile or null; in if rooted p then input p else p;
    };
    identity = { inherit (h.home) username homeDirectory stateVersion; };
    environment = { inherit (h.home) sessionVariables sessionPath; };
    packages = map (p: { inherit (p) drvPath outPath; priority = p.meta.priority or 5; outputsToInstall = p.meta.outputsToInstall or [ "out" ]; }) h.home.packages;
    artifacts = {
      generation = h.home.activationPackage.drvPath;
      profile = h.home.path.drvPath;
      activation = h.home.activation;
      files = builtins.mapAttrs (_: file: {
        inherit (file) target executable recursive force onChange;
        source = toString file.source;
      }) h.home.file;
    };
  }) normalized;
in {
  humans = builtins.mapAttrs (_: d: project d) {
    magnetite = f.nixosConfigurations.magnetite; pyrite = f.nixosConfigurations.pyrite; stibnite = f.darwinConfigurations.stibnite;
  };
  server = f.nixosConfigurations.magnetite.config.systemd.units."omnigent.service".unit.drvPath;
}`;
export function stateExpr(source: string, enabled: Host[]) {
  return `let f = builtins.getFlake ${JSON.stringify(source)};
    check = host: names: let
      c = if host == "stibnite" then f.darwinConfigurations.\${host}.config else f.nixosConfigurations.\${host}.config;
      workers = c.services.omnigent-host.workers;
      expected = builtins.elem host (builtins.fromJSON ${JSON.stringify(JSON.stringify(enabled))});
    in builtins.attrNames workers == names && builtins.all (n:
      let w = workers.\${n}; u = c.users.users.\${w.user};
          trusted = c.nix.settings.trusted-users or [];
          groups = (u.extraGroups or []) ++ [ (u.group or "") ];
      in w.enable == expected && w.user != "root" && w.user != "cameron" && w.user != "crs58"
      && w.owner == n && u.home != "/var/empty"
      && !(builtins.elem "wheel" groups) && !(builtins.elem "admin" groups)
      && !(builtins.elem w.user trusted) && !(builtins.elem "*" trusted)
      && builtins.all (g: !(builtins.elem ("@" + g) trusted)) groups
    ) names;
  in check "magnetite" [ "cameron" "raquel" ] && check "pyrite" [ "cameron" "raquel" ] && check "stibnite" [ "cameron" ]`;
}
export function gateCommands(phase: Phase, source: Source): string[] {
  const at = phases.indexOf(phase);
  const installables = ["checks.x86_64-linux.omnigent-worker-capabilities", "checks.aarch64-darwin.omnigent-worker-capabilities"];
  if (at >= 1) installables.push("checks.x86_64-linux.omnigent-worker-linux");
  if (at >= 2) installables.push("checks.aarch64-darwin.omnigent-worker-darwin");
  if (at >= 3) installables.push("checks.x86_64-linux.omnigent-worker-inventory", "checks.aarch64-darwin.omnigent-worker-inventory");
  return installables.map((attr) => `nix build --no-write-lock-file --no-link --print-out-paths ${quote(`${source.source}#${attr}`)}`);
}
export async function gates(ops: Operations, name: string, phase: Phase, source: Source) {
  return ops.tool(name, { phase, source }, async (signal) => {
    const commands = gateCommands(phase, source);
    const results: { command: string; exitCode: number }[] = [];
    for (const command of commands) {
      const result = await ops.execute("/Users/crs58/projects/vanixiets", command, signal);
      results.push({ command, exitCode: result.exitCode });
      if (result.exitCode !== 0) return { passed: false, results, source };
    }
    if (phases.indexOf(phase) >= 3) {
      const command = `nix eval --no-write-lock-file --impure --json --expr ${quote(stateExpr(source.source, expectedEnabled(phase)))}`;
      const result = await ops.execute("/Users/crs58/projects/vanixiets", command, signal);
      results.push({ command, exitCode: result.exitCode });
      if (result.exitCode !== 0 || result.stdout.trim() !== "true") return { passed: false, results, source };
    }
    return { passed: true, results, source };
  });
}
export async function systemPath(ops: Operations, host: Host, source: Source, signal: AbortSignal): Promise<string> {
  const attr = host === "stibnite" ? "darwinConfigurations.stibnite.system" : `nixosConfigurations.${host}.config.system.build.toplevel`;
  const out = (await ops.command(`nix build --no-write-lock-file --no-link --print-out-paths ${quote(`${source.source}#${attr}`)}`, signal)).trim();
  if (!/^\/nix\/store\/[a-z0-9]{32}-[^\s]+$/.test(out)) throw new Stop("infrastructure", "Expected one realized system output");
  return out;
}
export function workersExpr(source: string, host: Host): string {
  return `let f = builtins.getFlake ${JSON.stringify(source)}; c = f.${config(host)};
  in builtins.mapAttrs (name: w: {
    name = name; user = w.user; home = c.users.users.\${w.user}.home; enabled = w.enable;
    owner = w.owner; hostName = w.hostName;
  }) c.services.omnigent-host.workers`;
}

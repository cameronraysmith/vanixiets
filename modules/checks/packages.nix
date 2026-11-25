# Per-package build-realization checks.
#
# Mic92-style mapAttrs' over self'.packages with a blacklist for entries
# that are already covered under another check name, are intentional
# effect-input-wires (impure pushes), or are thin upstream re-packages
# fully cache-resident on cache.nixos.org without first-party patches.
#
# Naming: package-${n} (category prefix; ecosystem standard per mic92,
# clan-infra). No vanixiets- prefix (provenance is implicit via repo).
{ lib, ... }:
{
  perSystem =
    { self', system, ... }:
    let
      blacklist = [
        # evaluation needs import-from-derivation
        "k8s-manifests-local-json"
        "k8s-manifests-local-k3d-json"
        # already exposed under existing check names
        "fdContainer-aarch64"
        "fdContainer-x86_64"
        "rgContainer-aarch64"
        "rgContainer-x86_64"
        # built by checks.x86_64-linux.skills-marketplace-drift only; its output
        # does not depend on the platform (design D8, skills-single-source-marketplaces)
        "skills-marketplace"
        # run by checks.x86_64-linux.skills-spec-conformance, whose output names
        # it so that the check's upload carries it to the cache
        # (skills-single-source-marketplaces D15)
        "skill-validator"
        # intentional effect-input-wires (impure ghcr.io push)
        "fdManifest"
        "fdManifest-aarch64"
        "fdManifest-x86_64"
        "rgManifest"
        "rgManifest-aarch64"
        "rgManifest-x86_64"
        # thin upstream re-package, fully cache-resident on cache.nixos.org
        "nix-fast-build"
      ];

      filtered = lib.filterAttrs (n: _v: !(builtins.elem n blacklist)) self'.packages;
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      # A large package build shares one reason (design D6).
      testSizes.checks =
        let
          packageBuild = "a package check is the package's own build: it cannot be split, it reruns only when the package's inputs change, and a host closure that includes the package needs the same build";
        in
        {
          x86_64-linux = {
            # nixbot: 0 runs, too few to class (design D4)
            apm-deps = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 1.0 s, slowest 3.6 s, all 3 runs 2026-09-04..2026-10-02
            package-agent-plugins-cloudflare.class = "small";
            # nixbot: median 2.4 s, slowest 3.6 s, all 3 runs 2026-09-04..2026-10-02
            package-agent-plugins-dagster-skills.class = "small";
            # nixbot: median 2.5 s, slowest 3.3 s, all 3 runs 2026-09-04..2026-10-02
            package-agent-plugins-duckdb-skills.class = "small";
            # nixbot: median 1.2 s, slowest 3.3 s, all 3 runs 2026-09-04..2026-10-02
            package-agent-plugins-huggingface-skills.class = "small";
            # nixbot: median 2.6 s, slowest 30 s, all 4 runs 2026-09-04..2026-10-02
            package-agent-plugins-ouroboros.class = "small";
            # nixbot: median 12 s, slowest 32 s, 6 runs in 30 days
            package-apm-context-compile.class = "small";
            # nixbot: median 18 s, slowest 174 s, 20 runs in 30 days
            package-apm-skills-compose.class = "small";
            # nixbot: median 345 s, slowest 505 s, 3 runs in 30 days
            package-atomic = {
              class = "large";
              reason = packageBuild;
            };
            # nixbot: median 30 s, slowest 2448 s, 7 runs in 30 days
            package-atuin-format.class = "small";
            # nixbot: median 364 s, slowest 1121 s, all 9 runs 2026-08-29..2026-10-23
            package-buzz-cli = {
              class = "large";
              reason = packageBuild;
            };
            # nixbot: median 289 s, slowest 743 s, all 9 runs 2026-08-29..2026-11-11
            package-buzz-git-credential-nostr.class = "medium";
            # nixbot: median 260 s, slowest 829 s, all 10 runs 2026-08-29..2026-11-11
            package-buzz-git-sign-nostr.class = "medium";
            # nixbot: median 2.8 s, slowest 55 s, all 4 runs 2026-09-04..2026-10-02
            package-buzz-source.class = "small";
            # nixbot: 0 runs, too few to class (design D4)
            package-claude-cloud-session = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 12 s, slowest 72 s, 4 runs in 30 days
            package-claude-code.class = "small";
            # nixbot: 0 runs, too few to class (design D4)
            package-claude-sandbox-setup = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 32 s, slowest 91 s, all 10 runs 2026-09-04..2026-11-11
            package-dbt-fusion.class = "small";
            # nixbot: median 4.0 s, slowest 33 s, all 7 runs 2026-09-04..2026-11-11
            package-dependency-sources.class = "small";
            # nixbot: median 7.9 s, slowest 70 s, all 21 runs 2026-09-01..2026-11-11
            package-devin-cli.class = "small";
            # nixbot: 0 runs, too few to class (design D4)
            package-fleet-deploy-request = {
              class = "medium";
              measured = false;
            };
            # nixbot: 0 runs, too few to class (design D4)
            package-fleet-deploy-watch = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 12 s, slowest 14 s, all 3 runs 2026-10-23..2026-11-11
            package-ghq-shared.class = "small";
            # nixbot: median 3.9 s, slowest 21 s, all 12 runs 2026-09-04..2026-11-11
            package-ghq-sync.class = "small";
            # nixbot: median 9.3 s, slowest 33 s, all 7 runs 2026-09-04..2026-11-11
            package-git-xet.class = "small";
            # nixbot: median 14 s, slowest 80 s, all 8 runs 2026-09-12..2026-11-11
            package-golem-binary.class = "small";
            # nixbot: 2 runs, too few to class (design D4)
            package-greptimedb-bin = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 5.6 s, slowest 33 s, all 9 runs 2026-09-04..2026-11-11
            package-hindsight.class = "small";
            # nixbot: 0 runs, too few to class (design D4)
            package-ic-wasm-bin = {
              class = "medium";
              measured = false;
            };
            # nixbot: 0 runs, too few to class (design D4)
            package-icp-cli-bin = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 12 s, slowest 106 s, all 18 runs 2026-08-29..2026-11-13
            package-impressive.class = "small";
            # nixbot: 1 run, too few to class (design D4)
            package-k3d-cluster-config = {
              class = "medium";
              measured = false;
            };
            # nixbot: 0 runs, too few to class (design D4)
            package-langfuse-cli = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 11 s, slowest 39 s, all 11 runs 2026-08-29..2026-11-11
            package-linear-cli.class = "small";
            # nixbot: median 26 s, slowest 125 s, all 9 runs 2026-09-04..2026-11-11
            package-markdown-tree-parser.class = "small";
            # nixbot: median 5.1 s, slowest 33 s, all 9 runs 2026-09-02..2026-11-11
            package-mergify-cli-bin.class = "small";
            # nixbot: 0 runs, too few to class (design D4)
            package-mops-bin = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 12 s, slowest 51 s, all 11 runs 2026-08-31..2026-11-11
            package-moshi-hook.class = "small";
            # nixbot: 0 runs, too few to class (design D4)
            package-nix-update = {
              class = "small";
              measured = false;
            };
            # nixbot: median 5.4 s, slowest 54 s, all 13 runs 2026-09-04..2026-10-23
            package-nixidy.class = "small";
            # nixbot: median 18 s, slowest 33 s, all 3 runs 2026-10-21..2026-11-11
            package-ntfy-send.class = "small";
            # nixbot: median 64 s, slowest 167 s, 3 runs in 30 days
            package-omnigent.class = "medium";
            # nixbot: median 3.0 s, slowest 33 s, all 10 runs 2026-09-17..2026-11-11
            package-omnigent-worker-login.class = "small";
            # 16 s: one --rebuild on magnetite's store, 2026-11-24 (logs/tsc-4-omnigraph-20261124-141747.log);
            # a binary repackage since 2026-11-13, so nixbot's source-build runs
            # no longer apply (design D9)
            package-omnigraph.class = "small";
            # no nixbot runs yet, too few to class
            package-omnigraph-cookbooks = {
              class = "medium";
              measured = false;
            };
            # no nixbot runs yet, too few to class
            package-omnigraph-studio = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 4.1 s, slowest 98 s, 14 runs in 30 days
            package-omp-browser-relay-extension.class = "small";
            # nixbot: median 18 s, slowest 37 s, 3 runs in 30 days
            package-ouroboros.class = "small";
            # nixbot: 1 run, too few to class (design D4)
            package-ovnfs = {
              class = "medium";
              measured = false;
            };
            # nixbot: 1 run, too few to class (design D4)
            package-perses-bin = {
              class = "medium";
              measured = false;
            };
            # nixbot: 0 runs, too few to class (design D4)
            package-pi-acp = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 2.5 s, slowest 28 s, all 7 runs 2026-09-04..2026-11-11
            package-pi-agent-extensions.class = "small";
            # nixbot: median 3.6 s, slowest 26 s, all 6 runs 2026-09-04..2026-11-11
            package-pi-openai-server-compaction.class = "small";
            # nixbot: median 11 s, slowest 28 s, all 9 runs 2026-09-04..2026-11-11
            package-pi-vim.class = "small";
            # nixbot: median 33 s, slowest 92 s, all 5 runs 2026-10-02..2026-11-11
            package-playwright-cli.class = "small";
            # nixbot: median 45 s, slowest 117 s, all 8 runs 2026-09-12..2026-11-11
            package-quarto-bin.class = "small";
            # nixbot: 0 runs, too few to class (design D4)
            package-realize-pin = {
              class = "small";
              measured = false;
            };
            # nixbot: median 5.2 s, slowest 1734 s, all 14 runs 2026-08-29..2026-11-11
            package-repo-sync.class = "small";
            # nixbot: median 7.0 s, slowest 33 s, all 8 runs 2026-09-05..2026-11-11
            package-seed-age-key.class = "small";
            # nixbot: median 11 s, slowest 35 s, 5 runs in 30 days
            package-stack-land.class = "small";
            # nixbot: median 4.7 s, slowest 98 s, 13 runs in 30 days
            package-terraform.class = "small";
            # nixbot: 1 run, too few to class (design D4)
            package-tincapp-network-pixel11 = {
              class = "medium";
              measured = false;
            };
            # nixbot: 2 runs, too few to class (design D4)
            package-tincapp-network-pixel7 = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 4.0 s, slowest 45 s, all 12 runs 2026-09-01..2026-11-14
            package-tmux-command-palette.class = "small";
            # nixbot: median 3.1 s, slowest 33 s, all 9 runs 2026-09-04..2026-11-11
            package-uncomment-bin.class = "small";
            # nixbot: median 25 s, slowest 155 s, 127 runs in 30 days
            package-vanixiets-docs.class = "small";
            # nixbot: median 28 s, slowest 544 s, 90 runs in 30 days
            package-vanixiets-docs-deps.class = "small";
            # nixbot: median 1.6 s, slowest 2.4 s, 4 runs in 30 days
            package-vanixiets-docs-payload.class = "small";
            # nixbot: median 8.4 s, slowest 50 s, all 11 runs 2026-09-03..2026-11-11
            package-worktrunk-bin.class = "small";
            # nixbot: median 127 s, slowest 634 s, all 10 runs 2026-09-04..2026-11-09
            package-xsra.class = "medium";
          };
          aarch64-darwin = {
            # nixbot: 0 runs, too few to class (design D4)
            package-agent-plugins-cloudflare = {
              class = "medium";
              measured = false;
            };
            # nixbot: 0 runs, too few to class (design D4)
            package-agent-plugins-dagster-skills = {
              class = "medium";
              measured = false;
            };
            # nixbot: 0 runs, too few to class (design D4)
            package-agent-plugins-duckdb-skills = {
              class = "medium";
              measured = false;
            };
            # nixbot: 0 runs, too few to class (design D4)
            package-agent-plugins-huggingface-skills = {
              class = "medium";
              measured = false;
            };
            # nixbot: 0 runs, too few to class (design D4)
            package-agent-plugins-ouroboros = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 7.8 s, slowest 35 s, 4 runs in 30 days
            package-apm-context-compile.class = "small";
            # nixbot: median 48 s, slowest 395 s, 39 runs in 30 days
            package-apm-skills-compose.class = "small";
            # nixbot: median 259 s, slowest 425 s, 6 runs in 30 days
            package-atomic.class = "medium";
            # nixbot: median 57 s, slowest 160 s, 4 runs in 30 days
            package-atuin-format.class = "small";
            # nixbot: median 715 s, slowest 2983 s, all 4 runs 2026-10-07..2026-11-13
            package-buzz-cli = {
              class = "large";
              reason = packageBuild;
            };
            # nixbot: median 831 s, slowest 931 s, all 4 runs 2026-10-07..2026-11-11
            package-buzz-git-credential-nostr = {
              class = "large";
              reason = packageBuild;
            };
            # nixbot: median 921 s, slowest 946 s, all 4 runs 2026-10-07..2026-11-11
            # boundary: runs of 946, 905, 844, 938 s straddle 900 s, so large
            # and on the gate until stage 5's rule decides on three fresh runs
            package-buzz-git-sign-nostr = {
              class = "large";
              reason = packageBuild;
            };
            # nixbot: 0 runs, too few to class (design D4)
            package-buzz-source = {
              class = "medium";
              measured = false;
            };
            # nixbot: 1 run, too few to class (design D4)
            package-claude-cloud-session = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 34 s, slowest 162 s, 9 runs in 30 days
            package-claude-code.class = "small";
            # nixbot: 1 run, too few to class (design D4)
            package-claude-sandbox-setup = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 162 s, slowest 526 s, all 3 runs 2026-10-07..2026-11-11
            package-dbt-fusion.class = "medium";
            # nixbot: median 214 s, slowest 275 s, all 4 runs 2026-10-07..2026-11-11
            package-dependency-sources.class = "medium";
            # nixbot: median 186 s, slowest 653 s, all 3 runs 2026-10-07..2026-11-11
            package-devin-cli.class = "medium";
            # nixbot: median 10 s, slowest 52 s, 7 runs in 30 days
            package-fleet-deploy-request.class = "small";
            # nixbot: 1 run, too few to class (design D4)
            package-fleet-deploy-watch = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 28 s, slowest 37 s, all 3 runs 2026-10-24..2026-11-11
            package-ghq-shared.class = "small";
            # nixbot: median 31 s, slowest 558 s, all 6 runs 2026-10-04..2026-11-11
            package-ghq-sync.class = "small";
            # nixbot: median 127 s, slowest 311 s, all 4 runs 2026-10-04..2026-11-11
            package-git-xet.class = "medium";
            # nixbot: median 348 s, slowest 1210 s, all 4 runs 2026-10-07..2026-11-16
            package-golem-binary = {
              class = "large";
              reason = packageBuild;
            };
            # nixbot: median 78 s, slowest 261 s, all 4 runs 2026-10-04..2026-11-11
            package-hindsight.class = "medium";
            # nixbot: 0 runs, too few to class (design D4)
            package-ic-wasm-bin = {
              class = "medium";
              measured = false;
            };
            # nixbot: 0 runs, too few to class (design D4)
            package-icp-cli-bin = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 76 s, slowest 333 s, 3 runs in 30 days
            package-impressive.class = "medium";
            # nixbot: 2 runs, too few to class (design D4)
            package-k3d-cluster-config = {
              class = "medium";
              measured = false;
            };
            # nixbot: 0 runs, too few to class (design D4)
            package-langfuse-cli = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 20 s, slowest 352 s, all 3 runs 2026-10-04..2026-11-11
            package-linear-cli.class = "small";
            # nixbot: median 185 s, slowest 653 s, all 5 runs 2026-10-04..2026-11-11
            package-markdown-tree-parser.class = "medium";
            # nixbot: 2 runs, too few to class (design D4)
            package-mergify-cli-bin = {
              class = "medium";
              measured = false;
            };
            # nixbot: 0 runs, too few to class (design D4)
            package-mops-bin = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 6.4 s, slowest 94 s, 3 runs in 30 days
            package-moshi-hook.class = "small";
            # nixbot: 0 runs, too few to class (design D4)
            package-nix-update = {
              class = "small";
              measured = false;
            };
            # nixbot: median 122 s, slowest 266 s, all 5 runs 2026-10-07..2026-11-11
            package-nixidy.class = "medium";
            # nixbot: median 107 s, slowest 340 s, all 4 runs 2026-10-21..2026-11-11
            package-ntfy-send.class = "medium";
            # nixbot: median 71 s, slowest 400 s, 4 runs in 30 days
            package-omnigent.class = "medium";
            # nixbot: median 182 s, slowest 373 s, all 4 runs 2026-10-07..2026-11-11
            package-omnigent-worker-login.class = "medium";
            # nixbot: median 54 s, slowest 7695 s, all 4 runs 2026-10-07..2026-11-13
            package-omnigraph.class = "small";
            # no nixbot runs yet, too few to class
            package-omnigraph-cookbooks = {
              class = "medium";
              measured = false;
            };
            # no nixbot runs yet, too few to class
            package-omnigraph-studio = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 5.5 s, slowest 400 s, 9 runs in 30 days
            package-omp-browser-relay-extension.class = "small";
            # nixbot: median 88 s, slowest 593 s, 3 runs in 30 days
            package-ouroboros.class = "medium";
            # nixbot: median 52 s, slowest 653 s, 3 runs in 30 days
            package-ovnfs.class = "small";
            # nixbot: 2 runs, too few to class (design D4)
            package-perses-bin = {
              class = "medium";
              measured = false;
            };
            # nixbot: 1 run, too few to class (design D4)
            package-pi-acp = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 294 s, slowest 676 s, all 3 runs 2026-10-07..2026-11-11
            package-pi-agent-extensions.class = "medium";
            # nixbot: median 222 s, slowest 421 s, all 3 runs 2026-10-07..2026-11-11
            package-pi-openai-server-compaction.class = "medium";
            # nixbot: median 38 s, slowest 351 s, all 3 runs 2026-10-07..2026-11-11
            package-pi-vim.class = "small";
            # nixbot: median 204 s, slowest 827 s, all 3 runs 2026-10-21..2026-11-11
            package-playwright-cli.class = "medium";
            # nixbot: median 270 s, slowest 310 s, all 3 runs 2026-10-07..2026-11-11
            package-quarto-bin.class = "medium";
            # nixbot: median 120 s, slowest 245 s, all 3 runs 2026-10-07..2026-11-11
            package-radicle-desktop.class = "medium";
            # nixbot: 0 runs, too few to class (design D4)
            package-realize-pin = {
              class = "small";
              measured = false;
            };
            # nixbot: median 33 s, slowest 365 s, 3 runs in 30 days
            package-repo-sync.class = "small";
            # nixbot: median 89 s, slowest 373 s, all 3 runs 2026-10-21..2026-11-11
            package-seed-age-key.class = "medium";
            # nixbot: median 45 s, slowest 134 s, 4 runs in 30 days
            package-stack-land.class = "small";
            # nixbot: median 52 s, slowest 571 s, 13 runs in 30 days
            package-terraform.class = "small";
            # nixbot: 2 runs, too few to class (design D4)
            package-tincapp-network-pixel11 = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 7.1 s, slowest 28 s, 3 runs in 30 days
            package-tincapp-network-pixel7.class = "small";
            # nixbot: median 66 s, slowest 682 s, all 7 runs 2026-10-07..2026-11-14
            package-tmux-command-palette.class = "medium";
            # nixbot: 2 runs, too few to class (design D4)
            package-uncomment-bin = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 61 s, slowest 486 s, 133 runs in 30 days
            package-vanixiets-docs.class = "medium";
            # nixbot: median 268 s, slowest 723 s, 75 runs in 30 days
            package-vanixiets-docs-deps.class = "medium";
            # nixbot: median 10 s, slowest 42 s, 14 runs in 30 days
            package-vanixiets-docs-payload.class = "small";
            # nixbot: median 59 s, slowest 337 s, all 3 runs 2026-10-07..2026-11-11
            package-worktrunk-bin.class = "small";
            # nixbot: median 740 s, slowest 1640 s, all 4 runs 2026-10-07..2026-11-13
            package-xsra = {
              class = "large";
              reason = packageBuild;
            };
          };
        }
        .${system} or { };
      checks =
        lib.mapAttrs' (n: lib.nameValuePair "package-${n}") filtered
        # The compose copies its remote dependencies from this fixed-output
        # derivation at build time only, so no package's upload carries it; one
        # path on every system, exposed once.
        // lib.optionalAttrs (system == "x86_64-linux") {
          apm-deps = self'.packages.apm-skills-compose.deps;
        };
    };
}

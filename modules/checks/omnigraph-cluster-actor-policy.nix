# Behavioural check: the policy magnetite applies to its omnigraph graphs lets
# the host's cluster actor run the operations its units and its
# omnigraph-cluster wrapper perform, and nothing more; lets the seed actor
# load into `main`, and nothing more; lets the monitor actor list the graphs
# and read them, and nothing more; and keeps the bearer-token actor `admin`'s
# access.
#
# omnigraph judges a direct write to a cluster graph by the policy the cluster
# applied to that graph and denies an actor the policy does not name
# (docs/user/operations/policy.md#actor-identity in omnigraph 0.16.0). Its
# `policy test` command reads only applied bundles, so the check applies
# magnetite's rendered cluster configuration (the directory deployed at
# /etc/omnigraph/cluster, with only its `storage:` line pointed at a local
# root under $TMPDIR) and runs `omnigraph policy test` against it with the
# packaged binary. Nothing reaches R2 or any network.
#
# The root is first initialized with a policy that names only `admin`, the
# shape of a cluster whose applied policy predates the cluster actor's grants,
# and the deployed configuration is then applied over it as the cluster actor.
# That apply must converge: a direct apply runs as the storage owner, and the
# applied policy does not judge policy changes, so the grants can reach a
# cluster that does not yet grant that actor anything.
#
# Each allow case names the operation that needs it; the deny cases hold the
# cluster actor, the seed actor and the monitor actor to those operations,
# and the `admin` cases hold the bearer-token actor to its access. `policy
# test` asks the bundle bound to `cluster` for `graph_list` and
# `config_manage`, and the graph's bundle for every other action. The cases
# run on two of the graphs, the first and the last by id, which one bundle
# binds like the rest.
# Every graph magnetite declares must then let `admin` read it: the server
# denies every read on a graph no applied policy binds, so a graph left out of
# the bundle's `applies_to` fails here.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      magnetite = self.nixosConfigurations.magnetite.config;
      omnigraph = magnetite.services.omnigraph;
      actor = omnigraph.cluster.actor;
      graphs = lib.attrNames omnigraph.cluster.settings.graphs;
      sampledGraphs = lib.unique [
        (lib.head graphs)
        (lib.last graphs)
      ];
      clusterConfig = magnetite.environment.etc."omnigraph/cluster".source;
      # The bundle files bound to graphs rather than to the cluster scope.
      graphPolicyFiles = lib.unique (
        lib.mapAttrsToList (_: policy: policy.file) (
          lib.filterAttrs (_: policy: lib.any (g: lib.elem g graphs) (policy.applies_to or [ ])) (
            omnigraph.cluster.settings.policies or { }
          )
        )
      );

      case =
        id: actorName: action: extra: expect:
        {
          inherit id action expect;
          actor = actorName;
        }
        // extra;
      onMain = {
        branch = "main";
      };
      intoMain = {
        target_branch = "main";
      };
      mainToMain = onMain // intoMain;

      testsFile =
        name: cases:
        pkgs.writeText "omnigraph-cluster-actor-policy-${name}.tests.yaml" (
          builtins.toJSON {
            version = 1;
            inherit cases;
          }
        );

      policyTests =
        graph:
        let
          seeder = omnigraph.cluster.graphs.${graph}.seed.actor;
        in
        testsFile graph [
          # cluster apply of a schema change, and recovery of a started one
          (case "cluster-actor-schema-apply-for-cluster-apply" actor "schema_apply" intoMain "allow")
          # cluster apply that deletes the graph, and recovery of that deletion
          (case "cluster-actor-read-for-graph-deletion" actor "read" onMain "allow")
          # omnigraph-optimize
          (case "cluster-actor-maintain-for-optimize" actor "maintain" onMain "allow")
          # Nothing runs cleanup or writes data as the cluster actor.
          (case "cluster-actor-no-reclaim" actor "reclaim" { } "deny")
          (case "cluster-actor-no-change" actor "change" onMain "deny")
          (case "cluster-actor-no-export" actor "export" onMain "deny")
          (case "cluster-actor-no-branch-create" actor "branch_create" mainToMain "deny")
          (case "admin-read" "admin" "read" onMain "allow")
          (case "admin-export" "admin" "export" onMain "allow")
          (case "admin-change" "admin" "change" onMain "allow")
          (case "admin-invoke-query" "admin" "invoke_query" { } "allow")
          (case "admin-schema-apply" "admin" "schema_apply" intoMain "allow")
          (case "admin-branch-create" "admin" "branch_create" mainToMain "allow")
          (case "admin-branch-delete" "admin" "branch_delete" intoMain "allow")
          (case "admin-branch-merge" "admin" "branch_merge" mainToMain "allow")
          (case "admin-no-maintain" "admin" "maintain" onMain "deny")
          (case "admin-no-reclaim" "admin" "reclaim" { } "deny")
          # omnigraph-seed-<graph>: a served load into the existing `main`
          # checks `change` on `main` alone.
          (case "seeder-change-main-for-seed-load" seeder "change" onMain "allow")
          (case "seeder-no-change-other-branch" seeder "change" { branch = "feature"; } "deny")
          (case "seeder-no-read" seeder "read" onMain "deny")
          (case "seeder-no-export" seeder "export" onMain "deny")
          (case "seeder-no-invoke-query" seeder "invoke_query" { } "deny")
          (case "seeder-no-schema-apply" seeder "schema_apply" intoMain "deny")
          (case "seeder-no-branch-create" seeder "branch_create" mainToMain "deny")
          (case "seeder-no-branch-delete" seeder "branch_delete" intoMain "deny")
          (case "seeder-no-branch-merge" seeder "branch_merge" mainToMain "deny")
          (case "seeder-no-maintain" seeder "maintain" onMain "deny")
          (case "seeder-no-reclaim" seeder "reclaim" { } "deny")
          # omnigraph-probe: `GET /graphs` checks `graph_list`, and
          # `GET /graphs/<graph>/snapshot` checks `read` on `main`.
          (case "monitor-graph-list-for-probe" "monitor" "graph_list" { } "allow")
          (case "monitor-read-main-for-probe" "monitor" "read" onMain "allow")
          (case "monitor-no-change" "monitor" "change" onMain "deny")
          (case "monitor-no-export" "monitor" "export" onMain "deny")
          (case "monitor-no-schema-apply" "monitor" "schema_apply" intoMain "deny")
          (case "monitor-no-maintain" "monitor" "maintain" onMain "deny")
          (case "monitor-no-config-manage" "monitor" "config_manage" { } "deny")
        ];

      readableTests = testsFile "admin-read" [ (case "admin-read" "admin" "read" onMain "allow") ];

      # The first state: a graph policy that names only `admin`.
      adminOnlyPolicy = pkgs.writeText "admin-only.policy.yaml" ''
        version: 1
        groups:
          operators: [admin]
        rules:
          - id: operator-data
            allow:
              actors: { group: operators }
              actions: [read]
      '';

      omnigraph-cluster-actor-policy =
        pkgs.runCommand "omnigraph-cluster-actor-policy"
          {
            nativeBuildInputs = [
              omnigraph.package
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
            ];
            meta.description = "behavioural check: magnetite's applied omnigraph policy grants the cluster actor exactly what its units need and keeps admin's access";
          }
          ''
            set -euo pipefail
            fail() {
              echo "FAIL: $*" >&2
              exit 1
            }
            export HOME="$TMPDIR/home" OMNIGRAPH_HOME="$TMPDIR/omnigraph-home"
            mkdir -p "$HOME" "$OMNIGRAPH_HOME" "$TMPDIR/root"
            root="file://$TMPDIR/root"

            render() {
              rm -rf "$TMPDIR/config"
              cp -rL ${clusterConfig} "$TMPDIR/config"
              chmod -R u+w "$TMPDIR/config"
              [ "$(grep -c '^storage: ' "$TMPDIR/config/cluster.yaml")" = 1 ] \
                || fail "cluster.yaml has no single top-level storage line"
              sed -i "s|^storage: .*|storage: $root|" "$TMPDIR/config/cluster.yaml"
              for file in ${lib.escapeShellArgs graphPolicyFiles}; do
                [ -f "$TMPDIR/config/$file" ] || fail "the rendered configuration has no policy file $file"
              done
            }

            # A local root takes an unleased lock and waits for nothing, so
            # each command is bounded only against a hang.
            apply() {
              local label=$1
              if ! timeout 120 omnigraph --as ${lib.escapeShellArg actor} --target "$root" \
                cluster apply --config "$TMPDIR/config" --json >"$TMPDIR/$label.json" 2>"$TMPDIR/$label.err"; then
                cat "$TMPDIR/$label.err" "$TMPDIR/$label.json" >&2
                fail "cluster apply of the $label configuration as ${actor} failed"
              fi
              jq -e '.status == "complete" and .result.converged' "$TMPDIR/$label.json" >/dev/null \
                || fail "cluster apply of the $label configuration as ${actor} did not converge"
            }

            render
            for file in ${lib.escapeShellArgs graphPolicyFiles}; do
              cp ${adminOnlyPolicy} "$TMPDIR/config/$file"
            done
            apply admin-only

            render
            apply deployed

            lock=$(timeout 60 omnigraph --target "$root" cluster status --json | jq -r '.lock_id // empty')
            [ -z "$lock" ] || fail "the converged apply left the admission lock $lock held"

            for graph in ${lib.escapeShellArgs sampledGraphs}; do
              timeout 60 omnigraph --target "$root" --graph "$graph" policy validate
            done
            ${lib.concatMapStrings (graph: ''
              timeout 60 omnigraph --target "$root" --graph ${lib.escapeShellArg graph} policy test --tests ${policyTests graph}
            '') sampledGraphs}
            for graph in ${lib.escapeShellArgs graphs}; do
              timeout 60 omnigraph --target "$root" --graph "$graph" policy test --tests ${readableTests} \
                || fail "admin cannot read graph $graph: no applied policy grants it"
            done
            touch "$out"
          '';
    in
    {
      # 11 s: three --rebuild runs on magnetite's store, 2026-11-25 (10.5 to
      # 10.9 s each), with the ten cookbook graphs.
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-cluster-actor-policy.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit omnigraph-cluster-actor-policy;
      };
    };
}

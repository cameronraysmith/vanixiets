# Behavioural check: the policy magnetite applies to its omnigraph graph lets
# the host's cluster actor run the operations its units and its
# omnigraph-cluster wrapper perform, and nothing more, while the bearer-token
# actor `admin` keeps its access.
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
# cluster actor to those operations, and the `admin` cases hold the
# bearer-token actor to its access.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      magnetite = self.nixosConfigurations.magnetite.config;
      omnigraph = magnetite.services.omnigraph;
      actor = omnigraph.cluster.actor;
      graph = "dev";
      clusterConfig = magnetite.environment.etc."omnigraph/cluster".source;
      # The bundle file bound to the graph; the binding rules allow one.
      graphPolicyFiles = lib.mapAttrsToList (_: policy: policy.file) (
        lib.filterAttrs (_: policy: lib.elem graph (policy.applies_to or [ ])) (
          omnigraph.cluster.settings.policies or { }
        )
      );
      graphPolicyFile =
        assert lib.assertMsg (
          lib.length graphPolicyFiles == 1
        ) "magnetite binds ${toString (lib.length graphPolicyFiles)} policies to graph ${graph}, not one";
        lib.head graphPolicyFiles;

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

      policyTests = pkgs.writeText "omnigraph-cluster-actor-policy.tests.yaml" (
        builtins.toJSON {
          version = 1;
          cases = [
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
          ];
        }
      );

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
              [ -f "$TMPDIR/config/"${lib.escapeShellArg graphPolicyFile} ] \
                || fail "the rendered configuration has no policy file ${graphPolicyFile}"
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
            cp ${adminOnlyPolicy} "$TMPDIR/config/"${lib.escapeShellArg graphPolicyFile}
            apply admin-only

            render
            apply deployed

            lock=$(timeout 60 omnigraph --target "$root" cluster status --json | jq -r '.lock_id // empty')
            [ -z "$lock" ] || fail "the converged apply left the admission lock $lock held"

            timeout 60 omnigraph --target "$root" --graph ${graph} policy validate
            timeout 60 omnigraph --target "$root" --graph ${graph} policy test --tests ${policyTests}
            touch "$out"
          '';
    in
    {
      # 3 s: one --rebuild on magnetite's store, 2026-11-25 (11 s for the
      # first build, evaluation and the rendered configuration included).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-cluster-actor-policy.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit omnigraph-cluster-actor-policy;
      };
    };
}

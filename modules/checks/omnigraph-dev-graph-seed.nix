# Behavioural check: the omnigraph-cookbooks dev graph that magnetite serves
# as graph `dev` loads its pinned seed and answers the cookbook's questions
# under the packaged omnigraph.
#
# The check applies magnetite's rendered cluster configuration (the directory
# deployed at /etc/omnigraph/cluster, with only its `storage:` line pointed at
# a local root under $TMPDIR) as the cluster actor, then loads
# dev-graph/seed.jsonl from the same pinned cookbooks with `--mode append`, as
# the cookbook documents for a fresh graph. A direct load to a cluster graph
# is judged by the policy the cluster applied to that graph and refused before
# any effect for an actor it does not admit (references/server-policy.md of
# the skill built into omnigraph 0.16.0, "Direct access is a separate trust
# boundary"); the direct actor is self-declared, so no token is involved. The
# load is therefore made as `admin`, the actor magnetite's dev policy grants
# `change`, after a load as the cluster actor, which holds no `change`, has
# been refused.
#
# The questions run as ad-hoc queries over the rendered configuration's
# queries/ files, the source the cluster registers as stored queries: invoking
# a stored query by name needs a server, and a direct read runs the same
# query text without one. Nothing reaches R2 or any network.
#
# The expected results are taken from dev-graph/README.md ("Questions you can
# ask", "Sample data") and dev-graph/seed.md at the cookbooks revision pinned
# in pkgs/by-name/omnigraph-cookbooks/pin.json; site.json there features the
# same four questions as the README. A pin update that changes the seed or
# what those files document updates the expectations below in the same pull
# request, and this check failing is the signal to do so. The `ready` query
# orders only by priority, so the check holds the three priority-2 issues the
# README names as leading as a set, not in a tie order the query does not
# define. For `release_prs` the README states two pull requests, one of which
# caused the presence leak incident, which seed.md names as
# pr-presence-optimize.
{ self, lib, ... }:
let
  # The seed's documented totals: 102 nodes across 22 types, 239 edges.
  expectedNodes = 102;
  expectedEdges = 239;
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      nixos = self.nixosConfigurations.magnetite;
      magnetite = nixos.config;
      omnigraph = magnetite.services.omnigraph;
      actor = omnigraph.cluster.actor;
      graph = "dev";
      clusterConfig = magnetite.environment.etc."omnigraph/cluster".source;
      # The cookbooks package magnetite's configuration takes the schema and
      # queries from, so the seed comes from the same pinned commit.
      seed = "${nixos.pkgs.omnigraph-cookbooks}/dev-graph/seed.jsonl";

      omnigraph-dev-graph-seed =
        pkgs.runCommand "omnigraph-dev-graph-seed"
          {
            nativeBuildInputs = [
              omnigraph.package
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
            ];
            meta.description = "behavioural check: the pinned omnigraph-cookbooks dev graph seed loads into magnetite's applied configuration and answers the cookbook's documented questions";
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

            cp -rL ${clusterConfig} "$TMPDIR/config"
            chmod -R u+w "$TMPDIR/config"
            [ "$(grep -c '^storage: ' "$TMPDIR/config/cluster.yaml")" = 1 ] \
              || fail "cluster.yaml has no single top-level storage line"
            sed -i "s|^storage: .*|storage: $root|" "$TMPDIR/config/cluster.yaml"

            # A local root takes an unleased lock and waits for nothing, so
            # each command is bounded only against a hang.
            if ! timeout 120 omnigraph --as ${lib.escapeShellArg actor} --target "$root" \
              cluster apply --config "$TMPDIR/config" --json >"$TMPDIR/apply.json" 2>"$TMPDIR/apply.err"; then
              cat "$TMPDIR/apply.err" "$TMPDIR/apply.json" >&2
              fail "cluster apply of the deployed configuration as ${actor} failed"
            fi
            jq -e '.status == "complete" and .result.converged' "$TMPDIR/apply.json" >/dev/null \
              || fail "cluster apply of the deployed configuration as ${actor} did not converge"

            load() {
              timeout 120 omnigraph --as "$1" --target "$root" --graph ${graph} \
                load --data ${seed} --mode append --json
            }

            # The applied policy judges the load: the cluster actor is refused
            # before any effect.
            if load ${lib.escapeShellArg actor} >"$TMPDIR/denied.json" 2>"$TMPDIR/denied.err"; then
              fail "a load as ${actor}, which the dev policy grants no change, was accepted"
            fi
            jq -e '.code == "forbidden" and .disposition.effects == "none"' "$TMPDIR/denied.json" >/dev/null \
              || { cat "$TMPDIR/denied.err" "$TMPDIR/denied.json" >&2; fail "the load as ${actor} failed for a reason other than the policy"; }

            # omnigraph 0.16.0 keeps the root's admission lock after a direct
            # write even when it is refused, and the next writer would find it
            # held. Nothing else runs on this root, so a lock left now is the
            # refused load's and is released by its ID, as omnigraph documents
            # for a direct write that has finished.
            lock=$(timeout 60 omnigraph --target "$root" cluster status --json | jq -r '.lock_id // empty')
            if [ -n "$lock" ]; then
              timeout 60 omnigraph --target "$root" cluster force-unlock "$lock" --json \
                | jq -e '.unlocked' >/dev/null || fail "the refused load's admission lock $lock was not released"
            fi

            # An append onto rows the refused load had written would fail on
            # key_conflict, so this load also shows the refusal wrote nothing.
            if ! load admin >"$TMPDIR/load.json" 2>"$TMPDIR/load.err"; then
              cat "$TMPDIR/load.err" "$TMPDIR/load.json" >&2
              fail "the seed load as admin failed"
            fi
            nodes=$(jq '[.nodes[].entities_loaded] | add' "$TMPDIR/load.json")
            edges=$(jq '[.edges[].entities_loaded] | add' "$TMPDIR/load.json")
            [ "$nodes" = ${toString expectedNodes} ] || fail "the seed loaded $nodes nodes, not ${toString expectedNodes}"
            [ "$edges" = ${toString expectedEdges} ] || fail "the seed loaded $edges edges, not ${toString expectedEdges}"

            # ask <file> <query> <params> <jq assertion over the rows>
            ask() {
              local file=$1 name=$2 params=$3 assertion=$4
              if ! timeout 60 omnigraph --target "$root" --graph ${graph} \
                query --query "$TMPDIR/config/queries/$file" "$name" --params "$params" --json \
                >"$TMPDIR/$name.json" 2>"$TMPDIR/$name.err"; then
                cat "$TMPDIR/$name.err" "$TMPDIR/$name.json" >&2
                fail "query $name failed"
              fi
              jq -e --arg name "$name" '.query_name == $name' "$TMPDIR/$name.json" >/dev/null \
                || fail "query $name answered as another query"
              if ! jq -e ".rows | $assertion" "$TMPDIR/$name.json" >/dev/null; then
                jq -c '.rows' "$TMPDIR/$name.json" >&2
                fail "query $name did not return the documented answer: $assertion"
              fi
            }
            slugs() { echo "map(.[\"$1.slug\"]) | sort"; }

            ask queries.gq ready '{}' \
              "length == 5
               and (.[0:3] | $(slugs i)) == [\"iss-auth-mfa\", \"iss-flaky-sync-test\", \"iss-safari-login\"]
               and ($(slugs i)) == [\"iss-auth-mfa\", \"iss-billing-metering\", \"iss-flaky-sync-test\", \"iss-presence-scale\", \"iss-safari-login\"]"
            ask queries.gq blocked '{}' \
              'map([.["i.slug"], .["b.slug"]]) | sort
               == [["iss-billing-webhooks", "iss-billing-metering"], ["iss-offline-conflict-ui", "iss-offline-queue"]]'
            ask queries.gq blocked_on_upstream '{}' \
              'map([.["i.slug"], .["blk.slug"], .["blk.system"]])
               == [["iss-offline-queue", "blk-crdt-lib", "automerge-rs"]]'
            ask issues-dashboard.gq epic_spec '{"epic":"epc-offline-sync"}' \
              'map([.["s.slug"], .["s.status"], .["s.version"]])
               == [["spc-offline-sync-rfc", "approved", "2.1"]]'
            ask queries.gq release_prs '{"release":"rel-v1-4-0"}' \
              'length == 2 and any(.[]; .["p.slug"] == "pr-presence-optimize")'
            ask queries.gq unheld_invariants '{}' \
              "$(slugs inv) == [\"inv-single-writer\"]"
            ask queries.gq assumptions '{}' \
              'map(select((.["a.guardRef"] // "") == "") | .["a.slug"]) == ["asm-storage-ordering"]'
            ask queries.gq capabilities_without_component '{}' \
              "$(slugs cap) == [\"cap-offline-editing\"]"
            touch "$out"
          '';
    in
    {
      # 3 s: three --rebuild runs on magnetite's store, 2026-11-25 (2.8 to
      # 2.9 s each, evaluation included).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-dev-graph-seed.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit omnigraph-dev-graph-seed;
      };
    };
}

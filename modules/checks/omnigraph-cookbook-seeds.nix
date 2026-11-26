# Behavioural check: every example graph magnetite serves, one per cookbook of
# the pinned omnigraph-cookbooks, loads its seed under the packaged omnigraph
# and answers through its stored queries.
#
# The check applies magnetite's rendered cluster configuration (the directory
# deployed at /etc/omnigraph/cluster, with only its `storage:` line pointed at
# a local root under $TMPDIR) as the cluster actor, starts omnigraph-server on
# that root with --require-all-graphs as magnetite runs it, and drives it over
# loopback the way the omnigraph-seed-<graph> units and clients do. Nothing
# reaches R2 or any other network.
#
# It fails when:
#   - the pinned package holds a cookbook (a top-level directory with a
#     schema.pg and a seed.jsonl, found at build time) that magnetite does not
#     serve as a seeded graph, or magnetite seeds a graph from a directory the
#     package lacks;
#   - a seed does not load with `mode=append` on `main` as the graph's seed
#     actor, under the policy magnetite applies to the graph;
#   - the graph then holds, per node and edge type, other counts than its
#     seed.jsonl has rows, counted from the file at build time;
#   - a stored read without parameters (every `query <name>()` in the graph's
#     queries/*.gq that inserts, updates or deletes nothing, the parse the
#     cookbooks' own qualifier uses in scripts/check-cookbooks.py) answers
#     with an error;
#   - a question the cookbook's site.json features, run with its parameters,
#     returns no rows, which is what scripts/check-cookbooks.py in the pinned
#     source asserts for them;
#   - a featured question whose result README.md or seed.md states explicitly
#     answers otherwise, or, for dev-graph, one of the further reads its
#     README.md and seed.md answer (`documentedAnswers` below).
#
# Stored reads that take parameters and are not featured, and every stored
# write, are covered by the configuration's build and the cluster apply, which
# register each stored query and type-check it against its graph's schema.
#
# Featured questions whose stored query reads the current time are held to
# rows only, since an exact answer would change as the date moves:
# `ready` of beads (documented in its seed.md), `overdue_recommendations` of
# health-record (documented in its seed.md) and `tasks_next` of second-brain.
# Featured questions no README.md or seed.md answers explicitly are held to
# rows only too: beads' `ancestor_blockers` and `downstream`, industry-intel's
# `pattern_momentum`, `recent_signals` and `pattern_signals`, and every
# featured question of pharma-intel, second-brain and vc-os.
#
# The expected results are those documented at the cookbooks revision pinned
# in pkgs/by-name/omnigraph-cookbooks/pin.json. A pin update that changes a
# seed or what those files document updates them in the same pull request,
# and this check failing is the signal to do so. dev-graph's `ready` orders
# only by priority, so its three priority-2 issues are held as a set, not in a
# tie order the query does not define; for `release_prs` its README states two
# pull requests, one of which caused the presence leak incident, which seed.md
# names as pr-presence-optimize.
{ self, lib, ... }:
let
  slugs = column: "map(.[\"${column}\"]) | sort";

  # Per cookbook directory: the documented answers of its featured
  # questions, as a jq assertion over the rows of the stored query.
  documentedAnswers = {
    # agent-ops/seed.md, "Featured questions" table.
    agent-ops = [
      {
        query = "revision_scorecard";
        params.workflow = "wf-review-pr";
        answer = ''
          map([.revision, .status, .verdict, .judgments, .runs]) | sort
          == [[1, "retired", "fail", 5, 4], [1, "retired", "pass", 7, 5],
              [2, "active", "fail", 1, 1], [2, "active", "pass", 7, 4]]'';
      }
      {
        query = "criterion_failures";
        answer = ''
          map([.criterion, .revision, .failures]) | sort
          == [["crit-repro-script", 1, 1], ["crit-repro-version", 1, 1],
              ["crit-review-no-style-nits", 2, 1], ["crit-triage-routes-owner", 1, 1]]'';
      }
      {
        query = "revision_cost";
        # Runs and cost in tenths of a cent, which the documented dollar
        # amounts state exactly.
        answer = ''
          map([.runs, (.cost_usd * 1000 | round)]) | sort
          == ([[6, 2380], [5, 2570], [4, 2890], [2, 3160], [2, 3090], [2, 420], [4, 152]] | sort)'';
      }
      {
        query = "due_workflows";
        params.as_of = "2026-11-23T12:00:00Z";
        answer = ''
          map([.workflow, .due_at]) | sort
          == [["wf-judge-runs", "2026-11-23T06:00:00"], ["wf-triage-support", "2026-11-23T10:00:00"]]'';
      }
      {
        query = "runs_to_judge";
        answer = ''${slugs "run"} == ["wf-review-pr@pr-414", "wf-triage-support@2026-11-23T09"]'';
      }
    ];
    # beads/seed.md, "What the seed demonstrates": the issues `blocked`
    # matches by a direct edge, with the issue each waits on.
    beads = [
      {
        query = "blocked";
        answer = ''
          map([.["i.slug"], .blocker]) | sort
          == [["lk-conflict", "lk-queue"], ["lk-share", "lk-acl"], ["lk-sync-docs", "lk-conflict"]]'';
      }
    ];
    # company-brain/seed.md, "What the seed demonstrates".
    company-brain = [
      {
        query = "current_decisions";
        answer = ''
          ${slugs "decision"}
          == ["billing-freeze", "checkout-launch-nov-13", "checkout-saved-cards", "search-in-house"]'';
      }
      {
        query = "contested_claims";
        answer = ''map([.claim, .contradicts]) == [["address-step-tickets", "later-steps-not-needed"]]'';
      }
      {
        query = "decision_evidence";
        params.decision = "search-in-house";
        answer = ''
          .[0].claim == "vendor-quote-3x"
          and (.[1:] | ${slugs "claim"}) == ["keep-search-in-house", "prototype-meets-latency"]'';
      }
      {
        query = "actions_from_source";
        params.source = "meet:search-review-2026-10-02";
        answer = ''
          ${slugs "action"}
          == ["Cancel the hosted search trial", "Ship the in-house search prototype to staging"]'';
      }
    ];
    # dev-graph/README.md ("Questions you can ask", "Sample data") and
    # dev-graph/seed.md.
    dev-graph = [
      {
        query = "ready";
        answer = ''
          length == 5
          and (.[0:3] | ${slugs "i.slug"}) == ["iss-auth-mfa", "iss-flaky-sync-test", "iss-safari-login"]
          and (${slugs "i.slug"}) == ["iss-auth-mfa", "iss-billing-metering", "iss-flaky-sync-test", "iss-presence-scale", "iss-safari-login"]'';
      }
      {
        query = "blocked";
        answer = ''
          map([.["i.slug"], .["b.slug"]]) | sort
          == [["iss-billing-webhooks", "iss-billing-metering"], ["iss-offline-conflict-ui", "iss-offline-queue"]]'';
      }
      {
        query = "blocked_on_upstream";
        answer = ''
          map([.["i.slug"], .["blk.slug"], .["blk.system"]])
          == [["iss-offline-queue", "blk-crdt-lib", "automerge-rs"]]'';
      }
      {
        query = "epic_spec";
        params.epic = "epc-offline-sync";
        answer = ''
          map([.["s.slug"], .["s.status"], .["s.version"]])
          == [["spc-offline-sync-rfc", "approved", "2.1"]]'';
      }
      {
        query = "release_prs";
        params.release = "rel-v1-4-0";
        answer = ''length == 2 and any(.[]; .["p.slug"] == "pr-presence-optimize")'';
      }
      {
        query = "unheld_invariants";
        answer = ''${slugs "inv.slug"} == ["inv-single-writer"]'';
      }
      {
        query = "assumptions";
        answer = ''map(select((.["a.guardRef"] // "") == "") | .["a.slug"]) == ["asm-storage-ordering"]'';
      }
      {
        query = "capabilities_without_component";
        answer = ''${slugs "cap.slug"} == ["cap-offline-editing"]'';
      }
    ];
    # hardware-program/seed.md: the budget table and the reads table.
    hardware-program = [
      {
        query = "budget_rollup";
        answer = ''
          map([.["r.slug"], .contributors, .violated]) | sort
          == [["dc-eps-generation", 1, false], ["dc-pl-mass", 2, true], ["dc-str-mass", 2, false],
              ["req-lv-mass", 17, false], ["req-sys-power", 8, false]]'';
      }
      {
        query = "impacted_tests";
        params.slug = "req-lv-mass";
        answer = ''map([.["t.slug"], .verifies]) == [["tc-str-weigh", "dc-str-mass"]]'';
      }
      {
        query = "trace_up";
        params.slug = "dc-adcs-jitter";
        answer = ''${slugs "p.slug"} == ["mg-imaging", "req-pointing"]'';
      }
      {
        query = "unverified_requirements";
        answer = ''
          ${slugs "r.slug"}
          == ["dc-adapter", "dc-adcs-jitter", "dc-eps-generation", "dc-pl-mass",
              "req-passivation", "req-prop-deltav", "req-protoflight"]'';
      }
      {
        query = "gate_not_passing";
        params.milestone = "ms-cdr";
        answer = ''
          map([.["r.slug"], .["t.status"]]) | sort
          == [["dc-batt-temp", "not_run"], ["dc-bus-voltage", "not_run"], ["req-obc-temp", "fail"]]'';
      }
    ];
    # health-record/seed.md, the table of stored reads.
    health-record = [
      {
        query = "off_target";
        answer = ''map([.marker, .value]) | sort == [["mk-ldl", 2.1], ["mk-vitd", 71]]'';
      }
      {
        query = "intervention_effect";
        params.intervention = "int-rosuvastatin";
        answer = ''
          length == 8
          and (group_by(.marker) | map([.[0].marker, (map(.after_start) | sort)]))
            == [["mk-apob", [false, false, false, true]], ["mk-ldl", [false, false, false, true]]]'';
      }
      {
        query = "incomplete_series";
        answer = ''map([.disease, .doses_given, .["w.series_doses"]]) == [["cond-hepatitis-b", 2, 3]]'';
      }
      {
        query = "contested_hypotheses";
        answer = ''${slugs "h.slug"} == ["hyp-apob-diet", "hyp-fatigue-iron", "hyp-fatigue-iron"]'';
      }
    ];
    # industry-intel/seed.md, "Signal → Pattern edges (ContradictsPattern)".
    industry-intel = [
      {
        query = "contested_patterns";
        answer = ''
          map([.["p.slug"], .contradictions]) | sort
          == [["pat-accelerated-research", 1], ["pat-saaspocalypse", 2], ["pat-sovereign-ai", 1]]'';
      }
    ];
  };
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      nixos = self.nixosConfigurations.magnetite;
      magnetite = nixos.config;
      omnigraph = magnetite.services.omnigraph;
      actor = omnigraph.cluster.actor;
      clusterConfig = magnetite.environment.etc."omnigraph/cluster".source;
      cookbooksPackage = nixos.pkgs.omnigraph-cookbooks;

      # The graphs magnetite seeds, each with its seed file, the cookbook
      # directory that file lies in and the queries directory the cluster
      # registers. The directory's name is plain text, compared with the
      # package's directories at build time.
      seededGraphs = lib.mapAttrsToList (
        id: graph:
        let
          cookbook = builtins.unsafeDiscardStringContext (baseNameOf (dirOf graph.seed.file));
        in
        assert lib.assertMsg (
          graph.seed.file == "${cookbooksPackage}/${cookbook}/seed.jsonl"
        ) "magnetite seeds graph ${id} from ${graph.seed.file}, outside the pinned omnigraph-cookbooks";
        {
          inherit id cookbook;
          inherit (graph.seed) actor file;
          queries = omnigraph.cluster.settings.graphs.${id}.queries;
          answers = documentedAnswers.${cookbook} or [ ];
        }
      ) (lib.filterAttrs (_: graph: graph.seed != null) omnigraph.cluster.graphs);

      plan =
        assert lib.assertMsg (lib.all (cookbook: lib.any (graph: graph.cookbook == cookbook) seededGraphs) (
          lib.attrNames documentedAnswers
        )) "documentedAnswers names a cookbook magnetite does not seed";
        pkgs.writeText "omnigraph-cookbook-seeds.json" (
          builtins.toJSON {
            graphs = seededGraphs;
            cookbooks = "${cookbooksPackage}";
          }
        );

      # Seed actors take a bearer token each; admin reads.
      tokens = lib.listToAttrs (
        map (a: lib.nameValuePair a "cookbook-seeds-${a}") (
          lib.unique ([ "admin" ] ++ map (graph: graph.actor) seededGraphs)
        )
      );

      driver = pkgs.writeText "omnigraph-cookbook-seeds.py" ''
        import collections, json, os, pathlib, re, socket, subprocess, sys, time
        import urllib.error, urllib.request

        config, root, plan_path = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
        plan = json.loads(pathlib.Path(plan_path).read_text())
        cookbooks = pathlib.Path(plan["cookbooks"])
        tokens = json.loads(os.environ["OMNIGRAPH_SERVER_BEARER_TOKENS_JSON"])
        failures = []

        def fail(message):
            print(f"FAIL: {message}", file=sys.stderr)
            failures.append(message)

        # The cookbooks of the pinned package, against the graphs magnetite seeds.
        found = sorted(d.name for d in cookbooks.iterdir()
                       if (d / "schema.pg").is_file() and (d / "seed.jsonl").is_file())
        seeded = sorted(g["cookbook"] for g in plan["graphs"])
        for name in sorted(set(found) - set(seeded)):
            fail(f"the pinned cookbooks hold {name}/, which magnetite serves as no seeded graph")
        for name in sorted(set(seeded) - set(found)):
            fail(f"magnetite seeds a graph from {name}/, which the pinned cookbooks lack")

        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
        log = open("server.log", "w")
        server = subprocess.Popen(
            ["omnigraph-server", "--cluster", root, "--bind", f"127.0.0.1:{port}", "--require-all-graphs"],
            stdout=log, stderr=subprocess.STDOUT)
        http = urllib.request.build_opener(urllib.request.ProxyHandler({}))

        def request(actor, path, body=None, content_type="application/json"):
            data = None if body is None else body if isinstance(body, bytes) else json.dumps(body).encode()
            headers = {"Omnigraph-Http-Api": "0.14", "Authorization": f"Bearer {tokens[actor]}"}
            if data is not None:
                headers["Content-Type"] = content_type
            req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=data, headers=headers)
            try:
                response = http.open(req, timeout=60)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                return response.status, json.loads(response.read() or b"null")

        try:
            deadline = time.monotonic() + 60
            while True:
                if server.poll() is not None:
                    sys.exit(f"FAIL: omnigraph-server exited {server.returncode}; see server.log:\n" + open("server.log").read())
                try:
                    status, ready = request("admin", "/readyz")
                    if status == 200 and ready["loading_graph_count"] == 0:
                        break
                except OSError:
                    pass
                if time.monotonic() > deadline:
                    sys.exit("FAIL: omnigraph-server did not serve within 60 s")
                time.sleep(0.1)
            if ready["served_graph_count"] != len(plan["graphs"]):
                fail(f"the server serves {ready['served_graph_count']} graphs, not {len(plan['graphs'])}")

            QUERY = re.compile(r"^query\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)", re.M)
            STRING = re.compile(r'"(?:[^"\\]|\\.)*"')
            WRITES = re.compile(r"\b(insert|update|delete)\b")

            for graph in plan["graphs"]:
                gid, cookbook = graph["id"], cookbooks / graph["cookbook"]
                seed = pathlib.Path(graph["file"]).read_bytes()
                rows = [json.loads(line) for line in seed.decode().splitlines() if line.strip()]
                expected = collections.Counter(
                    ("node", r["type"]) if "type" in r else ("edge", r["edge"]) for r in rows)

                status, loaded = request(graph["actor"], f"/graphs/{gid}/load/ndjson?mode=append&branch=main",
                                         seed, "application/x-ndjson")
                if status != 200 or loaded.get("mode") != "append" or not (loaded.get("commit") or {}).get("graph_commit_id"):
                    fail(f"{gid}: the seed load as {graph['actor']} answered {status}: {json.dumps(loaded)[:2000]}")
                    continue
                reported = collections.Counter()
                for kind in ("node", "edge"):
                    for entry in loaded[kind + "s"]:
                        if entry["entities_loaded"]:
                            reported[(kind, entry["name"])] = entry["entities_loaded"]
                status, snapshot = request("admin", f"/graphs/{gid}/snapshot")
                stored = collections.Counter({(d["entity_kind"], d["type_name"]): d["entity_count"]
                                              for d in snapshot["datasets"] if d["entity_count"]})
                for label, counts in (("the load reported", reported), ("the graph holds", stored)):
                    if counts != expected:
                        fail(f"{gid}: {label} {sorted(counts.items())}, but {graph['cookbook']}/seed.jsonl has {sorted(expected.items())}")

                reads = []
                for path in sorted((config / graph["queries"]).glob("*.gq")):
                    source = path.read_text()
                    starts = list(QUERY.finditer(source))
                    for i, match in enumerate(starts):
                        body = source[match.end():starts[i + 1].start() if i + 1 < len(starts) else len(source)]
                        body = re.sub(r"//.*", "", STRING.sub('""', body))
                        if not match.group(2).strip() and not WRITES.search(body):
                            reads.append(match.group(1))
                if not reads:
                    fail(f"{gid}: found no stored read without parameters in {graph['queries']}")
                for name in reads:
                    status, answer = request("admin", f"/graphs/{gid}/queries/{name}", {"params": {}})
                    if status != 200 or not isinstance(answer.get("rows"), list):
                        fail(f"{gid}: stored read {name} answered {status}: {json.dumps(answer)[:1000]}")

                questions = json.loads((cookbook / "site.json").read_text())["questions"]
                featured = {q["query"]: q.get("params", {}) for q in questions}
                for name, params in featured.items():
                    status, answer = request("admin", f"/graphs/{gid}/queries/{name}", {"params": params})
                    if status != 200 or not answer.get("rows"):
                        fail(f"{gid}: featured question {name} {json.dumps(params)} answered {status} without rows: {json.dumps(answer)[:1000]}")
                for a in graph["answers"]:
                    name, params = a["query"], a.get("params", {})
                    if name in featured and featured[name] != params:
                        fail(f"{gid}: the documented answer of {name} takes {params}, site.json {featured[name]}")
                    status, answer = request("admin", f"/graphs/{gid}/queries/{name}", {"params": params})
                    if status != 200 or not isinstance(answer.get("rows"), list):
                        fail(f"{gid}: {name} {json.dumps(params)} answered {status}: {json.dumps(answer)[:1000]}")
                        continue
                    check = subprocess.run(["jq", "-e", a["answer"]], input=json.dumps(answer["rows"]),
                                           capture_output=True, text=True)
                    if check.returncode != 0:
                        fail(f"{gid}: {name} did not return the documented answer {a['answer']}\nrows: {json.dumps(answer['rows'])}")
                print(f"{gid}: {sum(expected.values())} seed rows, {len(reads)} stored reads without parameters, "
                      f"{len(featured)} featured questions, {len(graph['answers'])} documented answers")
        finally:
            server.terminate()
            server.wait(timeout=30)
        if failures:
            sys.exit(f"{len(failures)} failure(s)")
      '';

      omnigraph-cookbook-seeds =
        pkgs.runCommand "omnigraph-cookbook-seeds"
          {
            nativeBuildInputs = [
              omnigraph.package
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
              pkgs.python3
            ];
            meta.description = "behavioural check: every omnigraph-cookbooks example graph magnetite serves loads its seed and answers its stored reads and featured questions";
          }
          ''
            set -euo pipefail
            export HOME="$TMPDIR/home" OMNIGRAPH_HOME="$TMPDIR/omnigraph-home"
            mkdir -p "$HOME" "$OMNIGRAPH_HOME" "$TMPDIR/root"
            root="file://$TMPDIR/root"

            cp -rL ${clusterConfig} "$TMPDIR/config"
            chmod -R u+w "$TMPDIR/config"
            [ "$(grep -c '^storage: ' "$TMPDIR/config/cluster.yaml")" = 1 ] \
              || { echo "FAIL: cluster.yaml has no single top-level storage line" >&2; exit 1; }
            sed -i "s|^storage: .*|storage: $root|" "$TMPDIR/config/cluster.yaml"

            # A local root takes an unleased lock and waits for nothing, so
            # the apply is bounded only against a hang.
            if ! timeout 120 omnigraph --as ${lib.escapeShellArg actor} --target "$root" \
              cluster apply --config "$TMPDIR/config" --json >"$TMPDIR/apply.json" 2>"$TMPDIR/apply.err"; then
              cat "$TMPDIR/apply.err" "$TMPDIR/apply.json" >&2
              echo "FAIL: cluster apply of the deployed configuration as ${actor} failed" >&2
              exit 1
            fi
            jq -e '.status == "complete" and .result.converged' "$TMPDIR/apply.json" >/dev/null \
              || { echo "FAIL: cluster apply of the deployed configuration as ${actor} did not converge" >&2; exit 1; }

            export OMNIGRAPH_SERVER_BEARER_TOKENS_JSON=${lib.escapeShellArg (builtins.toJSON tokens)}
            timeout 600 python3 ${driver} "$TMPDIR/config" "$root" ${plan}
            touch "$out"
          '';
    in
    {
      # 13 s: three --rebuild runs on magnetite's store, 2026-11-25 (12.6 to
      # 12.8 s each), ten graphs with 3,905 seed rows, 188 stored reads and
      # 43 featured questions.
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-cookbook-seeds.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit omnigraph-cookbook-seeds;
      };
    };
}

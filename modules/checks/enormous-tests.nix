# checks.x86_64-linux.enormous-tests (declare-test-size-classes design D11,
# G6): enormous-tests.service's script run against a stub `nix` and a stub
# `nix-eval-jobs`, so the logic that decides what a run is runs without a
# runtime test. The fixture revision has six tests:
#   big-pass       enormous, built, the driver's line: passed, its script time
#   big-present    enormous, its output already in the store: present, no build
#   t-evalerror    did not evaluate: failed, no derivation
#   t-fail         medium, the build fails; a dependency's log carries a
#                  `test script finished in` line, which is not the test's: failed
#   t-substituted  small, the build succeeds without the driver's line: present
#   t-timeout      small, the driver's timer fires: timed_out, the 60 s limit
# The judge requires those records in that order (the enormous tests first),
# each with exactly devloop.runtime_test_result's columns; one build per test
# not already present, each with `--builders ''`; one evaluation under
# `nix-eval-jobs --gc-roots-dir`; a root per passing or present test and the
# stale root of a test no longer declared removed; and exit 1. A second
# revision whose two tests pass or are present must exit 0.
# Each mutant of the script, alone, must fail the judge's named clause:
# presentAsPassed (a build without the driver's line recorded as passed),
# timeoutAsFailure (the timeout line not read), exitZero (exit 0 after a
# failure) and buildPresent (no store lookup before building).
{ self, lib, ... }:
let
  inherit (self.lib.enormousTestsRun) runner;
  columns = map (c: c.name) self.lib.otelCollectorSchema.devloop.tables.runtime_test_result.columns;
  scriptText = builtins.readFile ../nixos/enormous-tests/run.sh;

  mutants = {
    presentAsPassed = {
      old = ''emit present null "$build_ms" "$drv"'';
      new = ''emit passed 0 "$build_ms" "$drv"'';
      clause = "t-substituted";
    };
    timeoutAsFailure = {
      old = "'timeout reached; test terminating'";
      new = "'no such line in any log'";
      clause = "t-timeout";
    };
    exitZero = {
      old = ''exit "$failed"'';
      new = ''exit "$((failed * 0))"'';
      clause = "exit";
    };
    buildPresent = {
      old = ''if nix path-info "$out" >/dev/null 2>&1; then'';
      new = "if false; then";
      clause = "builds";
    };
  };
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      # The runner as the module renders it, with one replacement in its body.
      variant =
        name: m:
        assert lib.assertMsg (lib.hasInfix m.old scriptText)
          "enormous-tests check: mutant ${name} found nothing to replace";
        runner pkgs {
          hostName = "fixture-host";
          body = builtins.replaceStrings [ m.old ] [ m.new ] scriptText;
        };
      unmutated = runner pkgs { hostName = "fixture-host"; };

      log = derivation: lines: lib.concatMapStrings (l: "${derivation}> ${l}\n") lines;
      job = name: {
        attr = name;
        attrPath = [ name ];
        drvPath = "/fixture/${name}.drv";
        name = "vm-test-run-${name}";
        outputs.out = "/fixture/out/${name}";
        system = "x86_64-linux";
      };
      fixture = pkgs.runCommand "enormous-tests-fixture" { } ''
        mkdir -p $out/source $out/logs $out/status $out/second
        cat > $out/sizes.json <<'EOF'
        ${builtins.toJSON {
          big-pass = {
            class = "enormous";
            limit = 3600;
          };
          big-present = {
            class = "enormous";
            limit = 3600;
          };
          t-evalerror = {
            class = "medium";
            limit = 300;
          };
          t-fail = {
            class = "medium";
            limit = 300;
          };
          t-substituted = {
            class = "small";
            limit = 60;
          };
          t-timeout = {
            class = "small";
            limit = 60;
          };
        }}
        EOF
        cat > $out/jobs.jsonl <<'EOF'
        ${builtins.toJSON (job "t-timeout")}
        ${builtins.toJSON (job "t-fail")}
        ${builtins.toJSON {
          attr = "t-evalerror";
          attrPath = [ "t-evalerror" ];
          error = "error: vmTests.x86_64-linux.t-evalerror has no testSizes.vmTests entry";
        }}
        ${builtins.toJSON (job "big-present")}
        ${builtins.toJSON (job "t-substituted")}
        ${builtins.toJSON (job "big-pass")}
        EOF
        cat > $out/second/jobs.jsonl <<'EOF'
        ${builtins.toJSON (job "big-pass")}
        ${builtins.toJSON (job "big-present")}
        EOF
        printf '%s\n' /fixture/out/big-present > $out/present
        cat > $out/logs/big-pass <<'EOF'
        ${
          log "vm-test-run-big-pass" [
            "[0.01s] Test will time out and terminate in 3600.0 seconds"
            "[1690.53s] (finished: run the VM test script, in 1690.50 seconds)"
            "[1690.53s] test script finished in 1690.50s"
          ]
        }EOF
        echo 0 > $out/status/big-pass
        cat > $out/logs/t-fail <<'EOF'
        ${log "vm-test-run-some-dependency" [ "[3.00s] test script finished in 2.00s" ]}${
          log "vm-test-run-t-fail" [
            "[0.01s] Test will time out and terminate in 300.0 seconds"
            "[40.00s] Traceback (most recent call last):"
            "[40.00s] AssertionError: fixture"
          ]
        }error: builder for '/fixture/t-fail.drv' failed with exit code 1
        EOF
        echo 1 > $out/status/t-fail
        : > $out/logs/t-substituted
        echo 0 > $out/status/t-substituted
        cat > $out/logs/t-timeout <<'EOF'
        ${
          log "vm-test-run-t-timeout" [
            "[0.01s] Test will time out and terminate in 60.0 seconds"
            "[60.00s] timeout reached; test terminating..."
          ]
        }error: builder for '/fixture/t-timeout.drv' failed with exit code 1
        EOF
        echo 1 > $out/status/t-timeout
        echo 0 > $out/status/big-present
        : > $out/logs/big-present
      '';

      stubs = pkgs.runCommand "enormous-tests-stubs" { } ''
        mkdir -p $out/bin
        cat > $out/bin/nix <<'EOF'
        #!${pkgs.runtimeShell}
        printf '%q ' nix "$@" >> "$CALLS"; echo >> "$CALLS"
        case "$1" in
          flake)
            shift 2
            link=""
            while [ $# -gt 0 ]; do
              case $1 in
                --out-link) link=$2; shift 2 ;;
                *) shift ;;
              esac
            done
            ln -sfn "$FIXTURE/source" "$link"
            echo '{"locked":{"rev":"fixture-rev"},"storePath":"/fixture/source"}'
            ;;
          eval) cat "$FIXTURE/sizes.json" ;;
          path-info) grep -qxF "$2" "$FIXTURE/present" ;;
          build)
            for a in "$@"; do drv=$a; done
            name=$(basename "''${drv%^*}" .drv)
            cat "$FIXTURE/logs/$name"
            exit "$(cat "$FIXTURE/status/$name")"
            ;;
          *) echo "stub nix: unexpected $*" >&2; exit 64 ;;
        esac
        EOF
        cat > $out/bin/nix-eval-jobs <<'EOF'
        #!${pkgs.runtimeShell}
        printf '%q ' nix-eval-jobs "$@" >> "$CALLS"; echo >> "$CALLS"
        cat "$JOBS"
        EOF
        chmod +x $out/bin/*
      '';

      judge = pkgs.writeText "enormous-tests-judge.py" ''
        import json, os, sys

        work, exit_first, exit_second = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
        columns = ${builtins.toJSON columns}
        records = [json.loads(line) for line in open(f"{work}/record.jsonl")]
        calls = open(f"{work}/calls").read().splitlines()
        failed = []

        def clause(name, ok, detail=""):
            if not ok:
                failed.append(name)
                print(f"FAIL {name}: {detail}")

        first, second = records[:6], records[6:]
        clause("order", [r["test"] for r in first] == ["big-pass", "big-present", "t-evalerror", "t-fail", "t-substituted", "t-timeout"], [r["test"] for r in first])
        clause("columns", all(list(r) == columns for r in records), [list(r) for r in records])
        by = {r["test"]: r for r in first}
        want = {
            "big-pass": ("passed", 1690500, "enormous", 3600),
            "big-present": ("present", None, "enormous", 3600),
            "t-evalerror": ("failed", None, "medium", 300),
            "t-fail": ("failed", None, "medium", 300),
            "t-substituted": ("present", None, "small", 60),
            "t-timeout": ("timed_out", 60000, "small", 60),
        }
        for test, (outcome, script, klass, limit) in want.items():
            r = by.get(test, {})
            clause(test, (r.get("outcome"), r.get("script_ms"), r.get("class"), r.get("limit_s")) == (outcome, script, klass, limit), r)
        clause("unbuilt", by.get("big-present", {}).get("build_ms") is None and by.get("t-evalerror", {}).get("drv_path") is None, by)
        clause("fields", all(r["host"] == "fixture-host" and r["revision"] == "fixture-rev" for r in records), records)
        builds = sorted(c.split("/fixture/")[1].split(".drv")[0] for c in calls if c.startswith("nix build "))
        # big-pass is built again by the second revision's run.
        clause("builds", builds == ["big-pass", "big-pass", "t-fail", "t-substituted", "t-timeout"], builds)
        clause("builders", all("--builders \'\'" in c and "--print-build-logs" in c and ".drv" in c and "^" in c for c in calls if c.startswith("nix build ")), calls)
        evals = [c for c in calls if c.startswith("nix-eval-jobs ")]
        clause("evaluation", len(evals) == 2 and all("--flake path:" in c and "vmTests.x86_64-linux" in c and "--gc-roots-dir" in c for c in evals), evals)
        roots = sorted(os.listdir(f"{work}/roots"))
        clause("roots", roots == ["big-pass", "big-present"] and os.readlink(f"{work}/roots/big-pass") == "/fixture/out/big-pass", roots)
        clause("exit", exit_first == 1 and exit_second == 0, (exit_first, exit_second))
        clause("second", [(r["test"], r["outcome"]) for r in second] == [("big-pass", "passed"), ("big-present", "present")], second)
        print(json.dumps(failed))
      '';

      # run SCRIPT LABEL: both revisions against the stubs, then the judge;
      # prints the judge's failing clauses as the last line.
      runAndJudge = ''
        run() {
          local script=$1 work=$2
          mkdir -p "$work/roots"
          ln -s /fixture/out/gone-test "$work/roots/gone-test"
          export CALLS=$work/calls FIXTURE=${fixture} ENORMOUS_TESTS_FLAKE=github:fixture/flake/main
          export ENORMOUS_TESTS_RECORD=$work/record.jsonl ENORMOUS_TESTS_ROOTS=$work/roots TMPDIR=$work
          export PATH=${stubs}/bin:$PATH
          JOBS=${fixture}/jobs.jsonl "$script" > "$work/first.out" 2>&1 && first=0 || first=$?
          JOBS=${fixture}/second/jobs.jsonl "$script" > "$work/second.out" 2>&1 && second=0 || second=$?
          python3 ${judge} "$work" "$first" "$second" | tee "$work/judge.out" | tail -n 1
        }
      '';
    in
    {
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # a pure stub run of a shell script, well under a second of work
        enormous-tests = {
          class = "small";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        enormous-tests =
          pkgs.runCommand "enormous-tests"
            {
              nativeBuildInputs = [ pkgs.python3 ];
              meta.description = "enormous-tests.service's run logic against a stub nix and nix-eval-jobs, with its mutants";
            }
            ''
              ${runAndJudge}
              verdict=$(run ${lib.getExe unmutated} "$TMPDIR/unmutated")
              if [ "$verdict" != "[]" ]; then
                cat "$TMPDIR/unmutated/first.out" "$TMPDIR/unmutated/judge.out"
                echo "enormous-tests: the unmutated script fails $verdict" >&2
                exit 1
              fi
              echo "ok: unmutated: $(wc -l < "$TMPDIR/unmutated/record.jsonl") records, every clause holds"
              ${lib.concatStrings (
                lib.mapAttrsToList (name: m: ''
                  verdict=$(run ${lib.getExe (variant name m)} "$TMPDIR/${name}")
                  case "$verdict" in
                    *'"${m.clause}"'*) echo "mutant ${name} rejected: fails $verdict" ;;
                    *) cat "$TMPDIR/${name}/judge.out"; echo "enormous-tests: mutant ${name} did not fail ${m.clause}: $verdict" >&2; exit 1 ;;
                  esac
                '') mutants
              )}
              touch $out
            '';
      };
    };
}

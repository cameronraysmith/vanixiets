# shellcheck shell=bash
# Body of enormous-tests.service (declare-test-size-classes design D11). The
# Nix side (modules/nixos/enormous-tests.nix) prepends `host`; the unit sets
# ENORMOUS_TESTS_FLAKE, ENORMOUS_TESTS_RECORD and ENORMOUS_TESTS_ROOTS and puts
# `nix` and the host's lock-wrapped `nix-eval-jobs` on PATH, which
# checks.x86_64-linux.enormous-tests replaces with stubs.
#
# One run: fetch the flake reference once into the store; read that
# revision's lib.runtimeTestSizes; evaluate every vmTests.x86_64-linux test
# once, under the host evaluation lock; then, one test at a time, the
# enormous ones first, record one result per test:
#   present    the test's output was already in the store, or the build
#              succeeded without the driver's `test script finished in` line
#              in this build's own log (substituted, or built meanwhile by
#              another run): it passes at this derivation, and nothing ran;
#   passed     the build ran the script to its end: its script time;
#   timed_out  the driver's timer fired: the class limit as its script time,
#              since the script ran at least that long;
#   failed     any other failed build, or a test that did not evaluate.
# Exit 1 when a test failed, timed out or did not evaluate; exit 2 when the
# reference, its sizes or its tests cannot be read.

flake=${ENORMOUS_TESTS_FLAKE:?ENORMOUS_TESTS_FLAKE is not set}
record=${ENORMOUS_TESTS_RECORD:?ENORMOUS_TESTS_RECORD is not set}
roots=${ENORMOUS_TESTS_ROOTS:?ENORMOUS_TESTS_ROOTS is not set}

say() {
  printf 'enormous-tests: %s\n' "$*"
}
unreadable() {
  say "cannot read $*" >&2
  exit 2
}

work=$(mktemp -d "${RUNTIME_DIRECTORY:-${TMPDIR:-/tmp}}/run.XXXXXX")
trap 'rm -rf "$work"' EXIT

# The source and the .drv files stay rooted under $work for the run only.
nix flake prefetch --json --out-link "$work/source" "$flake" >"$work/prefetch.json" || unreadable "$flake"
src=$(readlink -f "$work/source")
revision=$(jq -r '.locked.rev // .locked.narHash // ""' "$work/prefetch.json")
nix eval --json "path:$src#lib.runtimeTestSizes" >"$work/sizes.json" || unreadable "lib.runtimeTestSizes of $flake at $revision"
nix-eval-jobs --flake "path:$src#vmTests.x86_64-linux" --gc-roots-dir "$work/drv-roots" >"$work/jobs.jsonl" ||
  unreadable "vmTests.x86_64-linux of $flake at $revision"
say "$flake is $revision"

# The tests that evaluated or failed to, the enormous ones first, each set in
# name order.
mapfile -t names < <(
  jq -r -s --slurpfile sizes "$work/sizes.json" '
    map(.attr) | unique
    | map(select($sizes[0][.].class == "enormous")) + map(select($sizes[0][.].class != "enormous"))
    | .[]' "$work/jobs.jsonl"
)

if [ ! -e "$record" ]; then
  install -m 0644 /dev/null "$record"
fi
mkdir -p "$roots"

# emit OUTCOME SCRIPT_MS BUILD_MS DRV: the test's one record, the columns of
# devloop.runtime_test_result; a null or empty argument is a null column.
emit() {
  jq -n -c \
    --arg host "$host" \
    --arg test "$name" \
    --arg revision "$revision" \
    --arg drv "$4" \
    --arg class "$class" \
    --argjson limit "${limit:-null}" \
    --arg outcome "$1" \
    --argjson script "$2" \
    --argjson build "$3" \
    --arg finished "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" \
    '{host: $host, test: $test, revision: $revision,
      drv_path: (if $drv == "" then null else $drv end),
      class: (if $class == "" then null else $class end), limit_s: $limit,
      outcome: $outcome, script_ms: $script, build_ms: $build, finished_at: $finished}' >>"$record"
  say "$name: $1"
}
# keep_root: one direct GC root per test on the output it last saw pass, so
# the daily collection does not delete it and rerun an unchanged test.
keep_root() {
  ln -sfn "$out" "$roots/$name"
}

failed=0
for name in "${names[@]}"; do
  job=$(jq -c --arg n "$name" 'select(.attr == $n)' "$work/jobs.jsonl" | head -n 1)
  class=$(jq -r --arg n "$name" '.[$n].class // ""' "$work/sizes.json")
  limit=$(jq -r --arg n "$name" '.[$n].limit // ""' "$work/sizes.json")
  drv=$(jq -r '.drvPath // ""' <<<"$job")
  out=$(jq -r '.outputs.out // ""' <<<"$job")
  if [ -z "$drv" ] || [ -z "$out" ]; then
    say "$name did not evaluate: $(jq -r '.error // "no derivation"' <<<"$job" | head -c 4000)"
    emit failed null null ""
    failed=1
    continue
  fi
  if nix path-info "$out" >/dev/null 2>&1; then
    keep_root
    emit present null null "$drv"
    continue
  fi

  derivation=$(jq -r '.name' <<<"$job")
  say "$name ($class, limit ${limit:-unknown} s): building $drv"
  start=$(date +%s%3N)
  status=0
  nix build --no-link --builders '' --print-build-logs "$drv^*" >"$work/build.log" 2>&1 || status=$?
  build_ms=$(($(date +%s%3N) - start))
  # The journal gets the test's own lines and nix's, not every dependency's
  # build log.
  awk -v p="$derivation> " 'index($0, p) == 1 || $0 !~ /^[^ ]+> /' "$work/build.log"
  # Only the test derivation's own lines count; the driver prints the line
  # after the script ran to its end.
  grep -F -- "$derivation> " "$work/build.log" >"$work/own.log" || true
  seconds=$(grep -oE 'test script finished in [0-9]+(\.[0-9]+)?s$' "$work/own.log" | tail -n 1 | grep -oE '[0-9]+(\.[0-9]+)?' || true)
  script_ms=null
  if [ -n "$seconds" ]; then
    script_ms=$(awk -v s="$seconds" 'BEGIN { printf "%d", s * 1000 + 0.5 }')
  fi

  if [ "$status" -eq 0 ]; then
    keep_root
    if [ "$script_ms" != null ]; then
      emit passed "$script_ms" "$build_ms" "$drv"
    else
      say "$name: built without its script running here (substituted, or built meanwhile by another run)"
      emit present null "$build_ms" "$drv"
    fi
  elif grep -qF 'timeout reached; test terminating' "$work/own.log"; then
    emit timed_out "$((${limit:-0} * 1000))" "$build_ms" "$drv"
    failed=1
  else
    emit failed "$script_ms" "$build_ms" "$drv"
    failed=1
  fi
done

# The roots of tests this revision no longer declares.
for link in "$roots"/*; do
  [ -L "$link" ] || continue
  keep=0
  for name in "${names[@]}"; do
    if [ "$(basename "$link")" = "$name" ]; then
      keep=1
    fi
  done
  if [ "$keep" -eq 0 ]; then
    rm -f "$link"
  fi
done

exit "$failed"

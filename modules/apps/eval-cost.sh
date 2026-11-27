#!/usr/bin/env bash
# shellcheck shell=bash

usage() {
  cat <<'EOF'
Usage: eval-cost --attr ATTR --before REV --after REV [--runs N]
                 [--mode drv|keys] [--label LABEL]

Measures the evaluation cost of ATTR at two commits, read through
git+file://<repo>?rev=<commit>, with the fleet's stock Nix ($NIX_STOCK).
Each commit is first evaluated once untimed (the warm-up copies the flake to
the store); then N rounds (default 2) of before, after, each a fresh process
with NIX_SHOW_STATS=1, its own NIX_SHOW_STATS_PATH and the evaluation cache
off. Mode drv (default) evaluates ATTR.drvPath; mode keys evaluates ATTR with
--apply builtins.attrNames. Every run records wall time, cpuTime,
gc.totalBytes, nrThunks and envs.number; the header records the evaluator's
resolved path and version, the host, its memory, its sandbox setting and the
other evaluations running when the measurement started. Writes
logs/eval-cost-<LABEL>-<UTC>.{log,jsonl} (LABEL defaults to ATTR made
file-safe) and prints every run. A claim about cost compares the interleaved
runs: thunks and allocation separate on one round, CPU and wall need both.
Pass a jj change by commit id: $(jj log -r <rev> --no-graph -T commit_id).
EOF
}

die() {
  echo "eval-cost: $*" >&2
  exit 2
}

attr=""
before=""
after=""
runs=2
mode=drv
label=""
while [ $# -gt 0 ]; do
  case $1 in
    --attr) attr=$2; shift 2 ;;
    --before) before=$2; shift 2 ;;
    --after) after=$2; shift 2 ;;
    --runs) runs=$2; shift 2 ;;
    --mode) mode=$2; shift 2 ;;
    --label) label=$2; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[ -n "$attr" ] && [ -n "$before" ] && [ -n "$after" ] || { usage >&2; exit 2; }
case $mode in drv | keys) ;; *) die "--mode must be drv or keys" ;; esac
case $runs in '' | *[!0-9]* | 0) die "--runs must be a positive integer" ;; esac
[ -n "$label" ] || label=$(printf '%s' "$attr" | tr -c 'A-Za-z0-9_-' '-')

repo=$(git rev-parse --show-toplevel) || die "not in a git repository"
before=$(git -C "$repo" rev-parse --verify --quiet "$before^{commit}") || die "--before does not name a commit"
after=$(git -C "$repo" rev-parse --verify --quiet "$after^{commit}") || die "--after does not name a commit"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$repo/logs"
base=$repo/logs/eval-cost-$label-$(date -u +%Y%m%dT%H%M%SZ)
log=$base.log
jsonl=$base.jsonl
: >"$jsonl"

case $(uname -s) in
  Darwin) memory="$(($(sysctl -n hw.memsize) / 1048576)) MiB" ;;
  *) memory=$(awk '/^MemTotal:/ { printf "%d MiB", $2 / 1024 }' /proc/meminfo) ;;
esac
others=$(ps -A -o pid= -o command= | awk -v self=$$ '$1 != self && /nix-eval-jobs|nix eval|nix-instantiate|nix flake check|iets/ && !/awk/' || true)
{
  echo "attr: $attr"
  echo "mode: $mode; runs: $runs"
  echo "before: $before"
  echo "after: $after"
  echo "nix: $(readlink -f "$NIX_STOCK") ($("$NIX_STOCK" --version 2>&1 | head -1))"
  echo "sandbox: $("$NIX_STOCK" config show sandbox 2>/dev/null || echo unknown)"
  echo "host: $(uname -n) ($(uname -sm)); memory: $memory"
  echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ -n "$others" ]; then
    echo "other evaluations running at start:"
    printf '%s\n' "$others" | sed 's/^/  /'
  else
    echo "other evaluations running at start: none"
  fi
} | tee "$log"

# evaluate COMMIT: one evaluation of ATTR at COMMIT, output discarded.
evaluate() {
  local ref="git+file://$repo?rev=$1"
  case $mode in
    drv) "$NIX_STOCK" eval --option eval-cache false --raw "$ref#$attr.drvPath" ;;
    keys) "$NIX_STOCK" eval --option eval-cache false --json "$ref#$attr" --apply builtins.attrNames ;;
  esac >/dev/null 2>>"$tmp/err"
}

for c in "$before" "$after"; do
  "$NIX_STOCK" flake metadata "git+file://$repo?rev=$c" >/dev/null 2>>"$tmp/err" ||
    { tail -5 "$tmp/err" >&2; die "flake metadata failed at $c"; }
  evaluate "$c" || { tail -5 "$tmp/err" >&2; die "warm-up evaluation failed at $c"; }
done

printf '%-4s %-6s %-12s %9s %9s %14s %12s %12s\n' run side commit "wall s" "cpu s" "gc bytes" thunks envs | tee -a "$log"
for r in $(seq 1 "$runs"); do
  for side in before after; do
    case $side in
      before) c=$before ;;
      after) c=$after ;;
    esac
    stats=$tmp/$r-$side.json
    start=${EPOCHREALTIME/./}
    NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=$stats evaluate "$c" ||
      { tail -5 "$tmp/err" >&2; die "run $r at $side failed"; }
    wall=$(((${EPOCHREALTIME/./} - start) / 1000))
    jq -c --argjson run "$r" --arg side "$side" --arg commit "$c" --argjson wallMs "$wall" \
      '{run:$run, side:$side, commit:$commit, wall:($wallMs / 1000), cpuTime, totalBytes:.gc.totalBytes, nrThunks, envs:.envs.number}' \
      "$stats" >>"$jsonl"
    tail -1 "$jsonl" | jq -r '[.run, .side, .commit[0:12], .wall, .cpuTime, .totalBytes, .nrThunks, .envs] | @tsv' |
      awk -F'\t' '{ printf "%-4s %-6s %-12s %9.2f %9.2f %14s %12s %12s\n", $1, $2, $3, $4, $5, $6, $7, $8 }' | tee -a "$log"
  done
done
echo "written: $log $jsonl" | tee -a "$log"

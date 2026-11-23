#!/usr/bin/env bash
# shellcheck shell=bash

usage() {
  cat <<'EOF'
Usage: nix-eval-jobs-identity [--rev REV] [--workers N] [--max-memory-size MIB] [SYSTEM...]

Evaluates checks.<SYSTEM> of commit REV (default: the git HEAD of the current
repository) with this host's two evaluators, nix-eval-jobs-stock and then
nix-eval-jobs (iets), as found on PATH, one after the other,
with the same arguments (--force-recurse, import-from-derivation disallowed,
no evaluation cache), and compares them attribute by attribute: the same
attribute names, and for each the same drvPath, system and outputs, and an
error in both or in neither (the messages differ between the evaluators).
SYSTEMs default to x86_64-linux and aarch64-darwin, the systems nixbot
evaluates. --workers (default 2) and --max-memory-size (default 4096) apply
to both, within the host's bound for iets; iets ignores the memory limit on
macOS. Exits 1 on any difference, and 2 on a host whose nix-eval-jobs is not
iets (no nix-eval-jobs-stock on PATH).
EOF
}

rev=""
workers=2
mem=4096
systems=()
while [ $# -gt 0 ]; do
  case $1 in
    --rev) rev=$2; shift 2 ;;
    --workers) workers=$2; shift 2 ;;
    --max-memory-size) mem=$2; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) systems+=("$1"); shift ;;
  esac
done
[ ${#systems[@]} -gt 0 ] || systems=(x86_64-linux aarch64-darwin)
if ! stock_bin=$(command -v nix-eval-jobs-stock) || ! iets_bin=$(command -v nix-eval-jobs); then
  echo "nix-eval-jobs-identity: this host evaluates with stock nix-eval-jobs only (no nix-eval-jobs-stock on PATH), so there is no iets to compare" >&2
  exit 2
fi
repo=$(git rev-parse --show-toplevel)
[ -n "$rev" ] || rev=$(git -C "$repo" rev-parse HEAD)
rev=$(git -C "$repo" rev-parse --verify "$rev^{commit}")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# One line per attribute, sorted, holding only what must agree.
project() {
  jq -c -S '{attr, drvPath, system, outputs, error: has("error")}' "$1" | sort
}

failed=0
for sys in "${systems[@]}"; do
  ref="git+file://$repo?rev=$rev#checks.$sys"
  for evaluator in stock iets; do
    case $evaluator in
      stock) bin=$stock_bin ;;
      iets) bin=$iets_bin ;;
    esac
    start=${EPOCHREALTIME/./}
    status=0
    "$bin" --flake "$ref" --force-recurse \
      --workers "$workers" --max-memory-size "$mem" \
      --gc-roots-dir "$tmp/gcroots-$evaluator" \
      --option allow-import-from-derivation false \
      --option eval-cache false \
      >"$tmp/$evaluator.jsonl" 2>"$tmp/$evaluator.err" || status=$?
    elapsed=$(((${EPOCHREALTIME/./} - start) / 100000))
    case $evaluator in
      stock) time_stock="$((elapsed / 10)).$((elapsed % 10))" ;;
      iets) time_iets="$((elapsed / 10)).$((elapsed % 10))" ;;
    esac
    if [ "$status" -ne 0 ]; then
      echo "checks.$sys: $evaluator exited $status" >&2
      tail -5 "$tmp/$evaluator.err" >&2
      failed=1
      continue 2
    fi
    project "$tmp/$evaluator.jsonl" >"$tmp/$evaluator.projected"
  done
  attrs=$(wc -l <"$tmp/stock.projected" | tr -d ' ')
  errors=$(grep -c '"error":true' "$tmp/stock.projected" || true)
  if diff "$tmp/stock.projected" "$tmp/iets.projected" >"$tmp/diff"; then
    echo "checks.$sys at ${rev:0:12}: $attrs attributes identical ($errors failing in both); stock ${time_stock}s, iets ${time_iets}s"
  else
    echo "checks.$sys at ${rev:0:12}: stock and iets differ (< stock, > iets); stock ${time_stock}s, iets ${time_iets}s" >&2
    head -20 "$tmp/diff" >&2
    failed=1
  fi
done
exit "$failed"

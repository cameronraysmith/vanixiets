#!/usr/bin/env bash
# shellcheck shell=bash

usage() {
  cat <<'EOF'
Usage: nix-eval-jobs-identity [--rev REV] [--evaluators commit|path] [--workers N] [--max-memory-size MIB] [SYSTEM...]

Evaluates checks.<SYSTEM> of commit REV (default: the git HEAD of the current
repository) with this host's two evaluators, nix-eval-jobs-stock and then
nix-eval-jobs (iets), one after the other, with the same arguments
(--force-recurse, import-from-derivation disallowed, no evaluation cache),
and compares them attribute by attribute: the same attribute names, and for
each the same drvPath, system and outputs, and an error in both or in
neither (the messages differ between the evaluators).

--evaluators commit (the default) builds the two evaluators this host's
configuration has at REV, with stock Nix: on darwin
darwinConfigurations.<host>.config.vanixiets.nixEvalJobs.{package,stockPackage},
on NixOS nixosConfigurations.<host>.config.services.nixEvalLock.{package,stockPackage},
which are lock-wrapped and take the host's evaluation lock like the deployed
names. <host> is this machine's host name. This compares stock with the iets
REV's flake.lock pins, as an iets input bump needs.
--evaluators path takes nix-eval-jobs and nix-eval-jobs-stock from PATH,
the evaluators the host has deployed.

The evaluator store paths and the iets revision REV's flake.lock pins are
printed first. SYSTEMs default to x86_64-linux and aarch64-darwin, the
systems nixbot evaluates. --workers (default 2) and --max-memory-size
(default 4096) apply to both, within the host's bound for iets; iets ignores
the memory limit on macOS. Exits 1 on any difference, and 2 on a host whose
nix-eval-jobs is not iets (no nix-eval-jobs-stock).
EOF
}

rev=""
evaluators=commit
workers=2
mem=4096
systems=()
while [ $# -gt 0 ]; do
  case $1 in
    --rev) rev=$2; shift 2 ;;
    --evaluators) evaluators=$2; shift 2 ;;
    --workers) workers=$2; shift 2 ;;
    --max-memory-size) mem=$2; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) systems+=("$1"); shift ;;
  esac
done
[ ${#systems[@]} -gt 0 ] || systems=(x86_64-linux aarch64-darwin)
repo=$(git rev-parse --show-toplevel)
[ -n "$rev" ] || rev=$(git -C "$repo" rev-parse HEAD)
rev=$(git -C "$repo" rev-parse --verify "$rev^{commit}")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

no_iets() {
  echo "nix-eval-jobs-identity: $1 has no nix-eval-jobs-stock, so its nix-eval-jobs is stock and there is no iets to compare" >&2
  exit 2
}

case $evaluators in
  commit)
    host=$(uname -n)
    host=${host%%.*}
    case $(uname -s) in
      Darwin) attr="darwinConfigurations.$host.config.vanixiets.nixEvalJobs" ;;
      Linux) attr="nixosConfigurations.$host.config.services.nixEvalLock" ;;
      *) echo "nix-eval-jobs-identity: no host configuration class for $(uname -s)" >&2; exit 2 ;;
    esac
    stock_only=$("$NIX_STOCK" eval "git+file://$repo?rev=$rev#$attr.stockPackage" --apply 'p: p == null') || exit 2
    [ "$stock_only" = false ] || no_iets "$attr at ${rev:0:12}"
    for p in package stockPackage; do
      "$NIX_STOCK" build --out-link "$tmp/$p" "git+file://$repo?rev=$rev#$attr.$p" || exit 2
    done
    iets_bin=$tmp/package/bin/nix-eval-jobs
    stock_bin=$tmp/stockPackage/bin/nix-eval-jobs-stock
    echo "evaluators: $attr at ${rev:0:12}"
    ;;
  path)
    if ! stock_bin=$(command -v nix-eval-jobs-stock) || ! iets_bin=$(command -v nix-eval-jobs); then
      no_iets "this host's PATH"
    fi
    echo "evaluators: PATH"
    ;;
  *) usage >&2; exit 2 ;;
esac
for bin in "$iets_bin" "$stock_bin"; do
  echo "  $bin -> $(readlink -f "$bin")"
done
store_path() { readlink -f "$1" | cut -d/ -f1-4; }
echo "  iets in nix-eval-jobs: $("$NIX_STOCK" path-info -r "$(store_path "$iets_bin")" | grep -E -- '^/nix/store/[0-9a-z]{32}-iets-[0-9]' | paste -sd ' ' -)"
echo "  iets locked at ${rev:0:12}: $(git -C "$repo" show "$rev:flake.lock" | jq -r '.nodes[.nodes[.root].inputs.iets].locked.rev')"

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

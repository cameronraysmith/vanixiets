#!/usr/bin/env bash
# shellcheck shell=bash

usage() {
  cat <<'EOF'
Usage: drv-diff --before REV --after REV [--allow FILE] [--systems "S..."]
                [--vm-systems "S..."] [--workers N] [--max-memory-size MIB]
       drv-diff --reuse DIR [--allow FILE]

The cross-revision drvPath oracle. At each of two commits, read through
git+file://<repo>?rev=<commit> so that only committed trees are seen, it
dumps, without building, a map from attribute name to drvPath for:
  nixos     nixosConfigurations.<h>.config.system.build.toplevel
  darwin    darwinConfigurations.<h>.config.system.build.toplevel
  home      homeConfigurations."<name>".activationPackage
  checks.S  checks.<S> for each S in --systems
            (default "x86_64-linux aarch64-darwin")
  vmTests.S vmTests.<S> for each S in --vm-systems
            (default "x86_64-linux aarch64-linux")
and compares them. Configurations and homes are evaluated one attribute per
process with the fleet's stock Nix ($NIX_STOCK); checks and vmTests with
nix-eval-jobs-stock where it is on PATH, else nix-eval-jobs, with
--workers (default 2) and --max-memory-size (default 4096),
import-from-derivation disallowed and the evaluation cache off.

Allow-list (--allow FILE, and the base allow-list applied on every run):
one entry per line, `<set>.<attr> <expect>  # reason`, where <set> is one
of nixos, darwin, home, checks.<S>, vmTests.<S>, and <expect> is one of
  changed     the drvPath differs (or evaluates at one commit only)
  added       the attribute exists at the after commit only
  removed     the attribute exists at the before commit only
  may-change  any difference, or none
Each entry names one exact attribute; blank lines and `#` lines are ignored.
Each may-change entry of a change's own allow-list is resolved to
`changed`, or removed, before that change archives. The base allow-list
($DRV_DIFF_BASE_ALLOW) names the checks whose derivation takes the whole
flake source; its entries stay may-change permanently, and a change's
allow-list must not repeat them.

An attribute failing to evaluate at both commits is listed and does not
fail the run; failing at one commit is a difference.

Exit status: 0 every difference is allowed and every changed/added/removed
entry occurred; 1 otherwise; 2 on a usage error (a revision that is not a
commit, a malformed entry, an entry for an attribute absent at both commits,
an entry repeating a base entry) or a dump that could not be produced.
Evidence: logs/drv-diff-<before12>-<after12>-<UTC>/{header,<set>.{before,after}.jsonl,report}.
Pass a jj change by commit id: $(jj log -r <rev> --no-graph -T commit_id).

Re-judgement (--reuse DIR): read the revisions, systems and dumps of an
earlier run from DIR/header and DIR/<set>.{before,after}.jsonl, evaluate
nothing, and judge them against the current base allow-list and --allow.
The report goes to DIR/report.<UTC> and its conditions to DIR/header.<UTC>
(<UTC>-2, -3, ... when that name is taken); the original header and report
are never written. Exit status as above;
2 also when DIR has no header naming both revisions or lacks a dump of a
set the header names. --before, --after, --systems, --vm-systems,
--workers and --max-memory-size do not combine with --reuse.
EOF
}

die() {
  echo "drv-diff: $*" >&2
  exit 2
}

before=""
after=""
allow=""
reuse=""
systems="x86_64-linux aarch64-darwin"
vm_systems="x86_64-linux aarch64-linux"
workers=2
mem=4096
eval_opts=""
while [ $# -gt 0 ]; do
  case $1 in
    --before) before=$2; shift 2 ;;
    --after) after=$2; shift 2 ;;
    --allow) allow=$2; shift 2 ;;
    --reuse) reuse=$2; shift 2 ;;
    --systems) systems=$2; eval_opts+=" $1"; shift 2 ;;
    --vm-systems) vm_systems=$2; eval_opts+=" $1"; shift 2 ;;
    --workers) workers=$2; eval_opts+=" $1"; shift 2 ;;
    --max-memory-size) mem=$2; eval_opts+=" $1"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[ -n "${DRV_DIFF_BASE_ALLOW:-}" ] && [ -r "$DRV_DIFF_BASE_ALLOW" ] || die "no readable base allow-list (DRV_DIFF_BASE_ALLOW)"
[ -z "$allow" ] || [ -r "$allow" ] || die "cannot read allow-list $allow"

if [ -n "$reuse" ]; then
  [ -z "$before$after$eval_opts" ] || die "--reuse takes the revisions and sets from DIR/header; it does not combine with --before, --after$eval_opts"
  [ -r "$reuse/header" ] || die "--reuse $reuse: no evidence header $reuse/header"
  # header_field NAME: the value of the first `NAME: ` line of DIR/header;
  # a missing line is a usage error.
  header_field() {
    grep -q "^$1: " "$reuse/header" || die "--reuse $reuse: header has no $1 line"
    sed -n "s/^$1: //p" "$reuse/header" | head -1
  }
  before=$(header_field before) || exit 2
  after=$(header_field after) || exit 2
  systems=$(header_field systems) || exit 2
  vm_systems=$(header_field vm-systems) || exit 2
  [ -n "$before" ] && [ -n "$after" ] || die "--reuse $reuse: header names no before or after revision"
else
  [ -n "$before" ] && [ -n "$after" ] || { usage >&2; exit 2; }
  repo=$(git rev-parse --show-toplevel) || die "not in a git repository"
  before=$(git -C "$repo" rev-parse --verify --quiet "$before^{commit}") || die "--before does not name a commit"
  after=$(git -C "$repo" rev-parse --verify --quiet "$after^{commit}") || die "--after does not name a commit"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# parse_allow ORIGIN FILE: one JSON object per entry on stdout; a malformed
# line is a usage error naming it.
parse_allow() {
  local origin=$1 file=$2 n=0 line key expect extra set rest attr
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line=${line%%#*}
    read -r key expect extra <<<"$line" || true
    [ -n "${key:-}" ] || continue
    [ -z "${extra:-}" ] || die "$file:$n: more than one expectation: $line"
    case ${expect:-} in
      changed | added | removed | may-change) ;;
      *) die "$file:$n: expectation must be changed, added, removed or may-change: $line" ;;
    esac
    case $key in
      nixos.?* | darwin.?* | home.?*)
        set=${key%%.*}
        attr=${key#*.}
        ;;
      checks.?*.?* | vmTests.?*.?*)
        rest=${key#*.}
        set=${key%%.*}.${rest%%.*}
        attr=${rest#*.}
        ;;
      *) die "$file:$n: set must be nixos, darwin, home, checks.<system> or vmTests.<system>: $line" ;;
    esac
    jq -nc --arg o "$origin" --arg f "$file:$n" --arg k "$key" --arg s "$set" --arg a "$attr" --arg e "$expect" \
      '{origin:$o, where:$f, key:$k, set:$s, attr:$a, expect:$e}'
  done <"$file"
}

parse_allow base "$DRV_DIFF_BASE_ALLOW" >"$tmp/allow.jsonl"
[ -z "$allow" ] || parse_allow change "$allow" >>"$tmp/allow.jsonl"
dups=$(jq -rs 'group_by(.key)[] | select(length > 1) | map(.where) | join(", ")' "$tmp/allow.jsonl")
[ -z "$dups" ] || die "an attribute is named more than once (a change's allow-list must not repeat a base entry): $dups"

sets=(nixos darwin home)
for s in $systems; do sets+=("checks.$s"); done
for s in $vm_systems; do sets+=("vmTests.$s"); done

utc=$(date -u +%Y%m%dT%H%M%SZ)
seconds() { echo "$((${1} / 1000000)).$(((${1} / 100000) % 10))"; }
start_all=${EPOCHREALTIME/./}

if [ -n "$reuse" ]; then
  dir=$reuse
  for set in "${sets[@]}"; do
    for side in before after; do
      [ -r "$dir/$set.$side.jsonl" ] || die "--reuse $dir: no dump $set.$side.jsonl of a set its header names"
    done
  done
  stamp=$utc
  i=1
  while [ -e "$dir/report.$stamp" ] || [ -e "$dir/header.$stamp" ]; do
    i=$((i + 1))
    stamp=$utc-$i
  done
  header=$dir/header.$stamp
  report=$dir/report.$stamp
  {
    echo "re-judgement of: $dir (dumps as recorded in $dir/header)"
    echo "before: $before"
    echo "after: $after"
    echo "systems: $systems"
    echo "vm-systems: $vm_systems"
    echo "base allow-list: $DRV_DIFF_BASE_ALLOW"
    echo "allow-list: ${allow:-none}"
    echo "host: $(uname -n); started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$header"
  cat "$header"
else
  dir=$repo/logs/drv-diff-${before:0:12}-${after:0:12}-$utc
  header=$dir/header
  report=$dir/report
  mkdir -p "$dir"

  if jobs_bin=$(command -v nix-eval-jobs-stock); then :; else
    jobs_bin=$(command -v nix-eval-jobs) || die "no nix-eval-jobs on PATH"
  fi
  {
    echo "before: $before"
    echo "after: $after"
    echo "nix: $(readlink -f "$NIX_STOCK") ($("$NIX_STOCK" --version 2>&1 | head -1))"
    echo "nix-eval-jobs: $(readlink -f "$jobs_bin")"
    echo "systems: $systems"
    echo "vm-systems: $vm_systems"
    echo "workers: $workers; max-memory-size: $mem"
    echo "base allow-list: $DRV_DIFF_BASE_ALLOW"
    echo "allow-list: ${allow:-none}"
    echo "host: $(uname -n); started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$header"
  cat "$header"
fi

# dump_cfg SET OUTER SUFFIX SIDE COMMIT: one stock `nix eval` per attribute.
dump_cfg() {
  local set=$1 outer=$2 suffix=$3 side=$4 ref="git+file://$repo?rev=$5" out n d
  out=$dir/$set.$side.jsonl
  : >"$out"
  "$NIX_STOCK" eval --json --option eval-cache false "$ref#$outer" --apply builtins.attrNames \
    >"$tmp/names" 2>>"$dir/$set.$side.err" || die "$set at $side: could not list $outer (see $dir/$set.$side.err)"
  while read -r n; do
    if d=$("$NIX_STOCK" eval --raw --option eval-cache false "$ref#$outer.\"$n\".$suffix.drvPath" 2>>"$dir/$set.$side.err"); then
      jq -nc --arg a "$n" --arg d "$d" '{attr:$a, drvPath:$d, error:false}'
    else
      jq -nc --arg a "$n" '{attr:$a, drvPath:null, error:true}'
    fi
  done < <(jq -r '.[]' "$tmp/names") | sort >"$out"
}

# dump_jobs SET SIDE COMMIT [--force-recurse]: nix-eval-jobs over SET.
dump_jobs() {
  local set=$1 side=$2 ref="git+file://$repo?rev=$3#$1" status=0
  shift 3
  "$jobs_bin" --flake "$ref" "$@" \
    --workers "$workers" --max-memory-size "$mem" \
    --gc-roots-dir "$tmp/gcroots" \
    --option allow-import-from-derivation false \
    --option eval-cache false \
    >"$tmp/jobs.jsonl" 2>"$dir/$set.$side.err" || status=$?
  [ "$status" -eq 0 ] || die "$set at $side: $jobs_bin exited $status (see $dir/$set.$side.err)"
  jq -c -S '{attr, drvPath, error: has("error")}' "$tmp/jobs.jsonl" | sort >"$dir/$set.$side.jsonl"
}

[ -n "$reuse" ] || for side in before after; do
  case $side in
    before) commit=$before ;;
    after) commit=$after ;;
  esac
  for set in "${sets[@]}"; do
    t=${EPOCHREALTIME/./}
    case $set in
      nixos) dump_cfg nixos nixosConfigurations config.system.build.toplevel "$side" "$commit" ;;
      darwin) dump_cfg darwin darwinConfigurations config.system.build.toplevel "$side" "$commit" ;;
      home) dump_cfg home homeConfigurations activationPackage "$side" "$commit" ;;
      checks.*) dump_jobs "$set" "$side" "$commit" --force-recurse ;;
      vmTests.*) dump_jobs "$set" "$side" "$commit" ;;
    esac
    echo "dumped $set at $side ($(wc -l <"$dir/$set.$side.jsonl" | tr -d ' ') attributes) in $(seconds $((${EPOCHREALTIME/./} - t)))s" | tee -a "$header"
  done
done

# Comparison and decision, over every set's two dumps and the allow-list.
for set in "${sets[@]}"; do
  jq -c --arg s "$set" '{set:$s, side:"before"} + .' "$dir/$set.before.jsonl"
  jq -c --arg s "$set" '{set:$s, side:"after"} + .' "$dir/$set.after.jsonl"
done >"$tmp/dumps.jsonl"

status=0
jq -rn --argjson sets "$(printf '%s\n' "${sets[@]}" | jq -R . | jq -s .)" \
  --slurpfile dumps "$tmp/dumps.jsonl" --slurpfile allow "$tmp/allow.jsonl" \
  --arg before "${before:0:12}" --arg after "${after:0:12}" '
  def kind:
    if .before == null then "added"
    elif .after == null then "removed"
    elif .before.error and .after.error then "failing-at-both"
    elif .before.error or .after.error then "failing-at-one"
    elif .before.drvPath == .after.drvPath then "identical"
    else "changed" end;
  def matches($k):
    if .expect == "may-change" then true
    elif .expect == "changed" then ($k == "changed" or $k == "failing-at-one")
    else .expect == $k end;
  def show: if . == null then "absent" elif .error then "error" else .drvPath end;
  ($dumps | group_by(.set) | map({key: .[0].set, value:
      (group_by(.attr) | map({key: .[0].attr, value:
        (map({key: .side, value: .}) | from_entries)}) | from_entries)}) | from_entries) as $m
  | [ $sets[] as $s | ($m[$s] // {}) | to_entries[]
      | {set: $s, attr: .key, key: "\($s).\(.key)", before: .value.before, after: .value.after}
      | . + {kind: kind} ] as $rows
  | ($rows | map({key: .key, value: .}) | from_entries) as $byKey
  | ($allow | map({key: .key, value: .}) | from_entries) as $entries
  | [ $allow[] | select($byKey[.key] == null) ] as $absent
  | if ($absent | length) > 0 then
      ($absent[] | "drv-diff: \(.where): \(.key) exists at neither commit"), "STATUS 2"
    else
      [ $rows[] | select(.kind != "identical" and .kind != "failing-at-both")
        | . as $r | ($entries[$r.key]) as $e
        | . + {entry: $e, allowed: ($e != null and ($e | matches($r.kind)))} ] as $diffs
      | [ $allow[] | . as $e | ($byKey[$e.key].kind) as $k
          | select(($e | matches($k) | not) or $k == "identical" or $k == "failing-at-both")
          | . + {kind: $k, fails: (.expect != "may-change")} ] as $absentEntries
      | "drv-diff \($before) -> \($after)",
        ( $sets[] as $s | [ $rows[] | select(.set == $s) ] as $r
          | "\($s): \($r | length) attributes; " +
            ([ "identical", "changed", "added", "removed", "failing-at-one", "failing-at-both" ] as $ks
             | [ $ks[] as $k | "\([ $r[] | select(.kind == $k) ] | length) \($k)" ] | join(", ")) ),
        "differences:",
        ( $diffs[]
          | (if .allowed then (if .entry.origin == "base" then "  allowed by base" else "  declared" end)
             else "  UNDECLARED" end)
            + " \(.kind) \(.key)\(if .entry then " (\(.entry.expect), \(.entry.where))" else "" end)",
            "    before: \(.before | show)",
            "    after:  \(.after | show)" ),
        "failing at both commits:",
        ( $rows[] | select(.kind == "failing-at-both") | "  \(.key)" ),
        "entries that did not occur:",
        ( $absentEntries[]
          | "  \(if .fails then "NOT OCCURRING" else "not occurring" end) \(.key) \(.expect) (\(.kind), \(.where))" ),
        ( if ([ $diffs[] | select(.allowed | not) ] | length) > 0 or ([ $absentEntries[] | select(.fails) ] | length) > 0
          then "result: FAIL", "STATUS 1" else "result: PASS", "STATUS 0" end )
    end
' >"$tmp/report" || die "comparison failed"

status=$(sed -n 's/^STATUS //p' "$tmp/report")
grep -v '^STATUS ' "$tmp/report" >"$report"
echo "total $(seconds $((${EPOCHREALTIME/./} - start_all)))s" >>"$header"
if [ "$status" = 2 ]; then
  cat "$report" >&2
else
  cat "$report"
  echo "evidence: $dir (report $report); total $(seconds $((${EPOCHREALTIME/./} - start_all)))s"
fi
exit "$status"

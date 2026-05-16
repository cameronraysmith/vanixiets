#!/usr/bin/env bash
# Linearize N parallel chains from a jj diamond-workflow development join.
#
# Dissolves a development join with [wip] on @ and multi-parent [merge] on @-
# whose parents are the N chain tips named in --order. Produces a single
# linear chain on top of --base by sequentially rebasing each chain onto the
# previous chain's new tip. Preserves every chain bookmark at its post-rebase
# tip. Creates an aggregate bookmark at the final tip. Does NOT advance the
# base bookmark and does NOT push.
#
# Pre-conditions (each with a distinct exit code, see help text):
#  - cwd inside jj repo (10)
#  - --order non-empty (11)
#  - --aggregate-bookmark non-empty (12)
#  - aggregate bookmark does not exist (13)
#  - every chain bookmark in --order exists (14)
#  - base ref exists (15)
#  - @ is empty (16)
#  - @- has >= 2 parents, and every chain in --order is one of those parents
#    (strict-subset rule; see note in help text) (17)
#  - when --keep-remaining is given explicitly, every name in it is a parent
#    of @- and not in --order or --base (18)
#
# Exit codes:
#  0  success (or dry-run clean)
#  1  usage / unknown flag
#  2  dry-run produced conflicts
#  3  real-run produced conflicts (recovery instructions printed)
#  10..18  pre-condition violations (see above)
set -euo pipefail

show_help() {
  cat <<'HELP'
Linearize N parallel chains from a jj diamond-workflow development join

Usage:
  jj-linearize-join --order C1,C2,...,CN --aggregate-bookmark NAME [OPTIONS]
  jj-linearize-join test [SCENARIO]
  jj-linearize-join --help

Dissolves a development join (the multi-parent [merge] commit on @- with the
ephemeral [wip] commit on @) by sequentially rebasing each chain onto the
previous chain's new tip. The first chain in --order is rebased onto --base
(default "main"); each subsequent chain is rebased onto the previous chain's
post-rebase tip. Every chain bookmark is preserved at its new tip and an
aggregate bookmark is created at the final tip. The base bookmark is NOT
advanced; pushing is left to a separate step.

Required options:
  --order C1,C2,...,CN          Comma-separated chain bookmark names. C1 lands
                                first on --base, CN lands last.
  --aggregate-bookmark NAME     Bookmark name for the final linearized tip.

Optional options:
  --base REF                    Base ref to linearize onto (default: main)
  --dry-run                     Execute with --ignore-working-copy, inspect
                                conflicts(), then restore the operation log.
                                Exit 0 if clean, exit 2 if conflicts.
  --keep-remaining [CSV]        Submit a subset of chains while keeping the
                                rest as a smaller diamond above the linearized
                                aggregate. Two forms:
                                  --keep-remaining           (auto: derive from
                                    parents(@-) \ ({base} ∪ order))
                                  --keep-remaining c3,c4,... (explicit list)
                                After linearize, each remaining chain is
                                rebased onto the aggregate tip and a new
                                development join is reconstructed with parents
                                {aggregate, remaining...}. See diamond-workflow
                                skill, "Partial Phase 4" section.
  -h, --help                    Show this help message.

Subcommand:
  test [SCENARIO]               Run embedded self-tests. SCENARIO is one of:
                                  clean-dry, clean-real, conflict-dry,
                                  precond-violations, single-chain,
                                  subset-keep-remaining, subset-conflict
                                Omit SCENARIO to run all.

Pre-condition rule for --order vs parents(@-):
  --order must list a SUBSET of @-'s parents that excludes --base. The
  pre-condition requires that every name in --order is one of @-'s parents
  and that @- has at least two parents. Parents that are equal to --base
  (the degenerate "single-chain + main" diamond) are implicitly handled by
  the linearization itself, since rebasing chain-1 onto --base places it
  exactly where the diamond's base-parent already was. This permits the
  single-chain reduction where @- has parents {main, chain-1} and --order
  is "chain-1".

  When --keep-remaining is given, the script also reconstructs a smaller
  development join above the linearized aggregate, with parents being the
  aggregate bookmark plus each remaining-chain bookmark (post-rebase).

Exit codes:
  0    success (or dry-run clean)
  1    usage / unknown flag
  2    dry-run would produce conflicts
  3    real-run produced conflicts (recovery printed)
  10   not inside a jj repo
  11   --order missing or empty
  12   --aggregate-bookmark missing or empty
  13   aggregate bookmark already exists
  14   a chain bookmark in --order does not exist
  15   --base ref does not exist
  16   @ has working-copy changes (not empty)
  17   @- parent set does not satisfy the diamond shape
  18   remaining chain bookmark in --keep-remaining is not in
       parents(@-) \ ({base} ∪ order)

Examples:
  jj-linearize-join --order chain-a,chain-b,chain-c --aggregate-bookmark epic-foo
  jj-linearize-join --order c1,c2 --aggregate-bookmark agg --dry-run
  jj-linearize-join --order c1 --aggregate-bookmark agg --base main
  jj-linearize-join test
  jj-linearize-join test conflict-dry

Post-condition:
  After a successful real run, the chain bookmarks form a linear sequence on
  top of --base and the aggregate bookmark points at the final tip. The
  working copy @ is repositioned onto the aggregate bookmark (a fresh empty
  commit descending from it), and the state is ready for
  `jj git push --allow-new --bookmark ...` and forge PR creation.
HELP
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

# Default values
base="main"
order_csv=""
aggregate=""
dry_run=false
# `keep_remaining_mode` is "" when --keep-remaining is absent, "auto" when the
# bare flag is given (remaining list derived at precondition time), or
# "explicit" when a CSV value is supplied (parsed into `remaining_csv`).
keep_remaining_mode=""
remaining_csv=""
# `remaining` is populated by precondition_checks (auto-derived from
# parents(@-) \ ({base} ∪ order)) or from remaining_csv (explicit mode).
remaining=()
# `test` subcommand defers to run_tests after function definitions are parsed.
test_mode=false
test_scenario=""

if [[ "${1:-}" == "test" ]]; then
  test_mode=true
  shift
  test_scenario="${1:-}"
  # Skip flag parsing; jump straight to the bottom dispatch.
  set --
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    --order) order_csv="${2:-}"; shift 2 ;;
    --aggregate-bookmark) aggregate="${2:-}"; shift 2 ;;
    --base) base="${2:-}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --keep-remaining)
      # Optional-value flag: if the next argv starts with `-` or is absent,
      # treat as bare (auto-derive); otherwise consume the next argv as CSV.
      shift
      if [[ $# -eq 0 || "${1:0:1}" == "-" ]]; then
        keep_remaining_mode="auto"
      else
        keep_remaining_mode="explicit"
        remaining_csv="$1"
        shift
      fi
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      echo "Try 'jj-linearize-join --help' for more information." >&2
      exit 1
      ;;
    *)
      echo "Error: Unexpected argument: $1" >&2
      echo "Try 'jj-linearize-join --help' for more information." >&2
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# Run jj with --ignore-working-copy when in dry-run mode, normal otherwise.
jj_run() {
  if "${dry_run}"; then
    jj --ignore-working-copy "$@"
  else
    jj "$@"
  fi
}

# Probe whether a bookmark name exists. Returns 0 if found, 1 if not.
bookmark_exists() {
  local name="$1"
  local out
  out=$(jj --ignore-working-copy bookmark list --quiet "${name}" 2>/dev/null || true)
  if [[ -n "${out}" ]] && grep -q "^${name}:" <<<"${out}"; then
    return 0
  fi
  # Older/newer jj versions may emit slightly different formats; fall back to
  # checking for any line containing the bookmark name followed by colon or
  # whitespace.
  if [[ -n "${out}" ]] && grep -Eq "(^|[[:space:]])${name}([[:space:]:]|\$)" <<<"${out}"; then
    return 0
  fi
  return 1
}

# Resolve the short change-id at a revset (first match).
short_change_id() {
  local rev="$1"
  jj --ignore-working-copy log -r "${rev}" --no-graph -T 'change_id.short()' --limit 1 2>/dev/null
}

# Print parents-of-@- bookmark sets, one parent per line, bookmarks comma-joined.
parents_of_at_minus_bookmarks() {
  jj --ignore-working-copy log -r 'parents(@-)' --no-graph \
    -T 'bookmarks.join(",") ++ "\n"' 2>/dev/null
}

# Count parents of @-.
parents_of_at_minus_count() {
  jj --ignore-working-copy log -r 'parents(@-)' --no-graph -T 'change_id ++ "\n"' \
    2>/dev/null | sed '/^$/d' | wc -l | tr -d ' '
}

# Probe whether @ is empty (no working-copy changes).
working_copy_empty() {
  local out
  out=$(jj --ignore-working-copy log -r @ --no-graph -T 'empty' --limit 1 2>/dev/null || echo "")
  [[ "${out}" == "true" ]]
}

# Capture current operation id for op-log restore (dry-run safety).
current_op_id() {
  jj --ignore-working-copy op log --no-graph -T 'id.short()' --limit 1 2>/dev/null
}

# -----------------------------------------------------------------------------
# Pre-condition checks
# -----------------------------------------------------------------------------

precondition_checks() {
  # 10: inside a jj repo
  if ! jj --ignore-working-copy root >/dev/null 2>&1; then
    echo "Error (precondition 10): current directory is not inside a jj repository." >&2
    exit 10
  fi

  # 11: --order non-empty
  if [[ -z "${order_csv}" ]]; then
    echo "Error (precondition 11): --order is required and must be non-empty." >&2
    exit 11
  fi

  # 12: --aggregate-bookmark non-empty
  if [[ -z "${aggregate}" ]]; then
    echo "Error (precondition 12): --aggregate-bookmark is required and must be non-empty." >&2
    exit 12
  fi

  # Parse --order into an array (mutates the global `chains` for the rest of the script).
  IFS=',' read -r -a chains <<< "${order_csv}"
  if [[ ${#chains[@]} -eq 0 ]]; then
    echo "Error (precondition 11): --order parsed to zero chains." >&2
    exit 11
  fi

  # 13: aggregate bookmark must not already exist
  if bookmark_exists "${aggregate}"; then
    echo "Error (precondition 13): aggregate bookmark '${aggregate}' already exists." >&2
    exit 13
  fi

  # 14: every chain bookmark must exist
  local c
  for c in "${chains[@]}"; do
    if [[ -z "${c}" ]]; then
      echo "Error (precondition 14): --order contains an empty chain name." >&2
      exit 14
    fi
    if ! bookmark_exists "${c}"; then
      echo "Error (precondition 14): chain bookmark '${c}' does not exist." >&2
      exit 14
    fi
  done

  # 15: base ref exists
  if ! jj --ignore-working-copy log -r "${base}" --no-graph --limit 1 \
       -T 'change_id ++ "\n"' >/dev/null 2>&1; then
    echo "Error (precondition 15): base ref '${base}' does not resolve." >&2
    exit 15
  fi

  # 16: @ empty
  if ! working_copy_empty; then
    echo "Error (precondition 16): working copy (@) has uncommitted changes; commit or describe them first." >&2
    exit 16
  fi

  # 17: @- parent shape
  local parent_count
  parent_count=$(parents_of_at_minus_count)
  if [[ "${parent_count}" -lt 2 ]]; then
    echo "Error (precondition 17): @- has ${parent_count} parents; expected >= 2 for a development join." >&2
    exit 17
  fi

  # Build a set of parent-bookmark names (one bookmark string per parent, comma-joined per parent).
  # Then verify every chain in --order matches at least one parent.
  local parents_bookmarks
  parents_bookmarks=$(parents_of_at_minus_bookmarks)
  # Flatten: per-parent bookmark sets, comma-separated; split on commas and newlines.
  local flat
  flat=$(echo "${parents_bookmarks}" | tr ',' '\n' | sed '/^$/d')
  for c in "${chains[@]}"; do
    if ! grep -Fxq "${c}" <<<"${flat}"; then
      echo "Error (precondition 17): chain bookmark '${c}' is not among parents(@-)." >&2
      echo "  parents(@-) bookmarks were:" >&2
      printf '    %s\n' "${parents_bookmarks}" >&2
      exit 17
    fi
  done

  # 18: --keep-remaining validation and (auto) derivation. `remaining` is the
  # set of parent bookmarks that are NOT in --order and NOT equal to --base.
  remaining=()
  if [[ -n "${keep_remaining_mode}" ]]; then
    # Build the candidate set: parents(@-) \ ({base} ∪ order).
    local candidate_set=()
    local p
    while IFS= read -r p; do
      [[ -z "${p}" ]] && continue
      # Skip if equal to base
      if [[ "${p}" == "${base}" ]]; then
        continue
      fi
      # Skip if listed in --order
      local skip=false
      local oc
      for oc in "${chains[@]}"; do
        if [[ "${p}" == "${oc}" ]]; then
          skip=true; break
        fi
      done
      $skip && continue
      candidate_set+=("${p}")
    done <<< "${flat}"

    if [[ "${keep_remaining_mode}" == "explicit" ]]; then
      local explicit_list=()
      IFS=',' read -r -a explicit_list <<< "${remaining_csv}"
      local r
      for r in "${explicit_list[@]}"; do
        if [[ -z "${r}" ]]; then
          echo "Error (precondition 18): --keep-remaining contains an empty bookmark name." >&2
          exit 18
        fi
        local found=false
        local cs
        for cs in "${candidate_set[@]}"; do
          if [[ "${r}" == "${cs}" ]]; then
            found=true; break
          fi
        done
        if ! $found; then
          echo "Error (precondition 18): --keep-remaining bookmark '${r}' is not in parents(@-) \\ ({base} ∪ order)." >&2
          echo "  valid candidates were: ${candidate_set[*]:-<none>}" >&2
          exit 18
        fi
        remaining+=("${r}")
      done
    else
      # auto: take all candidates
      if [[ ${#candidate_set[@]} -gt 0 ]]; then
        remaining=("${candidate_set[@]}")
      fi
    fi
  fi
}

# -----------------------------------------------------------------------------
# Linearization core
# -----------------------------------------------------------------------------

# Perform the abandon + sequential rebase + bookmark moves. Operates either
# in dry-run (--ignore-working-copy) or real mode.
linearize() {
  local wip_id merge_id prev c
  wip_id=$(jj_run log -r @ --no-graph -T 'change_id' --limit 1)
  merge_id=$(jj_run log -r @- --no-graph -T 'change_id' --limit 1)

  echo "abandoning development-join scaffolding: wip=${wip_id} merge=${merge_id}"
  jj_run abandon "${wip_id}" "${merge_id}"

  prev="${base}"
  for c in "${chains[@]}"; do
    echo "rebasing chain '${c}' onto '${prev}'..."
    # `jj rebase -b <chain>` rebases the whole branch containing chain's tip.
    # The bookmark stays attached to the same change-id (jj bookmarks track
    # change-ids, which survive rebase), so no explicit move is required.
    jj_run rebase -b "${c}" -d "${prev}"
    # Codify the canonical recipe's explicit-advance pattern. Resolving the
    # bookmark to itself is a no-op-or-advance that asserts our intent.
    jj_run bookmark set "${c}" -r "${c}"
    prev="${c}"
  done

  echo "creating aggregate bookmark '${aggregate}' at '${prev}'..."
  jj_run bookmark create "${aggregate}" -r "${prev}"

  if [[ ${#remaining[@]} -eq 0 ]]; then
    # Exit the diamond onto the aggregate tip. SKILL.md:574-576 says "jj new
    # main", but that recipe assumes main has been locally advanced to the
    # linearized tip. This script deliberately does NOT advance main locally
    # (forge handles the merge), so the aggregate bookmark is the right exit
    # target — it points at the linearized tip and is the developer's current
    # state until merge.
    echo "exiting development join: jj new ${aggregate}"
    jj_run new "${aggregate}"
  else
    # Partial Phase 4 reconstruction: rebase each remaining chain onto the
    # aggregate tip, then build a new development join with parents
    # {aggregate, remaining...} and a fresh wip on top. See diamond-workflow
    # skill, "Partial Phase 4" section.
    local r
    for r in "${remaining[@]}"; do
      echo "rebasing remaining chain '${r}' onto '${aggregate}'..."
      jj_run rebase -b "${r}" -d "${aggregate}"
      # Explicit-advance assertion (mirrors the order-loop above).
      jj_run bookmark set "${r}" -r "${r}"
    done

    # Build the new [merge] parent list: aggregate + remaining (insertion
    # order is used to invoke `jj new`; alphabetical order produces the
    # description).
    local new_parents=("${aggregate}" "${remaining[@]}")
    local sorted_parents=()
    local sp
    while IFS= read -r sp; do
      [[ -z "${sp}" ]] && continue
      sorted_parents+=("${sp}")
    done < <(printf '%s\n' "${new_parents[@]}" | sort)
    local new_n=${#sorted_parents[@]}
    # Comma+space separated description list. (IFS only uses its first char
    # as separator, so build the string by hand.)
    local joined=""
    local jp first=true
    for jp in "${sorted_parents[@]}"; do
      if $first; then
        joined="${jp}"; first=false
      else
        joined+=", ${jp}"
      fi
    done
    local new_desc="join N=${new_n}: ${joined}"

    echo "reconstructing development join: ${new_desc}"
    jj_run new "${new_parents[@]}" -m "${new_desc}"
    jj_run new -m "wip"
  fi
}

# Print the post-linearization summary table. Reads chain tips via short_change_id.
# Args: $1 = pre-run operation id (for undo hint)
print_summary() {
  local pre_op="$1"
  local c short
  echo ""
  echo "linearized ${#chains[@]} chains onto ${base}:"
  for c in "${chains[@]}"; do
    short=$(short_change_id "${c}")
    printf '  %-30s -> %s\n' "${c}" "${short}"
  done
  short=$(short_change_id "${aggregate}")
  echo "aggregate bookmark:"
  printf '  %-30s -> %s\n' "${aggregate}" "${short}"

  if [[ ${#remaining[@]} -gt 0 ]]; then
    echo ""
    echo "remaining chains (rebased onto ${aggregate}):"
    local r
    for r in "${remaining[@]}"; do
      short=$(short_change_id "${r}")
      printf '  %-30s -> %s\n' "${r}" "${short}"
    done
    # Reconstructed-join description: aggregate + remaining sorted.
    local new_parents=("${aggregate}" "${remaining[@]}")
    local sorted_parents=()
    local sp
    while IFS= read -r sp; do
      [[ -z "${sp}" ]] && continue
      sorted_parents+=("${sp}")
    done < <(printf '%s\n' "${new_parents[@]}" | sort)
    local joined="" jp first=true
    for jp in "${sorted_parents[@]}"; do
      if $first; then
        joined="${jp}"; first=false
      else
        joined+=", ${jp}"
      fi
    done
    echo "reconstructed join: join N=${#sorted_parents[@]}: ${joined}"
  fi

  echo ""
  echo "undo: jj op restore ${pre_op}"
  local push_args="--bookmark ${chains[0]}"
  local i
  for ((i=1; i<${#chains[@]}; i++)); do
    push_args+=" --bookmark ${chains[i]}"
  done
  push_args+=" --bookmark ${aggregate}"
  echo "next: jj git push --allow-new ${push_args}"
  if [[ ${#remaining[@]} -gt 0 ]]; then
    echo "verify diamond: jj log -r '@ | @- | parents(@-)'"
  fi
}

# -----------------------------------------------------------------------------
# Conflict detection
# -----------------------------------------------------------------------------

# Print the conflicts() revset as `<change-id-short> <bookmarks>` lines.
list_conflicts() {
  jj --ignore-working-copy log --no-graph -r 'conflicts()' \
    -T 'change_id.short() ++ " " ++ bookmarks.join(",") ++ "\n"' 2>/dev/null \
    | sed '/^$/d' || true
}

# -----------------------------------------------------------------------------
# Test scenarios
# -----------------------------------------------------------------------------
#
# Each scenario constructs a tmp jj repo with a synthetic diamond and exercises
# one code path. The test runner sets globals (chains/order_csv/aggregate/base/
# dry_run) directly rather than re-invoking the script, so the production code
# path is exercised in-process.

scenario_setup_diamond() {
  # Args: $1 = number of chains, $@ = (optional) per-chain file content
  # overrides as "chainName:path:content" triples; defaults to disjoint files.
  local n="$1"; shift
  local conflict_mode="${1:-disjoint}"; shift || true

  local tmpdir
  tmpdir=$(mktemp -d -t jj-linearize-join-test.XXXXXX)
  echo "${tmpdir}"
  cd "${tmpdir}"

  jj git init >/dev/null 2>&1
  echo "base" > base.txt
  jj describe -m "init" >/dev/null
  jj bookmark create main -r @ >/dev/null
  jj new -m "wip-base" >/dev/null

  # Build N chains from main, each with a single commit.
  local i
  for ((i=1; i<=n; i++)); do
    jj new main -m "chain ${i} commit" >/dev/null
    if [[ "${conflict_mode}" == "conflict" ]]; then
      # All chains write the same file at the same line with different content.
      echo "content-from-chain-${i}" > shared.txt
    else
      echo "content-${i}" > "file-${i}.txt"
    fi
    jj bookmark create "c${i}" -r @ >/dev/null
  done

  # Build the multi-parent [merge] and [wip] on top.
  local parents=()
  for ((i=1; i<=n; i++)); do
    parents+=("c${i}")
  done
  jj new "${parents[@]}" -m "join 1: test diamond" >/dev/null
  jj new -m "wip" >/dev/null
}

# Build a "single-chain" diamond: [merge] has parents (main, c1). --order = "c1".
scenario_setup_single_chain_diamond() {
  local tmpdir
  tmpdir=$(mktemp -d -t jj-linearize-join-test.XXXXXX)
  echo "${tmpdir}"
  cd "${tmpdir}"

  jj git init >/dev/null 2>&1
  echo "base" > base.txt
  jj describe -m "init" >/dev/null
  jj bookmark create main -r @ >/dev/null
  jj new -m "stash" >/dev/null

  jj new main -m "c1 commit" >/dev/null
  echo "c1" > file-c1.txt
  jj bookmark create c1 -r @ >/dev/null

  jj new main c1 -m "join 1: single-chain diamond" >/dev/null
  jj new -m "wip" >/dev/null
}

# Reset globals between scenarios so leftover state cannot leak.
reset_globals() {
  base="main"
  order_csv=""
  aggregate=""
  dry_run=false
  chains=()
  keep_remaining_mode=""
  remaining_csv=""
  remaining=()
}

# Run a scenario in a subshell so cd/trap state doesn't leak.
run_scenario_clean_dry() {
  local result
  result=$(
    set +e
    tmp=$(scenario_setup_diamond 3 disjoint)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL clean-dry: cd to tmpdir failed"; exit 0; }
    order_csv="c1,c2,c3"
    aggregate="agg"
    base="main"
    dry_run=true
    chains=()
    precondition_checks
    local pre_op
    pre_op=$(current_op_id)
    linearize >/dev/null 2>&1
    local conflicts
    conflicts=$(list_conflicts)
    jj --ignore-working-copy op restore "${pre_op}" >/dev/null 2>&1
    if [[ -z "${conflicts}" ]]; then
      echo "PASS clean-dry"
    else
      echo "FAIL clean-dry: unexpected conflicts: ${conflicts}"
    fi
  )
  echo "${result}"
}

run_scenario_clean_real() {
  local result
  result=$(
    set +e
    tmp=$(scenario_setup_diamond 3 disjoint)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL clean-real: cd to tmpdir failed"; exit 0; }
    order_csv="c1,c2,c3"
    aggregate="agg"
    base="main"
    dry_run=false
    chains=()
    precondition_checks
    linearize >/dev/null 2>&1
    # Verify bookmarks exist
    local ok=true
    for c in c1 c2 c3 agg; do
      if ! bookmark_exists "${c}"; then
        ok=false
        echo "FAIL clean-real: bookmark '${c}' missing after linearize"
        break
      fi
    done
    # Verify @ no longer has a multi-parent ancestor at @-
    if $ok; then
      local pcount
      pcount=$(parents_of_at_minus_count)
      if [[ "${pcount}" -ge 2 ]]; then
        ok=false
        echo "FAIL clean-real: @- still has ${pcount} parents (development join not dissolved)"
      fi
    fi
    if $ok; then
      echo "PASS clean-real"
    fi
  )
  echo "${result}"
}

run_scenario_conflict_dry() {
  local result
  result=$(
    set +e
    tmp=$(scenario_setup_diamond 2 conflict)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL conflict-dry: cd to tmpdir failed"; exit 0; }
    order_csv="c1,c2"
    aggregate="agg"
    base="main"
    dry_run=true
    chains=()
    precondition_checks
    local pre_op
    pre_op=$(current_op_id)
    linearize >/dev/null 2>&1
    local conflicts
    conflicts=$(list_conflicts)
    jj --ignore-working-copy op restore "${pre_op}" >/dev/null 2>&1
    if [[ -n "${conflicts}" ]]; then
      echo "PASS conflict-dry"
    else
      echo "FAIL conflict-dry: expected conflicts but got none"
    fi
  )
  echo "${result}"
}

run_scenario_precond_violations() {
  local all_pass=true
  local result=""

  # 13: aggregate already exists
  result+=$(
    set +e
    tmp=$(scenario_setup_diamond 2 disjoint)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL precond-13: cd to tmpdir failed"; exit 0; }
    jj bookmark create existing -r main >/dev/null 2>&1
    order_csv="c1,c2"
    aggregate="existing"
    base="main"
    dry_run=false
    chains=()
    (precondition_checks) >/dev/null 2>&1
    code=$?
    if [[ $code -eq 13 ]]; then
      echo "PASS precond-13"
    else
      echo "FAIL precond-13: expected exit 13, got ${code}"
    fi
  )
  result+=$'\n'

  # 14: non-existent chain
  result+=$(
    set +e
    tmp=$(scenario_setup_diamond 2 disjoint)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL precond-14: cd to tmpdir failed"; exit 0; }
    order_csv="c1,does-not-exist"
    aggregate="agg"
    base="main"
    dry_run=false
    chains=()
    (precondition_checks) >/dev/null 2>&1
    code=$?
    if [[ $code -eq 14 ]]; then
      echo "PASS precond-14"
    else
      echo "FAIL precond-14: expected exit 14, got ${code}"
    fi
  )
  result+=$'\n'

  # 11: empty order
  result+=$(
    set +e
    tmp=$(scenario_setup_diamond 2 disjoint)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL precond-11: cd to tmpdir failed"; exit 0; }
    order_csv=""
    aggregate="agg"
    base="main"
    dry_run=false
    chains=()
    (precondition_checks) >/dev/null 2>&1
    code=$?
    if [[ $code -eq 11 ]]; then
      echo "PASS precond-11"
    else
      echo "FAIL precond-11: expected exit 11, got ${code}"
    fi
  )
  result+=$'\n'

  # 12: missing aggregate
  result+=$(
    set +e
    tmp=$(scenario_setup_diamond 2 disjoint)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL precond-12: cd to tmpdir failed"; exit 0; }
    order_csv="c1,c2"
    aggregate=""
    base="main"
    dry_run=false
    chains=()
    (precondition_checks) >/dev/null 2>&1
    code=$?
    if [[ $code -eq 12 ]]; then
      echo "PASS precond-12"
    else
      echo "FAIL precond-12: expected exit 12, got ${code}"
    fi
  )

  if grep -q '^FAIL' <<<"${result}"; then
    all_pass=false
  fi
  echo "${result}"
  if $all_pass; then
    echo "PASS precond-violations (all 4)"
  else
    echo "FAIL precond-violations"
  fi
}

run_scenario_subset_keep_remaining() {
  local result
  result=$(
    set +e
    tmp=$(scenario_setup_diamond 4 disjoint)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL subset-keep-remaining: cd to tmpdir failed"; exit 0; }
    order_csv="c1,c2"
    aggregate="agg"
    base="main"
    dry_run=false
    chains=()
    keep_remaining_mode="explicit"
    remaining_csv="c3,c4"
    remaining=()
    precondition_checks
    linearize >/dev/null 2>&1
    local ok=true

    # c1, c2, agg bookmarks exist; c3, c4 still exist post-rebase
    local b
    for b in c1 c2 c3 c4 agg; do
      if ! bookmark_exists "${b}"; then
        ok=false
        echo "FAIL subset-keep-remaining: bookmark '${b}' missing after linearize"
        break
      fi
    done

    # Verify c3 and c4 are descendants of agg (rebased on top)
    if $ok; then
      local agg_in_c3
      agg_in_c3=$(jj --ignore-working-copy log -r "agg::c3" --no-graph -T 'change_id ++ "\n"' 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')
      if [[ "${agg_in_c3}" -lt 2 ]]; then
        ok=false
        echo "FAIL subset-keep-remaining: c3 is not a descendant of agg (path length ${agg_in_c3})"
      fi
    fi
    if $ok; then
      local agg_in_c4
      agg_in_c4=$(jj --ignore-working-copy log -r "agg::c4" --no-graph -T 'change_id ++ "\n"' 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')
      if [[ "${agg_in_c4}" -lt 2 ]]; then
        ok=false
        echo "FAIL subset-keep-remaining: c4 is not a descendant of agg (path length ${agg_in_c4})"
      fi
    fi

    # Verify new [merge] @- has exactly 3 parents (agg, c3, c4)
    if $ok; then
      local pcount
      pcount=$(parents_of_at_minus_count)
      if [[ "${pcount}" -ne 3 ]]; then
        ok=false
        echo "FAIL subset-keep-remaining: @- has ${pcount} parents; expected 3"
      fi
    fi

    # Verify description of @- contains expected alphabetical bookmarks
    if $ok; then
      local merge_desc
      merge_desc=$(jj --ignore-working-copy log -r @- --no-graph -T 'description.first_line()' --limit 1 2>/dev/null)
      local expected="join N=3: agg, c3, c4"
      if [[ "${merge_desc}" != "${expected}" ]]; then
        ok=false
        echo "FAIL subset-keep-remaining: merge description '${merge_desc}' != '${expected}'"
      fi
    fi

    # Verify @ is empty (the wip)
    if $ok; then
      if ! working_copy_empty; then
        ok=false
        echo "FAIL subset-keep-remaining: @ is not empty after reconstruction"
      fi
    fi

    if $ok; then
      echo "PASS subset-keep-remaining"
    fi
  )
  echo "${result}"
}

run_scenario_single_chain() {
  local result
  # shellcheck disable=SC2030
  # Subshell-local writes to base/dry_run/order_csv/aggregate are intentional:
  # each test scenario runs in $(...) to isolate state from the parent shell.
  result=$(
    set +e
    tmp=$(scenario_setup_single_chain_diamond)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL single-chain: cd to tmpdir failed"; exit 0; }
    order_csv="c1"
    aggregate="agg"
    base="main"
    dry_run=false
    chains=()
    precondition_checks
    linearize >/dev/null 2>&1
    if bookmark_exists c1 && bookmark_exists agg; then
      echo "PASS single-chain"
    else
      echo "FAIL single-chain: c1 or agg bookmark missing"
    fi
  )
  echo "${result}"
}

run_tests() {
  local scenario="${1:-}"
  local out=""
  case "${scenario}" in
    "" )
      out+=$(run_scenario_clean_dry); out+=$'\n'
      out+=$(run_scenario_clean_real); out+=$'\n'
      out+=$(run_scenario_conflict_dry); out+=$'\n'
      out+=$(run_scenario_precond_violations); out+=$'\n'
      out+=$(run_scenario_single_chain); out+=$'\n'
      out+=$(run_scenario_subset_keep_remaining)
      ;;
    clean-dry) out=$(run_scenario_clean_dry) ;;
    clean-real) out=$(run_scenario_clean_real) ;;
    conflict-dry) out=$(run_scenario_conflict_dry) ;;
    precond-violations) out=$(run_scenario_precond_violations) ;;
    single-chain) out=$(run_scenario_single_chain) ;;
    subset-keep-remaining) out=$(run_scenario_subset_keep_remaining) ;;
    *)
      echo "Error: unknown test scenario '${scenario}'." >&2
      echo "Valid scenarios: clean-dry, clean-real, conflict-dry, precond-violations, single-chain, subset-keep-remaining" >&2
      return 1
      ;;
  esac
  echo "${out}"
  if grep -q '^FAIL' <<<"${out}"; then
    return 1
  fi
  return 0
}

# -----------------------------------------------------------------------------
# Main dispatch
# -----------------------------------------------------------------------------

if "${test_mode}"; then
  run_tests "${test_scenario}"
  exit $?
fi

# `chains` is populated by precondition_checks from order_csv.
chains=()
precondition_checks

# shellcheck disable=SC2031
# dry_run and base are read at top level; the SC2030/SC2031 pair conflates
# them with subshell-local writes inside test scenario functions, which never
# execute in this code path (test_mode short-circuits above).
if "${dry_run}"; then
  pre_op=$(current_op_id)
  if [[ -z "${pre_op}" ]]; then
    echo "Error: could not capture pre-run operation id for dry-run restore." >&2
    exit 1
  fi
  echo "dry-run starting (pre-op=${pre_op})..."
  linearize
  conflicts=$(list_conflicts)
  jj --ignore-working-copy op restore "${pre_op}" >/dev/null
  if [[ -z "${conflicts}" ]]; then
    # shellcheck disable=SC2031
    echo "dry-run clean: would linearize ${#chains[@]} chains onto ${base} without conflict"
    exit 0
  else
    echo "dry-run would produce conflicts:"
    printf '  %s\n' "${conflicts}"
    exit 2
  fi
fi

# Real run.
pre_op=$(current_op_id)
echo "real run starting (pre-op=${pre_op})..."
linearize
conflicts=$(list_conflicts)
if [[ -n "${conflicts}" ]]; then
  echo "" >&2
  echo "linearization produced conflicts in the following commits:" >&2
  printf '  %s\n' "${conflicts}" >&2
  echo "" >&2
  echo "to restore the pre-linearization state, run:" >&2
  echo "  jj op restore ${pre_op}" >&2
  echo "" >&2
  echo "after resolving the underlying cause, re-invoke jj-linearize-join." >&2
  exit 3
fi

print_summary "${pre_op}"

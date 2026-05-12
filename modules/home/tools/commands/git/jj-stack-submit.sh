#!/usr/bin/env bash
# Submit a linearized chain (as produced by jj-linearize-join) to a forge as
# N+1 PRs: N stacked-base chain PRs (each targets the previous chain bookmark)
# and 1 aggregate PR targeting --base. By default also posts a backlink comment
# on the aggregate listing the chain PRs and marks the aggregate ready.
#
# Does NOT advance the base ref locally and does NOT trigger merges. The
# script's job is preparing PRs for review; merging is a separate concern.
#
# Exit codes:
#  0   success (or dry-run clean)
#  1   usage / unknown flag
#  10  not inside a jj repo
#  11  --order missing or empty
#  12  --aggregate-bookmark missing or empty
#  13  a chain bookmark in --order does not exist
#  14  aggregate bookmark does not exist
#  15  --base ref does not resolve
#  16  --remote is not configured
#  17  forge could not be resolved (auto-detect failed or unknown forge)
#  18  chain bookmarks do not form a linear sequence rooted at --base
#  19  aggregate bookmark is not at the chain-N tip
#  20  required forge CLI (gh or tea) is not on PATH
set -euo pipefail

show_help() {
  cat <<'HELP'
Submit a linearized chain to a forge as N+1 PRs (stacked-base + aggregate)

Usage:
  jj-stack-submit --order C1,C2,...,CN --aggregate-bookmark NAME [OPTIONS]
  jj-stack-submit test [SCENARIO]
  jj-stack-submit --help

Pushes the N chain bookmarks and the aggregate bookmark to --remote in a
single atomic `jj git push --allow-new` invocation, then opens N+1 pull
requests on the resolved forge:

  - N chain PRs in stacked-base order: chain[1] targets --base, chain[k]
    targets chain[k-1] for k>1.
  - 1 aggregate PR: aggregate bookmark targets --base.

By default also posts a backlink comment on the aggregate PR listing the
chain PR numbers, and marks the aggregate PR ready for review. These two
post-steps can be disabled with --no-backlink-comment and --no-ready.

Required options:
  --order C1,C2,...,CN          Comma-separated chain bookmark names in
                                linearization order: C1 lowest on --base,
                                CN highest.
  --aggregate-bookmark NAME     Bookmark name at the chain-N tip.

Optional options:
  --base REF                    Base ref for the aggregate PR (default: main)
  --remote REMOTE               Remote name (default: origin)
  --forge {gh,tea,auto}         Forge selector (default: auto). Auto detects
                                via `jj git remote list` URL inspection.
  --dry-run                     Print all planned commands without executing
                                pushes, PR creates, comments, or ready calls.
                                Pre-conditions are still checked.
  --no-ready                    Skip marking the aggregate PR ready.
  --no-backlink-comment         Skip posting the backlink comment on the
                                aggregate PR.
  -h, --help                    Show this help message.

Subcommand:
  test [SCENARIO]               Run embedded self-tests. SCENARIO is one of:
                                  dry-run-gh, dry-run-tea,
                                  precond-violations, forge-detection
                                Omit SCENARIO to run all.

Exit codes:
  0    success (or dry-run clean)
  1    usage / unknown flag
  10   not inside a jj repo
  11   --order missing or empty
  12   --aggregate-bookmark missing or empty
  13   a chain bookmark in --order does not exist
  14   aggregate bookmark does not exist
  15   --base ref does not resolve
  16   --remote is not configured
  17   forge could not be resolved
  18   chain bookmarks do not form a linear sequence on --base
  19   aggregate bookmark is not at the chain-N tip
  20   required forge CLI is not on PATH

Example workflow:
  # After running jj-linearize-join to flatten the diamond:
  jj-stack-submit --order c1,c2,c3 --aggregate-bookmark epic-foo --dry-run
  jj-stack-submit --order c1,c2,c3 --aggregate-bookmark epic-foo

Post-condition:
  After a successful real run, the N+1 bookmarks are pushed to --remote,
  N chain PRs are open in stacked-base order, the aggregate PR is open
  targeting --base, the backlink comment is posted on the aggregate (unless
  --no-backlink-comment), and the aggregate PR is marked ready (unless
  --no-ready). Merging is a separate, manual step.
HELP
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

base="main"
remote="origin"
forge="auto"
order_csv=""
aggregate=""
dry_run=false
ready_default=true
backlink_comment=true
test_mode=false
test_scenario=""

if [[ "${1:-}" == "test" ]]; then
  test_mode=true
  shift
  test_scenario="${1:-}"
  # Skip flag parsing.
  set --
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    --order) order_csv="${2:-}"; shift 2 ;;
    --aggregate-bookmark) aggregate="${2:-}"; shift 2 ;;
    --base) base="${2:-}"; shift 2 ;;
    --remote) remote="${2:-}"; shift 2 ;;
    --forge) forge="${2:-}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --no-ready) ready_default=false; shift ;;
    --no-backlink-comment) backlink_comment=false; shift ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      echo "Try 'jj-stack-submit --help' for more information." >&2
      exit 1
      ;;
    *)
      echo "Error: Unexpected argument: $1" >&2
      echo "Try 'jj-stack-submit --help' for more information." >&2
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# Probe whether a bookmark name exists. Returns 0 if found, 1 if not.
bookmark_exists() {
  local name="$1"
  local out
  out=$(jj --ignore-working-copy bookmark list --quiet "${name}" 2>/dev/null || true)
  if [[ -n "${out}" ]] && grep -q "^${name}:" <<<"${out}"; then
    return 0
  fi
  if [[ -n "${out}" ]] && grep -Eq "(^|[[:space:]])${name}([[:space:]:]|\$)" <<<"${out}"; then
    return 0
  fi
  return 1
}

# Resolve the change-id at a revset (first match).
change_id_at() {
  local rev="$1"
  jj --ignore-working-copy log -r "${rev}" --no-graph -T 'change_id' --limit 1 2>/dev/null
}

# Print the first-line description of a chain tip.
chain_title() {
  local rev="$1"
  jj --ignore-working-copy log -r "${rev}" --no-graph \
    -T 'description.first_line()' --limit 1 2>/dev/null
}

# Check that target is a descendant of ancestor (i.e., ancestor::target is
# non-empty and contains both). Returns 0 if ancestor is an ancestor of target.
is_ancestor_of() {
  local ancestor="$1" target="$2"
  local out
  out=$(jj --ignore-working-copy log -r "${ancestor}::${target}" --no-graph \
    -T 'change_id ++ "\n"' --limit 1 2>/dev/null | sed '/^$/d')
  [[ -n "${out}" ]]
}

# Probe whether a remote is configured.
remote_exists() {
  local name="$1"
  jj --ignore-working-copy git remote list 2>/dev/null \
    | awk '{print $1}' | grep -Fxq "${name}"
}

# Return the URL for the given remote name, empty string if not found.
remote_url() {
  local name="$1"
  jj --ignore-working-copy git remote list 2>/dev/null \
    | awk -v n="${name}" '$1 == n { print $2 }'
}

# Detect the forge from a remote URL.
# Echoes "gh", "tea", or "unknown".
detect_forge_from_url() {
  local url="$1"
  case "${url}" in
    *github.com*) echo "gh" ;;
    *gitea*|*codeberg*|*magnetite*) echo "tea" ;;
    *) echo "unknown" ;;
  esac
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

  # Parse --order into the global `chains` array.
  IFS=',' read -r -a chains <<< "${order_csv}"
  if [[ ${#chains[@]} -eq 0 ]]; then
    echo "Error (precondition 11): --order parsed to zero chains." >&2
    exit 11
  fi

  # 13: every chain bookmark exists
  local c
  for c in "${chains[@]}"; do
    if [[ -z "${c}" ]]; then
      echo "Error (precondition 13): --order contains an empty chain name." >&2
      exit 13
    fi
    if ! bookmark_exists "${c}"; then
      echo "Error (precondition 13): chain bookmark '${c}' does not exist locally." >&2
      exit 13
    fi
  done

  # 14: aggregate bookmark exists
  if ! bookmark_exists "${aggregate}"; then
    echo "Error (precondition 14): aggregate bookmark '${aggregate}' does not exist locally." >&2
    exit 14
  fi

  # 15: base ref resolves
  if ! jj --ignore-working-copy log -r "${base}" --no-graph --limit 1 \
       -T 'change_id ++ "\n"' >/dev/null 2>&1; then
    echo "Error (precondition 15): base ref '${base}' does not resolve." >&2
    exit 15
  fi

  # 16: --remote configured
  if ! remote_exists "${remote}"; then
    echo "Error (precondition 16): remote '${remote}' is not configured." >&2
    exit 16
  fi

  # 17: forge resolves
  if [[ "${forge}" == "auto" ]]; then
    local url detected
    url=$(remote_url "${remote}")
    if [[ -z "${url}" ]]; then
      echo "Error (precondition 17): could not read URL for remote '${remote}'; pass --forge explicitly." >&2
      exit 17
    fi
    detected=$(detect_forge_from_url "${url}")
    if [[ "${detected}" == "unknown" ]]; then
      echo "Error (precondition 17): could not auto-detect forge from remote URL '${url}'; pass --forge {gh,tea} explicitly." >&2
      exit 17
    fi
    forge="${detected}"
  fi
  if [[ "${forge}" != "gh" && "${forge}" != "tea" ]]; then
    echo "Error (precondition 17): unknown --forge value '${forge}'; expected one of {gh, tea, auto}." >&2
    exit 17
  fi

  # 18: chain bookmarks form a linear sequence rooted at --base
  # chain[0] must descend from --base.
  if ! is_ancestor_of "${base}" "${chains[0]}"; then
    echo "Error (precondition 18): first chain '${chains[0]}' is not a descendant of --base '${base}'." >&2
    exit 18
  fi
  local k prev
  prev="${chains[0]}"
  for ((k=1; k<${#chains[@]}; k++)); do
    if ! is_ancestor_of "${prev}" "${chains[k]}"; then
      echo "Error (precondition 18): chain '${chains[k]}' is not a descendant of '${prev}'; chains do not form a linear sequence." >&2
      exit 18
    fi
    prev="${chains[k]}"
  done

  # 19: aggregate bookmark is at the chain-N tip (same change-id)
  local last_chain agg_id tip_id
  last_chain="${chains[$((${#chains[@]} - 1))]}"
  agg_id=$(change_id_at "${aggregate}")
  tip_id=$(change_id_at "${last_chain}")
  if [[ -z "${agg_id}" || -z "${tip_id}" || "${agg_id}" != "${tip_id}" ]]; then
    echo "Error (precondition 19): aggregate '${aggregate}' (change ${agg_id:-?}) is not at chain-N tip '${last_chain}' (change ${tip_id:-?})." >&2
    exit 19
  fi

  # 20: forge CLI available
  if [[ "${forge}" == "gh" ]]; then
    if ! command -v gh >/dev/null 2>&1; then
      echo "Error (precondition 20): 'gh' is not on PATH." >&2
      exit 20
    fi
  elif [[ "${forge}" == "tea" ]]; then
    if ! command -v tea >/dev/null 2>&1; then
      echo "Error (precondition 20): 'tea' is not on PATH." >&2
      exit 20
    fi
  fi
}

# -----------------------------------------------------------------------------
# Forge dispatch
# -----------------------------------------------------------------------------

# Create a PR. Args: $1=base $2=head $3=title. Echoes the PR URL on success.
# In dry-run mode, prints DRY-RUN line and echoes a synthetic placeholder URL
# that downstream comment/ready steps can use deterministically.
forge_create_pr() {
  local base_ref="$1" head_ref="$2" title="$3"
  if "${dry_run}"; then
    case "${forge}" in
      gh)
        printf 'DRY-RUN: gh pr create -d -a @me -B %s -H %s -t %q -b ""\n' \
          "${base_ref}" "${head_ref}" "${title}" >&2
        ;;
      tea)
        # tea CLI flag verification needed at runtime
        printf 'DRY-RUN: tea pr create --base %s --head %s --title %q --description ""\n' \
          "${base_ref}" "${head_ref}" "${title}" >&2
        ;;
    esac
    echo "<${head_ref}-url>"
    return 0
  fi
  case "${forge}" in
    gh)
      gh pr create -d -a "@me" -B "${base_ref}" -H "${head_ref}" -t "${title}" -b ""
      ;;
    tea)
      # tea CLI flag verification needed at runtime
      tea pr create --base "${base_ref}" --head "${head_ref}" --title "${title}" --description ""
      ;;
  esac
}

# Post a comment on a PR. Args: $1=url $2=body
forge_post_comment() {
  local url="$1" body="$2"
  if "${dry_run}"; then
    case "${forge}" in
      gh)
        printf 'DRY-RUN: gh pr comment %s --body %q\n' "${url}" "${body}" >&2
        ;;
      tea)
        # tea CLI flag verification needed at runtime
        printf 'DRY-RUN: tea pr comment %s --content %q\n' "${url}" "${body}" >&2
        ;;
    esac
    return 0
  fi
  case "${forge}" in
    gh)
      gh pr comment "${url}" --body "${body}"
      ;;
    tea)
      # tea CLI flag verification needed at runtime
      tea pr comment "${url}" --content "${body}"
      ;;
  esac
}

# Mark a PR ready. Args: $1=url
forge_mark_ready() {
  local url="$1"
  if "${dry_run}"; then
    case "${forge}" in
      gh)
        printf 'DRY-RUN: gh pr ready %s\n' "${url}" >&2
        ;;
      tea)
        # tea CLI flag verification needed at runtime
        printf 'DRY-RUN: tea pr edit %s --ready\n' "${url}" >&2
        ;;
    esac
    return 0
  fi
  case "${forge}" in
    gh)
      gh pr ready "${url}"
      ;;
    tea)
      # tea CLI flag verification needed at runtime
      tea pr edit "${url}" --ready
      ;;
  esac
}

# Extract a PR number from a URL like https://github.com/o/r/pull/123 or a
# synthetic <name-url> placeholder from dry-run mode. Falls back to the
# last path segment of the input.
extract_pr_number() {
  local url="$1"
  # Detect dry-run synthetic placeholders of the form "<name-url>".
  if [[ "${url}" == "<"*"-url>" ]]; then
    local name="${url#<}"
    name="${name%-url>}"
    echo "<${name}-num>"
    return 0
  fi
  # Strip everything up to the last '/' which leaves the number.
  echo "${url##*/}"
}

# -----------------------------------------------------------------------------
# Push and submit
# -----------------------------------------------------------------------------

push_bookmarks() {
  local args=()
  local c
  for c in "${chains[@]}"; do
    args+=(--bookmark "${c}")
  done
  args+=(--bookmark "${aggregate}")

  if "${dry_run}"; then
    local line="DRY-RUN: jj git push --remote ${remote} --allow-new"
    local a
    for a in "${args[@]}"; do
      line+=" ${a}"
    done
    echo "${line}" >&2
    return 0
  fi
  jj git push --remote "${remote}" --allow-new "${args[@]}"
}

submit() {
  push_bookmarks

  declare -A pr_url
  local prev_chain="${base}"
  local c title url
  for c in "${chains[@]}"; do
    title=$(chain_title "${c}")
    if [[ -z "${title}" ]]; then
      title="${c}"
    fi
    url=$(forge_create_pr "${prev_chain}" "${c}" "${title}")
    pr_url["${c}"]="${url}"
    prev_chain="${c}"
  done

  # Build aggregate title: "aggregate: [c1, c2, ..., cN]"
  local agg_title="aggregate: ["
  local i
  for ((i=0; i<${#chains[@]}; i++)); do
    if [[ $i -gt 0 ]]; then
      agg_title+=", "
    fi
    agg_title+="${chains[i]}"
  done
  agg_title+="]"

  local agg_url
  agg_url=$(forge_create_pr "${base}" "${aggregate}" "${agg_title}")

  if "${backlink_comment}"; then
    local body="" pr_num
    for c in "${chains[@]}"; do
      pr_num=$(extract_pr_number "${pr_url[${c}]}")
      body+="- #${pr_num}"$'\n'
    done
    forge_post_comment "${agg_url}" "${body}"
  fi

  if "${ready_default}"; then
    forge_mark_ready "${agg_url}"
  fi

  if ! "${dry_run}"; then
    echo ""
    echo "submitted ${#chains[@]} chain PRs + 1 aggregate PR via ${forge}:"
    for c in "${chains[@]}"; do
      printf '  %-30s -> %s\n' "${c}" "${pr_url[${c}]}"
    done
    printf '  %-30s -> %s\n' "${aggregate}" "${agg_url}"
  fi
}

# -----------------------------------------------------------------------------
# Test scenarios
# -----------------------------------------------------------------------------

# Build a synthetic linearized state: N chain bookmarks stacked linearly on
# main, plus an aggregate bookmark at the chain-N tip. Echoes the tmpdir on
# stdout and cd's into it.
scenario_setup_linearized() {
  local n="${1:-3}"
  local tmpdir
  tmpdir=$(mktemp -d -t jj-stack-submit-test.XXXXXX)
  echo "${tmpdir}"
  cd "${tmpdir}"

  jj git init >/dev/null 2>&1
  echo "base" > base.txt
  jj describe -m "init" >/dev/null
  jj bookmark create main -r @ >/dev/null
  jj new -m "stash" >/dev/null

  local prev="main" i
  for ((i=1; i<=n; i++)); do
    jj new "${prev}" -m "chain ${i}" >/dev/null
    echo "content-${i}" > "file-${i}.txt"
    jj bookmark create "c${i}" -r @ >/dev/null
    prev="c${i}"
  done

  # Aggregate at chain-N tip.
  jj bookmark create agg -r "c${n}" >/dev/null
  # Move @ off the chain so working copy is clean elsewhere.
  jj new main -m "post-stash" >/dev/null
}

reset_globals() {
  base="main"
  remote="origin"
  forge="auto"
  order_csv=""
  aggregate=""
  dry_run=false
  ready_default=true
  backlink_comment=true
  chains=()
}

run_scenario_dry_run_gh() {
  local result
  result=$(
    set +e
    tmp=$(scenario_setup_linearized 3)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL dry-run-gh: cd to tmpdir failed"; exit 0; }
    order_csv="c1,c2,c3"
    aggregate="agg"
    base="main"
    remote="origin"
    forge="gh"
    dry_run=true
    ready_default=true
    backlink_comment=true
    chains=()
    # Skip remote/precond 16 by pre-creating a fake remote URL.
    jj git remote add origin "git@fake.github.com:org/repo.git" >/dev/null 2>&1 || true
    # Run preconditions and submit in the same shell (no $() subshell) so that
    # the `chains` array populated by precondition_checks remains visible to
    # submit. Capture combined stdout/stderr via process substitution.
    pre_out_file=$(mktemp)
    precondition_checks >"${pre_out_file}" 2>&1
    code=$?
    if [[ $code -ne 0 ]]; then
      echo "FAIL dry-run-gh: preconditions failed (exit ${code}): $(cat "${pre_out_file}")"
      rm -f "${pre_out_file}"
      exit 0
    fi
    rm -f "${pre_out_file}"
    out_file=$(mktemp)
    submit >"${out_file}" 2>&1
    code=$?
    out=$(cat "${out_file}")
    rm -f "${out_file}"
    if [[ $code -ne 0 ]]; then
      echo "FAIL dry-run-gh: submit failed (exit ${code}): ${out}"
      exit 0
    fi
    # Assertions on output structure.
    local pass=true
    if ! grep -q "DRY-RUN: jj git push --remote origin --allow-new --bookmark c1 --bookmark c2 --bookmark c3 --bookmark agg" <<<"${out}"; then
      pass=false
      echo "FAIL dry-run-gh: missing or malformed push line"
    fi
    if ! grep -q "DRY-RUN: gh pr create -d -a @me -B main -H c1 -t " <<<"${out}"; then
      pass=false
      echo "FAIL dry-run-gh: missing c1 PR create line"
    fi
    if ! grep -q "DRY-RUN: gh pr create -d -a @me -B c1 -H c2 -t " <<<"${out}"; then
      pass=false
      echo "FAIL dry-run-gh: missing c2 PR create line"
    fi
    if ! grep -q "DRY-RUN: gh pr create -d -a @me -B c2 -H c3 -t " <<<"${out}"; then
      pass=false
      echo "FAIL dry-run-gh: missing c3 PR create line"
    fi
    if ! grep -q "DRY-RUN: gh pr create -d -a @me -B main -H agg -t " <<<"${out}"; then
      pass=false
      echo "FAIL dry-run-gh: missing aggregate PR create line"
    fi
    if ! grep -q "DRY-RUN: gh pr comment" <<<"${out}"; then
      pass=false
      echo "FAIL dry-run-gh: missing backlink comment line"
    fi
    if ! grep -q "DRY-RUN: gh pr ready" <<<"${out}"; then
      pass=false
      echo "FAIL dry-run-gh: missing ready line"
    fi
    if $pass; then
      echo "PASS dry-run-gh"
    fi
  )
  echo "${result}"
}

run_scenario_dry_run_tea() {
  local result
  result=$(
    set +e
    tmp=$(scenario_setup_linearized 2)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL dry-run-tea: cd to tmpdir failed"; exit 0; }
    order_csv="c1,c2"
    aggregate="agg"
    base="main"
    remote="origin"
    forge="tea"
    dry_run=true
    ready_default=true
    backlink_comment=true
    chains=()
    jj git remote add origin "https://gitea.example.com/org/repo.git" >/dev/null 2>&1 || true
    pre_out_file=$(mktemp)
    precondition_checks >"${pre_out_file}" 2>&1
    code=$?
    if [[ $code -ne 0 ]]; then
      echo "FAIL dry-run-tea: preconditions failed (exit ${code}): $(cat "${pre_out_file}")"
      rm -f "${pre_out_file}"
      exit 0
    fi
    rm -f "${pre_out_file}"
    out_file=$(mktemp)
    submit >"${out_file}" 2>&1
    code=$?
    out=$(cat "${out_file}")
    rm -f "${out_file}"
    if [[ $code -ne 0 ]]; then
      echo "FAIL dry-run-tea: submit failed (exit ${code}): ${out}"
      exit 0
    fi
    local pass=true
    if ! grep -q "DRY-RUN: tea pr create --base main --head c1 " <<<"${out}"; then
      pass=false
      echo "FAIL dry-run-tea: missing c1 PR create line"
    fi
    if ! grep -q "DRY-RUN: tea pr create --base c1 --head c2 " <<<"${out}"; then
      pass=false
      echo "FAIL dry-run-tea: missing c2 PR create line"
    fi
    if ! grep -q "DRY-RUN: tea pr create --base main --head agg " <<<"${out}"; then
      pass=false
      echo "FAIL dry-run-tea: missing aggregate PR create line"
    fi
    if ! grep -q "DRY-RUN: tea pr comment" <<<"${out}"; then
      pass=false
      echo "FAIL dry-run-tea: missing backlink comment line"
    fi
    if ! grep -q "DRY-RUN: tea pr edit" <<<"${out}"; then
      pass=false
      echo "FAIL dry-run-tea: missing ready line"
    fi
    if $pass; then
      echo "PASS dry-run-tea"
    fi
  )
  echo "${result}"
}

run_scenario_precond_violations() {
  local result=""

  # 13: missing chain bookmark
  result+=$(
    set +e
    tmp=$(scenario_setup_linearized 2)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL precond-13: cd to tmpdir failed"; exit 0; }
    jj git remote add origin "git@fake.github.com:org/repo.git" >/dev/null 2>&1 || true
    order_csv="c1,does-not-exist"
    aggregate="agg"
    base="main"
    remote="origin"
    forge="gh"
    dry_run=true
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

  # 14: missing aggregate bookmark
  result+=$(
    set +e
    tmp=$(scenario_setup_linearized 2)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL precond-14: cd to tmpdir failed"; exit 0; }
    jj git remote add origin "git@fake.github.com:org/repo.git" >/dev/null 2>&1 || true
    order_csv="c1,c2"
    aggregate="missing-agg"
    base="main"
    remote="origin"
    forge="gh"
    dry_run=true
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

  # 15: missing base ref
  result+=$(
    set +e
    tmp=$(scenario_setup_linearized 2)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL precond-15: cd to tmpdir failed"; exit 0; }
    jj git remote add origin "git@fake.github.com:org/repo.git" >/dev/null 2>&1 || true
    order_csv="c1,c2"
    aggregate="agg"
    base="does-not-exist-ref"
    remote="origin"
    forge="gh"
    dry_run=true
    chains=()
    (precondition_checks) >/dev/null 2>&1
    code=$?
    if [[ $code -eq 15 ]]; then
      echo "PASS precond-15"
    else
      echo "FAIL precond-15: expected exit 15, got ${code}"
    fi
  )
  result+=$'\n'

  # 16: missing remote
  result+=$(
    set +e
    tmp=$(scenario_setup_linearized 2)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL precond-16: cd to tmpdir failed"; exit 0; }
    order_csv="c1,c2"
    aggregate="agg"
    base="main"
    remote="never-configured"
    forge="gh"
    dry_run=true
    chains=()
    (precondition_checks) >/dev/null 2>&1
    code=$?
    if [[ $code -eq 16 ]]; then
      echo "PASS precond-16"
    else
      echo "FAIL precond-16: expected exit 16, got ${code}"
    fi
  )
  result+=$'\n'

  # 18: non-linear chain (two chains both descending from main but neither
  # descending from the other). Build a fork structure.
  result+=$(
    set +e
    tmp=$(mktemp -d -t jj-stack-submit-test.XXXXXX)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL precond-18: cd to tmpdir failed"; exit 0; }
    jj git init >/dev/null 2>&1
    echo "base" > base.txt
    jj describe -m "init" >/dev/null
    jj bookmark create main -r @ >/dev/null
    jj new -m "stash" >/dev/null
    jj new main -m "fork-a" >/dev/null
    echo "a" > file-a.txt
    jj bookmark create c1 -r @ >/dev/null
    jj new main -m "fork-b" >/dev/null
    echo "b" > file-b.txt
    jj bookmark create c2 -r @ >/dev/null
    jj bookmark create agg -r c2 >/dev/null
    jj git remote add origin "git@fake.github.com:org/repo.git" >/dev/null 2>&1 || true
    order_csv="c1,c2"
    aggregate="agg"
    base="main"
    remote="origin"
    forge="gh"
    dry_run=true
    chains=()
    (precondition_checks) >/dev/null 2>&1
    code=$?
    if [[ $code -eq 18 ]]; then
      echo "PASS precond-18"
    else
      echo "FAIL precond-18: expected exit 18, got ${code}"
    fi
  )
  result+=$'\n'

  # 19: aggregate not at chain-N tip
  result+=$(
    set +e
    tmp=$(scenario_setup_linearized 3)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL precond-19: cd to tmpdir failed"; exit 0; }
    # Move agg off c3 so it points elsewhere. jj rejects backwards moves
    # (c3 -> c1) without --allow-backwards.
    jj bookmark set agg -r c1 --allow-backwards >/dev/null 2>&1 \
      || jj bookmark move agg --to c1 --allow-backwards >/dev/null 2>&1
    jj git remote add origin "git@fake.github.com:org/repo.git" >/dev/null 2>&1 || true
    order_csv="c1,c2,c3"
    aggregate="agg"
    base="main"
    remote="origin"
    forge="gh"
    dry_run=true
    chains=()
    (precondition_checks) >/dev/null 2>&1
    code=$?
    if [[ $code -eq 19 ]]; then
      echo "PASS precond-19"
    else
      echo "FAIL precond-19: expected exit 19, got ${code}"
    fi
  )

  echo "${result}"
  if grep -q '^FAIL' <<<"${result}"; then
    echo "FAIL precond-violations"
  else
    echo "PASS precond-violations (all 6)"
  fi
}

run_scenario_forge_detection() {
  local result=""

  # Case 1: github.com -> gh
  result+=$(
    set +e
    tmp=$(scenario_setup_linearized 1)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL forge-detect-gh: cd failed"; exit 0; }
    jj git remote add origin "git@github.com:org/repo.git" >/dev/null 2>&1 || true
    order_csv="c1"
    aggregate="agg"
    base="main"
    remote="origin"
    forge="auto"
    dry_run=true
    chains=()
    # Call precondition_checks directly (no inner subshell) so that the
    # forge="gh" mutation propagates to the test's check below.
    precondition_checks >/dev/null 2>&1
    code=$?
    if [[ $code -eq 0 && "${forge}" == "gh" ]]; then
      echo "PASS forge-detect-gh"
    else
      echo "FAIL forge-detect-gh: code=${code} forge=${forge}"
    fi
  )
  result+=$'\n'

  # Case 2: gitea -> tea
  result+=$(
    set +e
    tmp=$(scenario_setup_linearized 1)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL forge-detect-tea: cd failed"; exit 0; }
    jj git remote add origin "https://gitea.example.com/org/repo.git" >/dev/null 2>&1 || true
    order_csv="c1"
    aggregate="agg"
    base="main"
    remote="origin"
    forge="auto"
    dry_run=true
    chains=()
    # Call precondition_checks directly (no inner subshell) so that the
    # forge="tea" mutation propagates to the test's check below.
    precondition_checks >/dev/null 2>&1
    code=$?
    if [[ $code -eq 0 && "${forge}" == "tea" ]]; then
      echo "PASS forge-detect-tea"
    else
      echo "FAIL forge-detect-tea: code=${code} forge=${forge}"
    fi
  )
  result+=$'\n'

  # Case 3: unknown URL -> exit 17
  # shellcheck disable=SC2030
  # Subshell-local writes to base/forge/dry_run/etc. are intentional: each
  # test scenario runs in $(...) to isolate state from the parent shell.
  result+=$(
    set +e
    tmp=$(scenario_setup_linearized 1)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL forge-detect-unknown: cd failed"; exit 0; }
    jj git remote add origin "https://example.com/org/repo.git" >/dev/null 2>&1 || true
    order_csv="c1"
    aggregate="agg"
    base="main"
    remote="origin"
    forge="auto"
    dry_run=true
    chains=()
    (precondition_checks) >/dev/null 2>&1
    code=$?
    if [[ $code -eq 17 ]]; then
      echo "PASS forge-detect-unknown"
    else
      echo "FAIL forge-detect-unknown: expected exit 17, got ${code}"
    fi
  )

  echo "${result}"
  if grep -q '^FAIL' <<<"${result}"; then
    echo "FAIL forge-detection"
  else
    echo "PASS forge-detection (all 3)"
  fi
}

run_tests() {
  local scenario="${1:-}"
  local out=""
  case "${scenario}" in
    "")
      out+=$(run_scenario_dry_run_gh); out+=$'\n'
      out+=$(run_scenario_dry_run_tea); out+=$'\n'
      out+=$(run_scenario_precond_violations); out+=$'\n'
      out+=$(run_scenario_forge_detection)
      ;;
    dry-run-gh) out=$(run_scenario_dry_run_gh) ;;
    dry-run-tea) out=$(run_scenario_dry_run_tea) ;;
    precond-violations) out=$(run_scenario_precond_violations) ;;
    forge-detection) out=$(run_scenario_forge_detection) ;;
    *)
      echo "Error: unknown test scenario '${scenario}'." >&2
      echo "Valid scenarios: dry-run-gh, dry-run-tea, precond-violations, forge-detection" >&2
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

chains=()
precondition_checks

# shellcheck disable=SC2031
# dry_run and forge are read at top level; the SC2030/SC2031 pair conflates
# them with subshell-local writes inside test scenario functions, which never
# execute in this code path (test_mode short-circuits above).
if "${dry_run}"; then
  echo "dry-run starting..."
  submit
  # shellcheck disable=SC2031
  echo "dry-run clean: would submit ${#chains[@]} chain PRs + 1 aggregate PR via ${forge}"
  exit 0
fi

echo "real run starting..."
submit

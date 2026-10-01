#!/usr/bin/env bash
# shellcheck shell=bash
# Docs browser-evidence publisher invoked via `nix run .#publish-evidence`;
# see usage() for the interface. It turns the report nixbot already built for
# a default-branch build into an inert bundle plus a receipt. The report and
# its metadata are untrusted data: nothing from them is evaluated, executed or
# expanded by a shell, and a missing or rejected report never falls back to
# building one.
#
# Set by publish-evidence.nix: validator (this program's own copy of
# packages/docs/tests/report/validate-report.ts, never the report's).
# Test seams: PUBLISH_EVIDENCE_DEBUG (keep the tmpdir). nix-store honours
# NIX_REMOTE, so a rehearsal realises reports against a chroot store.

set -euo pipefail

usage() {
  cat <<'EOF'
usage: publish-evidence build-finished --out <dir>
       publish-evidence --help

Publish the docs browser report nixbot built for a finished build as an
inert evidence bundle and receipt.

Subcommands:
  build-finished  nixbot build_finished event: look up the event's build
                  through nixbot's build API, select the
                  checks.x86_64-linux.package-vanixiets-docs-test-e2e-report
                  attribute, realise its recorded output, validate it, and
                  write run.json, playwright-report/completion.json, the PNG
                  screenshots its attempts reference, and receipt.json into
                  --out. Prints
                  `PUBLISH-EVIDENCE: published (build <n>, passed=<bool>)`,
                  or `PUBLISH-EVIDENCE: unchanged (build <n>, passed=<bool>)`
                  when --out already holds this exact publication. A report
                  whose assertions failed is published with passed=false.
                  The aggregate build may have failed.

Flags:
  --out <dir>     publication directory; it must not exist, be empty, or
                  hold this build's identical publication. Upload to a
                  storage backend is not selected yet, so publication ends
                  at this local directory.
  --help, -h      print this usage and exit 0

Exit status: 0 published or unchanged, 1 evidence unavailable or rejected,
2 usage error.

Environment:
  NIXBOT_EVENT_KIND, NIXBOT_EVENT_JSON, NIXBOT_API_URL   set by nixbot
  PUBLISH_EVIDENCE_DEBUG                                 optional

Example:
  nix run .#publish-evidence -- build-finished --out ./evidence
EOF
}

usage_error() {
  echo "error: $*" >&2
  echo "(run publish-evidence --help for usage)" >&2
  exit 2
}

die() {
  echo "error: $*" >&2
  exit 1
}

mode="${1:-}"
case "$mode" in
  -h | --help)
    usage
    exit 0
    ;;
  build-finished) ;;
  "") usage_error "missing subcommand" ;;
  *) usage_error "unknown subcommand '$mode'" ;;
esac
shift

# Only the flag sets the destination: a builder's or caller's exported
# `out` must not choose where evidence lands.
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --out)
      [[ $# -ge 2 ]] || usage_error "$1 requires a value"
      out="$2"
      shift 2
      ;;
    *) usage_error "unexpected argument '$1'" ;;
  esac
done
[[ -n "$out" ]] || usage_error "--out is required"
: "${validator:?validator not set; publish-evidence.nix must interpolate validate-report.ts}"

# The x86_64-linux report is the CI evidence (W1); its provenance must name
# the same system and the default suite, so another platform's or a negative
# control's report cannot be published under this attribute.
readonly repo=cameronraysmith/vanixiets
readonly report_attr=checks.x86_64-linux.package-vanixiets-docs-test-e2e-report
readonly report_system=x86_64-linux
readonly report_config=playwright.config.ts

out_parent="$(dirname -- "$out")"
[[ -d "$out_parent" ]] || die "the parent of --out $out is not a directory"

tmpdir=$(mktemp -d -t publish-evidence.XXXXXX)
stage=""
on_exit() {
  local rc=$?
  trap - EXIT
  [[ -z "$stage" ]] || rm -rf "$stage"
  if [[ -n "${PUBLISH_EVIDENCE_DEBUG:-}" ]]; then
    echo "[publish-evidence] DEBUG: tmpdir preserved at '$tmpdir'" >&2
  else
    rm -rf "$tmpdir"
  fi
  exit "$rc"
}
trap on_exit EXIT

unavailable() {
  die "evidence unavailable: $*"
}
rejected() {
  die "evidence rejected: $*"
}

# --- the event: data only, validated before use

[[ "${NIXBOT_EVENT_KIND:-}" == build_finished ]] ||
  die "expected a build_finished event, got ${NIXBOT_EVENT_KIND:-none}"
for var in NIXBOT_API_URL NIXBOT_EVENT_JSON; do
  [[ -n "${!var:-}" ]] || die "$var is not set"
done
[[ "$NIXBOT_API_URL" =~ ^https?://[^[:space:]]+$ ]] || die "malformed NIXBOT_API_URL"
event_field() {
  jq -r --arg key "$1" '.build[$key] | if type == "string" or type == "number" then tostring else "" end' \
    "$NIXBOT_EVENT_JSON"
}
build_number="$(event_field number)" || die "cannot read the build from $NIXBOT_EVENT_JSON"
rev="$(event_field rev)" || die "cannot read the build from $NIXBOT_EVENT_JSON"
build_status="$(event_field status)" || die "cannot read the build from $NIXBOT_EVENT_JSON"
build_event_url="$(event_field url)" || die "cannot read the build from $NIXBOT_EVENT_JSON"
if ! [[ "$build_number" =~ ^[0-9]+$ && "$rev" =~ ^[0-9a-f]{40}$ && "$build_status" =~ ^[a-z_]+$ &&
  "$build_event_url" =~ ^https?://[^[:space:]]+$ ]]; then
  die "malformed event (build=$(jq -c '.build.number' "$NIXBOT_EVENT_JSON") rev=$(jq -c '.build.rev' "$NIXBOT_EVENT_JSON"))"
fi

echo "=== publish-evidence (build $build_number at ${rev:0:12}, $build_status) ==="

# --- the recorded report output, by build number: nothing is evaluated, and
# an absent output is reported rather than rebuilt (S5, S7).

build_url="$NIXBOT_API_URL/api/repos/github/$repo/builds/$build_number"
build_json="$(curl -fsS --retry 3 "$build_url")" ||
  unavailable "cannot fetch nixbot build $build_number from $build_url"
api_identity="$(jq -r '[.build.number, .build.commit_sha] | map(tostring) | join(" ")' <<<"$build_json")" ||
  unavailable "nixbot build $build_number response is not JSON"
[[ "$api_identity" == "$build_number $rev" ]] ||
  rejected "nixbot build $build_number is $(jq -c '{number: .build.number, rev: .build.commit_sha}' <<<"$build_json"), not the event's build $build_number at $rev"
attribute="$(jq -c --arg attr "$report_attr" 'first(.attributes[]? | select(.attr == $attr)) // empty' <<<"$build_json")"
[[ -n "$attribute" ]] ||
  unavailable "nixbot build $build_number has no attribute $report_attr"
attr_status="$(jq -c '.status' <<<"$attribute")"
case "$attr_status" in
  '"succeeded"' | '"skipped_local"') ;;
  *) unavailable "nixbot build $build_number attribute $report_attr is $attr_status" ;;
esac
# Recorded as the API states it: succeeded does not mean freshly executed.
cached="$(jq -c '.cached' <<<"$attribute")"
[[ "$cached" == true || "$cached" == false ]] ||
  unavailable "nixbot build $build_number attribute $report_attr has no boolean cached field"
report="$(jq -r '.outputs.out | if type == "string" then . else "" end' <<<"$attribute")"
[[ "$report" =~ ^/nix/store/[0-9a-z]{32}-[A-Za-z0-9+._?=-]+$ ]] ||
  unavailable "nixbot build $build_number attribute $report_attr has no store path output: $(jq -c '.outputs.out' <<<"$attribute")"
nix-store --realise "$report" >/dev/null ||
  unavailable "cannot realise $report"

# --- the inert bundle: only regular, non-symlinked files at normalised
# relative paths, and screenshots only when their bytes are PNG.

[[ ! -L "$report" && -d "$report" ]] || rejected "$report is not a directory"

# no_symlink <relative path>: refuses a symlink at any component, so a link
# cannot substitute bytes from elsewhere, even inside the report.
no_symlink() {
  local prefix="$report" part parts
  IFS=/ read -ra parts <<<"$1"
  for part in "${parts[@]}"; do
    prefix+="/$part"
    [[ ! -L "$prefix" ]] || rejected "symlink in the report: $1"
  done
  [[ -f "$prefix" ]] || rejected "not a regular file in the report: $1"
}

no_symlink run.json
no_symlink playwright-report/completion.json

# Each attachment as one JSON-encoded line, so a path's bytes reach error
# messages escaped and never split a line.
attachments="$(jq -c '
  [.tests[]?.attempts[]?.attachments[]?]
  | if all(type == "string") then .[] else error("non-string attachment") end
' "$report/playwright-report/completion.json")" ||
  rejected "playwright-report/completion.json attachments are not strings in JSON"
screenshots=()
while IFS= read -r encoded; do
  [[ -n "$encoded" ]] || continue
  # The sentinel keeps a trailing newline in the decoded path.
  path="$(jq -j '., "."' <<<"$encoded")"
  path="${path%.}"
  [[ "$path" != /* ]] || rejected "absolute attachment path $encoded"
  [[ "$path" =~ ^[A-Za-z0-9._@+/-]+$ ]] || rejected "unexpected characters in attachment path $encoded"
  case "/$path/" in
    */../* | */./* | *//*) rejected "attachment path is not normalised $encoded" ;;
  esac
  [[ "$path" == *.png ]] || continue
  no_symlink "$path"
  [[ "$(od -An -tx1 -N8 "$report/$path" | tr -d ' \n')" == 89504e470d0a1a0a ]] ||
    rejected "attachment is not PNG data $encoded"
  screenshots+=("$path")
done <<<"$attachments"

provenance="$(jq -c '.provenance | if type == "object" then . else error("no provenance") end' "$report/run.json")" ||
  rejected "run.json has no provenance object"
report_identity="$(jq -c '{system, config}' <<<"$provenance")"
expected_identity="$(jq -nc --arg system "$report_system" --arg config "$report_config" '{system: $system, config: $config}')"
[[ "$report_identity" == "$expected_identity" ]] ||
  rejected "report provenance $report_identity does not match $report_attr $expected_identity"

# This program's validator judges the report; a negative report is valid
# evidence (exit 0, passed false), anything else is not publishable.
validator_status=0
verdict="$(node "$validator" validate "$report" 2>"$tmpdir/validator.err")" || validator_status=$?
case "$validator_status" in
  0) ;;
  2) rejected "invalid report: $(cat "$tmpdir/validator.err")" ;;
  *) die "validate-report.ts exited $validator_status: $(cat "$tmpdir/validator.err")" ;;
esac

# --- publication: staged next to --out and renamed into place, so --out
# never holds a partial bundle or a receipt for rejected evidence.

stage="$(mktemp -d "$out_parent/.publish-evidence.XXXXXX")"
chmod 0755 "$stage"
files=()
while IFS= read -r path; do
  mkdir -p "$stage/$(dirname -- "$path")"
  install -m 0644 "$report/$path" "$stage/$path"
  files+=("$path")
done < <(printf '%s\n' run.json playwright-report/completion.json "${screenshots[@]}" | LC_ALL=C sort -u)

for path in "${files[@]}"; do
  jq -nc --arg path "$path" --arg sha256 "$(sha256sum "$stage/$path" | cut -d' ' -f1)" \
    --argjson bytes "$(wc -c <"$stage/$path")" '{path: $path, sha256: $sha256, bytes: $bytes}'
done >"$tmpdir/files.jsonl"

# No timestamp: the receipt is a function of the build/report identity, so a
# retry reproduces it byte for byte.
jq -n \
  --argjson number "$build_number" \
  --arg rev "$rev" \
  --arg status "$build_status" \
  --arg url "$build_event_url" \
  --arg attribute "$report_attr" \
  --arg outPath "$report" \
  --argjson cached "$cached" \
  --argjson provenance "$provenance" \
  --argjson verdict "$verdict" \
  --slurpfile files "$tmpdir/files.jsonl" \
  '{
    schemaVersion: 1,
    build: {number: $number, rev: $rev, status: $status, url: $url},
    attribute: $attribute,
    outPath: $outPath,
    cached: $cached,
    reportProvenance: $provenance,
    verdict: {passed: $verdict.passed, counts: $verdict.counts},
    files: $files
  }' >"$stage/receipt.json"
chmod 0644 "$stage/receipt.json"
passed="$(jq -r '.verdict.passed' "$stage/receipt.json")"

identity='[.build.number, .build.rev, .attribute, .outPath]'
if [[ -e "$out/receipt.json" || -L "$out/receipt.json" ]]; then
  existing="$(jq -c "$identity" "$out/receipt.json" 2>/dev/null)" ||
    die "--out $out holds an unreadable receipt; refusing to overwrite it"
  [[ "$existing" == "$(jq -c "$identity" "$stage/receipt.json")" ]] ||
    die "--out $out holds the receipt of another publication $existing; refusing to overwrite it"
  diff -r "$stage" "$out" >/dev/null ||
    die "--out $out holds a different publication of build $build_number; refusing to overwrite it"
  echo "PUBLISH-EVIDENCE: unchanged (build $build_number, passed=$passed)"
  exit 0
fi
if [[ -e "$out" || -L "$out" ]]; then
  [[ -d "$out" && ! -L "$out" && -z "$(find "$out" -mindepth 1 -print -quit)" ]] ||
    die "--out $out is neither empty nor a publication; refusing to overwrite it"
fi
# rename(2) replaces an empty directory; a concurrent publisher that filled
# --out meanwhile makes it fail rather than merge.
mv -T "$stage" "$out" || die "cannot move the publication into $out"
stage=""
echo "PUBLISH-EVIDENCE: published (build $build_number, passed=$passed)"

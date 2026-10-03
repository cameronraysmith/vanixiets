#!/usr/bin/env bash
# shellcheck shell=bash
# Docs browser-evidence publisher invoked via `nix run .#publish-evidence`;
# see usage() for the interface. It turns the report nixbot already built
# into an inert bundle plus a receipt, in a local directory, the evidence
# bucket, or both. The report and its metadata are untrusted data: nothing
# from them is evaluated, executed or expanded by a shell, and a missing or
# rejected report never falls back to building one.
#
# Set by publish-evidence.nix: validator (this program's own copy of
# packages/docs/tests/report/validate-report.ts, never the report's).
# Test seams: PUBLISH_EVIDENCE_DEBUG (keep the tmpdir),
# PUBLISH_EVIDENCE_S3_ENDPOINT (the S3 API origin, optionally with a path
# prefix). nix-store honours NIX_REMOTE, so a rehearsal realises reports
# against a chroot store.

set -euo pipefail

usage() {
  cat <<'EOF'
usage: publish-evidence event [--out <dir>] [--upload]
       publish-evidence main --rev <commit> [--out <dir>] [--upload]
       publish-evidence --help

Publish the docs browser report nixbot built for a build as an inert
evidence bundle and receipt, into a local directory, the evidence bucket,
or both.

Subcommands:
  event           nixbot event of kind build_finished or pull_request
                  (NIXBOT_EVENT_KIND; any other kind is an error): look up
                  the event's build through nixbot's build API, select the
                  checks.x86_64-linux.package-vanixiets-docs-test-e2e-report
                  attribute, realise its recorded output, validate it, and
                  publish run.json, playwright-report/completion.json, the
                  PNG screenshots its attempts reference, and receipt.json.
                  A report whose assertions failed is published with
                  passed=false. The aggregate build may have failed.
                  An event without a pull request publishes as main does.
                  A pull_request event may name a build nixbot reused for
                  the pull request's head (an identical tree): the build's
                  commit then differs from pullRequest.headRev, and the
                  comment says so.
                  With --upload, an event carrying a pull request first
                  probes tier ttl-90d, read-only, for this report:
                    present  unaffected: the identical report is already
                             published from main; nothing is uploaded and
                             no comment is posted, except that a comment
                             this program left on the pull request is
                             replaced once by a note that it is superseded
                    absent   affected: the report uploads to tier ttl-30d,
                             then one comment on the pull request links its
                             screenshots and receipt
  main            default-branch push: resolve the newest nixbot build of
                  --rev through the build API, then publish as event does
                  without a pull request, to tier ttl-90d, without probe or
                  comment.

Flags:
  --out <dir>     publication directory; it must not exist, be empty, or
                  hold this report's identical publication.
  --upload        upload the bundle to the R2 bucket sciexp under
                  projects/vanixiets/browser-evidence/<tier>/v1/<obs>/,
                  receipt.json last and only where none exists, served at
                  https://evidence.vanixiets.net/vanixiets/browser-evidence/<tier>/v1/<obs>/
                  (the key without its projects/ segment).
                  <obs> hashes only the report's identity, its attribute
                  and store path, and the receipt holds nothing per build,
                  so every build carrying the same report targets the same
                  keys with a byte-identical receipt.
  --rev <commit>  main only, required: the 40-hex commit whose build to
                  publish.
  --help, -h      print this usage and exit 0
At least one of --out and --upload is required.

Pull request marker: the comment's state is recorded at
projects/vanixiets/browser-evidence/ttl-30d/pr/<pr>.json as
{"schemaVersion":1,"pr":N,"state":"current"|"superseded","obs","build","rev","head"},
where rev is the build's commit and head the pull request head it settled
for (pullRequest.headRev, or rev when the event names none); the two
differ when nixbot reused a build of an identical tree. It is
written current after each affected comment and superseded after the
superseding comment. Two builds of one pull request finishing out of order
race on it: the run that finishes last wins.

Output:
  PUBLISH-EVIDENCE: published (report <obs>, passed=<bool>)
  PUBLISH-EVIDENCE: unchanged (report <obs>, passed=<bool>)
                  every destination already held this exact publication;
                  not printed for an unaffected run without --out
  PUBLISH-EVIDENCE: uploaded <url>     this run wrote the bucket's receipt
  PUBLISH-EVIDENCE: unaffected (report <obs> already published from main)
  PUBLISH-EVIDENCE: commented #<pr>    the pull request comment is current
  PUBLISH-EVIDENCE: superseded #<pr>   the comment now says it is superseded

Exit status: 0 published, unchanged or unaffected; 1 evidence unavailable
or rejected, a destination holding a different publication, or a failed
probe, upload, comment or marker update (a retry is idempotent); 2 usage
error.

Environment:
  NIXBOT_EVENT_KIND, NIXBOT_EVENT_JSON  event; set by nixbot
  NIXBOT_API_URL                        set by nixbot
  NIXBOT_API_TOKEN                      set by nixbot; pull request comment
  R2_EVIDENCE_ACCESS_KEY_ID, R2_EVIDENCE_SECRET_ACCESS_KEY,
  CLOUDFLARE_ACCOUNT_ID                 --upload: the parent R2 token, which
                                        only signs local 15-minute
                                        credentials: read-write on the
                                        run's own tier, and for a pull
                                        request read-only on ttl-90d
  PUBLISH_EVIDENCE_S3_ENDPOINT          optional, default
                                        https://<account>.r2.cloudflarestorage.com
  PUBLISH_EVIDENCE_DEBUG                optional

Examples:
  nix run .#publish-evidence -- event --out ./evidence
  nix run .#publish-evidence -- main --rev <commit> --upload
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
  event | main) ;;
  "") usage_error "missing subcommand" ;;
  *) usage_error "unknown subcommand '$mode'" ;;
esac
shift

# Only the flag sets the destination: a builder's or caller's exported
# `out` must not choose where evidence lands.
out=""
upload=false
main_rev=""
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
    --upload)
      upload=true
      shift
      ;;
    --rev)
      [[ "$mode" == main ]] || usage_error "--rev is only valid for main"
      [[ $# -ge 2 ]] || usage_error "$1 requires a value"
      main_rev="$2"
      shift 2
      ;;
    *) usage_error "unexpected argument '$1'" ;;
  esac
done
if [[ "$mode" == main ]]; then
  [[ -n "$main_rev" ]] || usage_error "main requires --rev"
  [[ "$main_rev" =~ ^[0-9a-f]{40}$ ]] || usage_error "--rev must be a 40-hex commit, got '$main_rev'"
fi
[[ -n "$out" || "$upload" == true ]] || usage_error "one of --out or --upload is required"
: "${validator:?validator not set; publish-evidence.nix must interpolate validate-report.ts}"

# The x86_64-linux report is the CI evidence (W1); its provenance must name
# the same system and the default suite, so another platform's or a negative
# control's report cannot be published under this attribute.
readonly repo=cameronraysmith/vanixiets
readonly report_attr=checks.x86_64-linux.package-vanixiets-docs-test-e2e-report
readonly report_system=x86_64-linux
readonly report_config=playwright.config.ts
# The evidence bucket's layout, shared with the vanixiets-evidence Worker
# and the bucket lifecycle rules in modules/terranix/cloudflare.nix.
readonly bucket=sciexp
readonly key_root=projects/vanixiets/browser-evidence
# The Worker serves key projects/<path> at <evidence_host>/<path>. The host
# is dedicated to untrusted CI content: nothing on vanixiets.net carries
# authentication, sessions or cookies.
readonly evidence_host=https://evidence.vanixiets.net
readonly comment_marker=vanixiets-browser-evidence

if [[ -n "$out" ]]; then
  out_parent="$(dirname -- "$out")"
  [[ -d "$out_parent" ]] || die "the parent of --out $out is not a directory"
fi

# --- upload credentials, checked before any request. The parent secret
# leaves the environment at once, so no child process inherits it; only the
# signing step below sees it.
if [[ "$upload" == true ]]; then
  for var in R2_EVIDENCE_ACCESS_KEY_ID R2_EVIDENCE_SECRET_ACCESS_KEY CLOUDFLARE_ACCOUNT_ID; do
    [[ -n "${!var:-}" ]] || die "$var is not set (required by --upload)"
  done
  [[ "$R2_EVIDENCE_ACCESS_KEY_ID" =~ ^[A-Za-z0-9]+$ ]] || die "malformed R2_EVIDENCE_ACCESS_KEY_ID"
  [[ "$CLOUDFLARE_ACCOUNT_ID" =~ ^[0-9a-f]{32}$ ]] || die "malformed CLOUDFLARE_ACCOUNT_ID"
  s3_endpoint="${PUBLISH_EVIDENCE_S3_ENDPOINT:-https://$CLOUDFLARE_ACCOUNT_ID.r2.cloudflarestorage.com}"
  s3_endpoint="${s3_endpoint%/}"
  [[ "$s3_endpoint" =~ ^https?://[A-Za-z0-9.:-]+(/[A-Za-z0-9._/-]*)?$ ]] ||
    die "malformed S3 endpoint $s3_endpoint"
  parent_secret="$R2_EVIDENCE_SECRET_ACCESS_KEY"
  unset R2_EVIDENCE_SECRET_ACCESS_KEY
fi

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

# --- the build: from the event (data only, validated before use) or, for
# main, from nixbot's builds of --rev.

pr_number=""
pr_head=""
if [[ "$mode" == event ]]; then
  # build_finished: any build, though the effect subscribes to failed ones
  # only; pull_request: a pull request's build settled green, fresh or
  # reused for its head. Both carry the build; a pull request's also its
  # head.
  case "${NIXBOT_EVENT_KIND:-}" in
    build_finished | pull_request) ;;
    *) die "expected a build_finished or pull_request event, got ${NIXBOT_EVENT_KIND:-none}" ;;
  esac
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
  # A pull request build's evidence is short-lived (ttl-30d) and linked
  # from the pull request; anything else is kept for ttl-90d.
  pr_type="$(jq -r '.pullRequest | type' "$NIXBOT_EVENT_JSON")" ||
    die "cannot read the pull request from $NIXBOT_EVENT_JSON"
  if [[ "$pr_type" == object ]]; then
    pr_number="$(jq -r '.pullRequest.number | if type == "number" then tostring else "" end' "$NIXBOT_EVENT_JSON")"
    [[ "$pr_number" =~ ^[0-9]+$ ]] ||
      die "malformed event (pullRequest.number=$(jq -c '.pullRequest.number' "$NIXBOT_EVENT_JSON"))"
    # The head this build settled for: nixbot reuses a terminal build for
    # a new commit with an identical tree, so it may differ from the
    # build's commit. Absent or null names none.
    pr_head="$(jq -r '.pullRequest.headRev // "" | if type == "string" then . else tojson end' "$NIXBOT_EVENT_JSON")"
    [[ -z "$pr_head" || "$pr_head" =~ ^[0-9a-f]{40}$ ]] ||
      die "malformed event (pullRequest.headRev=$(jq -c '.pullRequest.headRev' "$NIXBOT_EVENT_JSON"))"
    tier=ttl-30d
  else
    tier=ttl-90d
  fi
  build_source="the event's build"
else
  [[ -n "${NIXBOT_API_URL:-}" ]] ||
    die "NIXBOT_API_URL is not set: main resolves the build of --rev through nixbot's build API, which nixbot exposes to an effect only with its task token"
  [[ "$NIXBOT_API_URL" =~ ^https?://[^[:space:]]+$ ]] || die "malformed NIXBOT_API_URL"
  rev="$main_rev"
  builds_url="$NIXBOT_API_URL/api/repos/github/$repo/builds?commit=$rev"
  builds_json="$(curl -fsS --retry 3 "$builds_url")" ||
    unavailable "cannot list nixbot builds of $rev from $builds_url"
  # The filter matches a commit prefix: keep exact commits, newest build.
  selected="$(jq -c --arg rev "$rev" '[.items[]? | select(.commit_sha == $rev)] | max_by(.number) // empty' <<<"$builds_json")" ||
    unavailable "nixbot builds of $rev response is not JSON"
  [[ -n "$selected" ]] || unavailable "nixbot has no build of $rev"
  build_number="$(jq -r '.number | if type == "number" then tostring else "" end' <<<"$selected")"
  build_status="$(jq -r '.status | if type == "string" then . else "" end' <<<"$selected")"
  [[ "$build_number" =~ ^[0-9]+$ && "$build_status" =~ ^[a-z_]+$ ]] ||
    unavailable "malformed nixbot build of $rev: $selected"
  # The URL nixbot's own events carry for this build.
  build_event_url="$NIXBOT_API_URL/repos/github/$repo/builds/$build_number"
  tier=ttl-90d
  build_source="build $build_number of --rev,"
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
  rejected "nixbot build $build_number is $(jq -c '{number: .build.number, rev: .build.commit_sha}' <<<"$build_json"), not $build_source $build_number at $rev"
attribute="$(jq -c --arg attr "$report_attr" 'first(.attributes[]? | select(.attr == $attr)) // empty' <<<"$build_json")"
[[ -n "$attribute" ]] ||
  unavailable "nixbot build $build_number has no attribute $report_attr"
attr_status="$(jq -c '.status' <<<"$attribute")"
case "$attr_status" in
  '"succeeded"' | '"skipped_local"') ;;
  *) unavailable "nixbot build $build_number attribute $report_attr is $attr_status" ;;
esac
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
  # The Worker serves only these segments, and they need no escaping in
  # an S3 key or a signed request.
  [[ "$upload" == false || "$path" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] ||
    rejected "attachment path is not servable from the evidence Worker $encoded"
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

# --- the identity: <obs> hashes only the report's attribute and store path,
# so every build carrying this report, on any branch, maps to the same keys.

identity='[.identity.attribute, .identity.outPath]'
obs="$(jq -nj --arg attribute "$report_attr" --arg outPath "$report" \
  '[$attribute, $outPath] | tojson' | sha256sum | cut -c1-32)"
marker_key=""
[[ -z "$pr_number" ]] || marker_key="$key_root/ttl-30d/pr/$pr_number.json"

# --- temporary credentials, signed locally exactly as Cloudflare's
# r2/examples/authenticate-r2-temp-credentials: an HS256 JWT keyed by the
# parent secret, for one scope and prefix of this bucket for 15 minutes.
# Its secret is the JWT's SHA-256, its session token base64("jwt/" + JWT),
# its access key id the parent's. A run writes only its own tier (a pull
# request's ttl-30d also holds its marker), and a pull request reads ttl-90d
# read-only, so it can never write main's evidence.

# mint <scope> <prefix>: prints {secretAccessKey, sessionToken}. The parent
# secret reaches only this node process, through its own environment.
# shellcheck disable=SC2016 # JavaScript, not shell expansions
mint() {
  R2_PARENT_SECRET="$parent_secret" \
    MINT_ENDPOINT="$s3_endpoint" \
    MINT_ACCOUNT="$CLOUDFLARE_ACCOUNT_ID" \
    MINT_ACCESS_KEY_ID="$R2_EVIDENCE_ACCESS_KEY_ID" \
    MINT_BUCKET="$bucket" \
    MINT_SCOPE="$1" \
    MINT_PREFIX="$2" \
    node -e '
      const crypto = require("node:crypto");
      const env = process.env;
      const b64url = (data) => Buffer.from(data).toString("base64url");
      const iat = Math.floor(Date.now() / 1000);
      const claims = {
        bucket: env.MINT_BUCKET,
        scope: env.MINT_SCOPE,
        paths: { prefixPaths: [env.MINT_PREFIX], objectPaths: [] },
        sub: env.MINT_ACCOUNT,
        iss: env.MINT_ACCESS_KEY_ID,
        aud: new URL(env.MINT_ENDPOINT).host,
        iat,
        exp: iat + 900,
      };
      const input = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" })) + "." + b64url(JSON.stringify(claims));
      const jwt = input + "." +
        crypto.createHmac("sha256", Buffer.from(env.R2_PARENT_SECRET, "utf8")).update(input).digest("base64url");
      process.stdout.write(JSON.stringify({
        secretAccessKey: crypto.createHash("sha256").update(jwt).digest("hex"),
        sessionToken: Buffer.from("jwt/" + jwt).toString("base64"),
      }));
    '
}

# s3 <rw|ro> <response file> <key> <curl args...>: one request for <key>,
# SigV4 signed with that temporary credential, which reaches curl through
# its config on stdin rather than argv. Prints the HTTP status (000: none).
s3() {
  local secret token response=$2 key=$3
  case "$1" in
    rw) secret="$rw_secret" token="$rw_token" ;;
    ro) secret="$ro_secret" token="$ro_token" ;;
  esac
  shift 3
  curl -sS --config - --aws-sigv4 aws:amz:auto:s3 -o "$response" -w '%{http_code}' \
    "$@" "$s3_endpoint/$bucket/$key" <<EOF || :
user = "$R2_EVIDENCE_ACCESS_KEY_ID:$secret"
header = "x-amz-security-token: $token"
EOF
}

rw_secret="" rw_token="" ro_secret="" ro_token=""
if [[ "$upload" == true ]]; then
  credential="$(mint object-read-write "$key_root/$tier/")" || die "cannot sign a temporary R2 credential"
  rw_secret="$(jq -r '.secretAccessKey' <<<"$credential")"
  rw_token="$(jq -r '.sessionToken' <<<"$credential")"
  if [[ -n "$pr_number" ]]; then
    credential="$(mint object-read-only "$key_root/ttl-90d/")" || die "cannot sign a temporary R2 credential"
    ro_secret="$(jq -r '.secretAccessKey' <<<"$credential")"
    ro_token="$(jq -r '.sessionToken' <<<"$credential")"
  fi
  unset credential parent_secret
fi

# --- the baseline probe: a pull request's report already published from
# main (ttl-90d) is unaffected by the pull request and is not uploaded
# again; its destination is main's, where the report lives.

unaffected=false
if [[ "$upload" == true && -n "$pr_number" ]]; then
  baseline_key="$key_root/ttl-90d/v1/$obs/receipt.json"
  code="$(s3 ro /dev/null "$baseline_key" --head)"
  case "$code" in
    200)
      unaffected=true
      tier=ttl-90d
      ;;
    404) ;;
    *) die "baseline probe failed: HEAD $bucket/$baseline_key returned HTTP $code" ;;
  esac
fi

prefix="$key_root/$tier/v1/$obs/"
evidence_url="$evidence_host/${prefix#projects/}"
destination=null
if [[ "$upload" == true ]]; then
  destination="$(jq -nc --arg bucket "$bucket" --arg prefix "$prefix" --arg tier "$tier" --arg url "$evidence_url" \
    '{bucket: $bucket, prefix: $prefix, tier: $tier, url: $url}')"
fi

# --- the bundle: staged next to --out and renamed into place, so --out
# never holds a partial bundle or a receipt for rejected evidence; without
# --out it stages in the tmpdir.

if [[ -n "$out" ]]; then
  stage="$(mktemp -d "$out_parent/.publish-evidence.XXXXXX")"
else
  stage="$tmpdir/bundle"
  mkdir "$stage"
fi
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

# Nothing per build and no timestamp: the receipt is a function of the
# report and its destination, so every build carrying this report
# reproduces it byte for byte.
jq -n \
  --arg obs "$obs" \
  --arg attribute "$report_attr" \
  --arg outPath "$report" \
  --argjson provenance "$provenance" \
  --argjson verdict "$verdict" \
  --slurpfile files "$tmpdir/files.jsonl" \
  --argjson destination "$destination" \
  '{
    schemaVersion: 3,
    identity: {attribute: $attribute, outPath: $outPath},
    obs: $obs,
    attribute: $attribute,
    outPath: $outPath,
    reportProvenance: $provenance,
    verdict: {passed: $verdict.passed, counts: $verdict.counts},
    files: $files
  } + if $destination == null then {} else {destination: $destination} end' >"$stage/receipt.json"
chmod 0644 "$stage/receipt.json"
passed="$(jq -r '.verdict.passed' "$stage/receipt.json")"

# --- the local destination, checked before anything is uploaded.

changed=false
out_unchanged=false
if [[ -n "$out" ]]; then
  if [[ -e "$out/receipt.json" || -L "$out/receipt.json" ]]; then
    existing="$(jq -c "$identity" "$out/receipt.json" 2>/dev/null)" ||
      die "--out $out holds an unreadable receipt; refusing to overwrite it"
    [[ "$existing" == "$(jq -c "$identity" "$stage/receipt.json")" ]] ||
      die "--out $out holds the receipt of another publication $existing; refusing to overwrite it"
    diff -r "$stage" "$out" >/dev/null ||
      die "--out $out holds a different publication of report $obs; refusing to overwrite it"
    out_unchanged=true
  elif [[ -e "$out" || -L "$out" ]]; then
    [[ -d "$out" && ! -L "$out" && -z "$(find "$out" -mindepth 1 -print -quit)" ]] ||
      die "--out $out is neither empty nor a publication; refusing to overwrite it"
  fi
fi

# --- the upload, once per report and tier.

# A receipt already in the bucket is this publication's only when it is
# byte-identical; anything else is never overwritten.
check_remote_receipt() {
  cmp -s "$tmpdir/remote-receipt.json" "$stage/receipt.json" ||
    die "conflict: $bucket/$receipt_key holds a different receipt than this publication's; refusing to overwrite it"
}

if [[ "$upload" == true && "$unaffected" == false ]]; then
  receipt_key="${prefix}receipt.json"
  code="$(s3 rw "$tmpdir/remote-receipt.json" "$receipt_key")"
  case "$code" in
    200)
      check_remote_receipt
      ;;
    404)
      # Every file before the receipt, so a receipt in the bucket implies
      # its complete bundle; the receipt only where none exists.
      for path in "${files[@]}"; do
        case "$path" in
          *.png) content_type=image/png ;;
          *) content_type=application/json ;;
        esac
        code="$(s3 rw /dev/null "$prefix$path" --upload-file "$stage/$path" -H "Content-Type: $content_type")"
        [[ "$code" == 2?? ]] || die "upload failed: PUT $bucket/$prefix$path returned HTTP $code"
      done
      code="$(s3 rw /dev/null "$receipt_key" --upload-file "$stage/receipt.json" \
        -H "Content-Type: application/json" -H "If-None-Match: *")"
      case "$code" in
        2??)
          changed=true
          echo "PUBLISH-EVIDENCE: uploaded $evidence_url"
          ;;
        412)
          # A concurrent run wrote the receipt first.
          code="$(s3 rw "$tmpdir/remote-receipt.json" "$receipt_key")"
          [[ "$code" == 200 ]] || die "cannot read $bucket/$receipt_key: HTTP $code"
          check_remote_receipt
          ;;
        *) die "upload failed: PUT $bucket/$receipt_key returned HTTP $code" ;;
      esac
      ;;
    *) die "cannot read $bucket/$receipt_key: HTTP $code" ;;
  esac
fi

# rename(2) replaces an empty directory; a concurrent publisher that filled
# --out meanwhile makes it fail rather than merge.
if [[ -n "$out" && "$out_unchanged" == false ]]; then
  mv -T "$stage" "$out" || die "cannot move the publication into $out"
  stage=""
  changed=true
fi
if [[ "$unaffected" == true ]]; then
  echo "PUBLISH-EVIDENCE: unaffected (report $obs already published from main)"
fi
# An unaffected run without --out wrote nowhere and reports only that.
if [[ "$unaffected" == false || -n "$out" ]]; then
  if [[ "$changed" == true ]]; then
    echo "PUBLISH-EVIDENCE: published (report $obs, passed=$passed)"
  else
    echo "PUBLISH-EVIDENCE: unchanged (report $obs, passed=$passed)"
  fi
fi

# --- the pull request comment, upserted by marker through nixbot's task
# API (nixbot-pr-comment's protocol), so a retry edits the same comment.
# The API can only upsert, so the marker object records whether this
# program's comment is current: an affected run writes it current after
# commenting; an unaffected run replaces a current comment once with the
# superseded body. Two builds of one pull request finishing out of order
# race on the comment and marker; the run that finishes last wins.

if [[ "$upload" == true && -n "$pr_number" ]]; then
  if [[ "$unaffected" == true ]]; then
    code="$(s3 rw "$tmpdir/marker.json" "$marker_key")"
    case "$code" in
      200) ;;
      # No comment was ever posted: stay silent.
      404) exit 0 ;;
      *) die "cannot read $bucket/$marker_key: HTTP $code" ;;
    esac
    marker_state="$(jq -r 'if type == "object" and (.state == "current" or .state == "superseded") then .state else error("bad marker") end' \
      "$tmpdir/marker.json" 2>/dev/null)" || die "malformed marker $bucket/$marker_key"
    [[ "$marker_state" == current ]] || exit 0
    marker_state=superseded
  else
    marker_state=current
  fi
  if [[ -z "${NIXBOT_API_TOKEN:-}" ]]; then
    echo "PUBLISH-EVIDENCE: no comment on #$pr_number: NIXBOT_API_TOKEN is not set" >&2
    exit 0
  fi
  [[ "$NIXBOT_API_TOKEN" =~ ^[A-Za-z0-9._~+/=-]+$ ]] || die "malformed NIXBOT_API_TOKEN"
  if [[ "$marker_state" == superseded ]]; then
    {
      echo "### Browser evidence: superseded"
      echo
      echo "The latest build of this pull request produces the same docs report as \`main\` (report \`$obs\`), so the evidence previously linked here no longer describes a change. Build $build_number, rev \`${rev:0:12}\`."
    } >"$tmpdir/comment.md"
  else
    retention="${tier#ttl-}"
    {
      if [[ "$passed" == true ]]; then
        echo "### Browser evidence: passed"
      else
        echo "### Browser evidence: failed"
      fi
      echo
      echo "This pull request changes the docs site's browser evidence."
      echo
      # A build reused for a later head of an identical tree names both.
      reused_head=""
      [[ -z "$pr_head" || "$pr_head" == "$rev" ]] || reused_head="${pr_head:0:12}"
      jq -r --arg number "$build_number" --arg url "$build_event_url" --arg rev "${rev:0:12}" \
        --arg head "$reused_head" '
        "[build \($number)](\($url)) at `\($rev)`" +
        (if $head == "" then "" else " (reused for head `\($head)`, same tree)" end) + ": " +
        (.verdict.counts | "\(.expected) expected, \(.unexpected) unexpected, \(.flaky) flaky, \(.skipped) skipped.")
      ' "$stage/receipt.json"
      echo
      if [[ ${#screenshots[@]} -gt 0 ]]; then
        echo "Screenshots:"
        for path in "${screenshots[@]}"; do
          echo "- [$path]($evidence_url$path)"
        done
      else
        echo "No screenshots."
      fi
      echo
      echo "Receipt: [receipt.json](${evidence_url}receipt.json)"
      echo
      echo "No report identical to this one has been published from \`main\` in the last 90 days, so it is shown here."
      echo
      echo "Evidence kept ${retention%d} days."
    } >"$tmpdir/comment.md"
  fi
  jq -n --rawfile body "$tmpdir/comment.md" --arg marker "$comment_marker" \
    '{body: $body, marker: $marker}' >"$tmpdir/comment.json"
  code="$(curl -sS --config - -o "$tmpdir/comment.out" -w '%{http_code}' \
    -H "Content-Type: application/json" --data-binary "@$tmpdir/comment.json" \
    "$NIXBOT_API_URL/api/v1/pr-comment" <<EOF || :
header = "Authorization: Bearer $NIXBOT_API_TOKEN"
EOF
  )"
  [[ "$code" == 2?? ]] || die "comment on #$pr_number failed: HTTP $code"
  if [[ "$marker_state" == superseded ]]; then
    echo "PUBLISH-EVIDENCE: superseded #$pr_number"
  else
    echo "PUBLISH-EVIDENCE: commented #$pr_number"
  fi
  jq -nc --argjson pr "$pr_number" --arg state "$marker_state" --arg obs "$obs" \
    --argjson build "$build_number" --arg rev "$rev" --arg head "${pr_head:-$rev}" \
    '{schemaVersion: 1, pr: $pr, state: $state, obs: $obs, build: $build, rev: $rev, head: $head}' >"$tmpdir/marker.json"
  code="$(s3 rw /dev/null "$marker_key" --upload-file "$tmpdir/marker.json" -H "Content-Type: application/json")"
  [[ "$code" == 2?? ]] || die "marker update failed: PUT $bucket/$marker_key returned HTTP $code"
fi

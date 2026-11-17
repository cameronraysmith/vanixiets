# Body of the flake-update program (./flake-update.nix), which prepends
# `nixbot_flake_update`, the command running nixbot's vendored flake-update
# script with this repository's configuration, and the commit identity.
#
# Run in nixbot's checkout of the default branch by the registry's schedule
# entry point, which exports FLAKE_UPDATER_APP_ID and FLAKE_UPDATER_PRIVATE_KEY.
# It mints a one-hour installation token of the vanixiets-flake-updater App,
# narrowed to this repository with contents and pull_requests write, hands it
# to nixbot's script through a private secrets file, and revokes it on exit.
# The key exists on disk only until the JWT is signed; neither the key nor
# the variables holding it reach nixbot's script. Nothing is pushed unless a
# token was minted.

: "${FLAKE_UPDATER_APP_ID:?FLAKE_UPDATER_APP_ID is required}"
: "${FLAKE_UPDATER_PRIVATE_KEY:?FLAKE_UPDATER_PRIVATE_KEY is required}"

# The forge and repository behind origin, read as nixbot's script reads them.
origin="$(git config --get remote.origin.url)"
scheme="${origin%%://*}"
case "$scheme" in
  http | https) ;;
  *)
    echo "flake-update: origin is not an http(s) URL" >&2
    exit 1
    ;;
esac
rest="${origin#*://}"
authority="${rest%%/*}"
host="${authority##*@}"
slug="${rest#*/}"
slug="${slug%/}"
slug="${slug%.git}"
owner="${slug%%/*}"
repo="${slug#*/}"
unset origin rest authority
if [ "$scheme://$host" = https://github.com ]; then
  api=https://api.github.com
else
  api="$scheme://$host/api/v3"
fi

umask 077
private="$(mktemp -d)"
token=""
# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() {
  if [ -n "$token" ]; then
    curl -sS -o /dev/null --fail -X DELETE -H @"$private/token.header" "$api/installation/token" ||
      echo "flake-update: could not revoke the installation token; it expires within the hour" >&2
  fi
  rm -rf "$private"
}
trap cleanup EXIT

github() {
  curl -sS --fail-with-body \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "$@"
}

# gh-token signs locally and makes no request.
printf '%s\n' "$FLAKE_UPDATER_PRIVATE_KEY" >"$private/key.pem"
jwt="$(gh-token generate --jwt --duration 9 --app-id "$FLAKE_UPDATER_APP_ID" --key "$private/key.pem")"
rm -f "$private/key.pem"
unset FLAKE_UPDATER_APP_ID FLAKE_UPDATER_PRIVATE_KEY
printf 'Authorization: Bearer %s\n' "$jwt" >"$private/jwt.header"
unset jwt

if ! installation="$(github -H @"$private/jwt.header" "$api/repos/$owner/$repo/installation")"; then
  echo "flake-update: the App has no installation on $owner/$repo, or the lookup failed" >&2
  exit 1
fi
installation_id="$(printf '%s' "$installation" | jq -er '.id')"
request="$(jq -nc --arg repo "$repo" \
  '{repositories: [$repo], permissions: {contents: "write", pull_requests: "write"}}')"
if ! minted="$(github -X POST -H @"$private/jwt.header" -H 'Content-Type: application/json' \
  -d "$request" "$api/app/installations/$installation_id/access_tokens")"; then
  echo "flake-update: minting an installation token for $owner/$repo failed" >&2
  exit 1
fi
rm -f "$private/jwt.header"
token="$(printf '%s' "$minted" | jq -er '.token')"
unset minted
printf 'Authorization: Bearer %s\n' "$token" >"$private/token.header"

# The shape nixbot's script reads its token from.
printf '%s' "$token" | jq -Rc '{token: {data: {token: .}}}' >"$private/secrets.json"
export HERCULES_CI_SECRETS_JSON="$private/secrets.json"

status=0
"${nixbot_flake_update[@]}" || status=$?
exit "$status"

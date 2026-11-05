#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix yq-go gawk
# shellcheck shell=bash

set -euo pipefail

SOURCES="$(git rev-parse --show-toplevel)/pkgs/by-name/perses-bin/sources.json"
before="$(cat "$SOURCES")"

# Filter the release list to bare semver tags (vMAJOR.MINOR.PATCH) so that a
# pre-release cannot be mistaken for the latest release.
latest_tag="$(curl -fsSL -H 'Accept: application/vnd.github+json' \
  'https://api.github.com/repos/perses/perses/releases?per_page=100' \
  | jq -r '[.[] | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))] | .[0].tag_name')"
latest="${latest_tag#v}"
[[ -n "$latest" && "$latest" != null ]] || {
  echo "error: no semver release found" >&2
  exit 1
}

sums="$(curl -fsSL "https://github.com/perses/perses/releases/download/v${latest}/perses_${latest}_checksums.txt")"
sri() {
  local hex
  hex="$(awk -v f="perses_${latest}_$1.tar.gz" '$2 == f {print $1}' <<<"$sums")"
  [[ ${#hex} -eq 64 ]] || {
    echo "error: no checksum for $1" >&2
    exit 1
  }
  nix hash convert --hash-algo sha256 --to sri "$hex"
}
linux="$(sri linux_amd64)"
darwin="$(sri darwin_arm64)"

# The server is tested against the tag's pins, so they come from the tag, not
# from the newest plugin releases.
# shellcheck disable=SC2016  # $p is a yq variable, intentionally unexpanded by the shell
plugins="$(curl -fsSL "https://raw.githubusercontent.com/perses/perses/v${latest}/scripts/plugin/plugin.yaml" \
  | yq -o=json '[.[] | {(.name): .version}] | .[] as $p ireduce ({}; . * $p)')"

# One jq call writes the whole file, so the version and the hashes cannot be
# separated by a text edit that misses reformatted lines.
jq -n --arg v "$latest" --arg l "$linux" --arg d "$darwin" --argjson p "$plugins" \
  '{version: $v, hashes: {"x86_64-linux": $l, "aarch64-darwin": $d}, plugins: $p}' >"$SOURCES"

# The version and both hashes move together: all changed, or none did. The
# plugin pins are not compared, because a release may leave a pin unchanged.
jq -e -n --argjson a "$before" --slurpfile b "$SOURCES" '
  [($a.version != $b[0].version), ($a.hashes["x86_64-linux"] != $b[0].hashes["x86_64-linux"]), ($a.hashes["aarch64-darwin"] != $b[0].hashes["aarch64-darwin"])]
  | all or (any | not)' >/dev/null || {
  echo "error: a partial update: the version and the hashes did not all change, or all stay the same" >&2
  exit 1
}

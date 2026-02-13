#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert

set -euo pipefail

GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

version="$(curl -fsSL "${GCS_BUCKET}/latest")"
manifest="$(
  curl -fsSL "${GCS_BUCKET}/${version}/manifest.json" \
  | jq '{
    version,
    platforms: .platforms | with_entries(
      select(.key | test("^(darwin|linux)-(x64|arm64)$"))
      | {
        key,
        value: { checksum: .value.checksum }
      }
    )
  }'
)"
echo "$manifest" > ./manifest.json

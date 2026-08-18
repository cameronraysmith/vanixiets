#!/bin/bash
set -euo pipefail
mkdir -p /logs/verifier
if grep -qx 'HARBORIZE-CANARY-9F3A21' /logs/verifier/canary-output.txt; then
  echo 1 > /logs/verifier/reward.txt
else
  echo 0 > /logs/verifier/reward.txt
fi

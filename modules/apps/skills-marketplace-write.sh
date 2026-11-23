#!/usr/bin/env bash
# shellcheck shell=bash
#
# Writes the generated marketplace and skills.sh files (the skills-marketplace package,
# $SKILLS_MARKETPLACE) into the repository root, where
# checks.x86_64-linux.skills-marketplace-drift compares them with a fresh build.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
for file in .claude-plugin/marketplace.json .github/plugin/marketplace.json skills.sh.json; do
  install -D -m 0644 "${SKILLS_MARKETPLACE}/${file}" "${repo_root}/${file}"
  echo "skills-marketplace-write: wrote ${file}"
done

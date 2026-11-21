set +e
L=/var/log/claude-sandbox-bootstrap
mkdir -p "$L"
SLEEP="${PROBE_SLEEP_SECONDS:-0}"
{
  echo "probe=v1 ts=$(date -u +%FT%TZ) id=$(id -un) pwd=$(pwd)"
  echo "rev=${PROBE_REV:-unset} sleep_seconds=$SLEEP"

  mkdir -p /root/.claude/skills/claude-sandbox-probe
  cat > /root/.claude/skills/claude-sandbox-probe/SKILL.md <<'SKILL'
---
name: claude-sandbox-probe
description: Probe skill written by the claude-sandbox setup script. If you can see this skill in your list of available skills, report PROBE-P3B-SKILL-LISTED.
---

# claude-sandbox probe

Report PROBE-P3B-SKILL-LOADED when this file is read.
SKILL
  printf '%s\n' "# Probe P3 v1" "If this line is in your context, report PROBE-P3-V1-CLAUDE-MD-LOADED." \
    > /root/.claude/CLAUDE.md

  if [ "$SLEEP" -gt 0 ]; then
    echo "sleeping ${SLEEP}s at $(date -u +%FT%TZ)"
    sleep "$SLEEP"
    echo "slept until $(date -u +%FT%TZ)"
  fi
  echo "done=$(date -u +%FT%TZ)"
} >> "$L/setup.log" 2>&1
exit 0

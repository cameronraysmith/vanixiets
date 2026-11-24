Daily PR summary for {{REPO}} covering {{START}} to {{END}}
(America/New_York). If START/END are still placeholders, use the 24 hours ending now.
If REPO is still a placeholder, use the current repository
(`gh repo view --json nameWithOwner -q .nameWithOwner`).

1. List the PRs created in the interval, with the same columns as my `gh prs` alias,
   forcing full-width output so titles are not truncated:
   GH_FORCE_TTY=260 NO_COLOR=1 PAGER=cat gh prs --repo REPO --state all --limit 200 \
     --search "created:START..END" | sed 's/\x1b\[[0-9;]*m//g'
   (START/END as ISO 8601 with offset, e.g. 2026-11-24T00:00:00-05:00.)
   If `gh alias list` has no `prs` entry, define it first:
   gh alias set prs - <<'EOF'
   pr list --json number,title,headRefName,state,createdAt --template '{{tablerow "ID" "STATE" "TITLE" "BRANCH" "CREATED AT"}}{{range .}}{{tablerow (printf "#%v" .number | autocolor "green") (.state | autocolor "cyan") .title (.headRefName | autocolor "cyan") (timeago .createdAt)}}{{end}}{{tablerender}}'
   EOF
   Print the table verbatim in a ```text block (ID, STATE, TITLE, BRANCH, CREATED AT).
   Also list separately any PR that was merged in the interval but created before it
   (same command with `--search "merged:START..END"`, minus the first set).
2. Summarize from the titles, adding `gh pr view <N> --repo REPO` only where a title is ambiguous:
   - Group by theme (one bold heading per theme, numbered), not by PR order.
   - Under each theme, put terse bullets that cite PR numbers inline; merge related PRs into one bullet.
   - Call out completed or archived OpenSpec changes and Linear IDs (CAM-*) when titles name them.
   - Keep renovate/dependency bumps on one line under Misc.
   - State the count and how many merged, open, or closed; list any not merged by name.
   - End with one line saying the summary comes from titles alone, or what was read beyond them.
   - No closing summary or recap.

### Task 8: Close-out and integration verification

Implements `tasks.md` 6.1–6.3 and 7.1.
Close-out pull request.

**Files:**
- Create: this change's `verify.md`, `retrospective.md`
- Modify: this change's `specs/world-assumptions/spec.md` (rebase only)
- Modify at archive: `openspec/specs/**`, `packages/docs/src/content/docs/development/traceability/satisfaction.md`

**Interfaces:**
- Consumes: every evidence log of Tasks 1 to 7.
- Produces: the archived change and the synced main specs.

- [ ] **Step 1: End-to-end reading (tasks.md 7.1)**

Gated, the operator: open `fleet-hosts` with the last 15 min and all hosts, and state the latest memory point's time per host.
At the same minute, on magnetite:

```bash
ssh magnetite.zt 'bash -s' <<'EOF' | tee logs/cam73-evidence/7.1-end-to-end-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
P=$(sudo cat /run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password)
curl -s -u "regulator:$P" -H 'x-greptime-db-name: fleet' \
  --data-urlencode 'query=count by (host_name) (system_memory_usage_bytes)' \
  http://127.0.0.1:4000/v1/prometheus/api/v1/query | jq -c '.data.result[] | {host: .metric.host_name, n: .value[1]}'
EOF
```

The password is read into a shell variable on magnetite and never printed; if the runbook names another way to read as `regulator`, use it.

Expected: the hosts the view shows equal the hosts the query returns; stibnite is absent until CAM-72.

- [ ] **Step 2: verify.md (tasks.md 6.1)**

Invoke `openspec-verify-change` and fill `verify.md`: per requirement, its discharge and evidence log; each check's cost before and after; the designation lint of `fleet-dashboard`'s six requirements against the `world-assumptions` table; the trust boundary as its scenarios give it.

Run: `openspec validate serve-the-fleet-dashboard --strict`; and `rg -o "(FD|FDI|TS|TSI|WA) \`[^\`]+\`" tasks.md | sort -u` against `verify.md`.

Expected: valid; every quoted requirement appears in `verify.md`.

- [ ] **Step 3: Rebase the designation table (tasks.md 6.2)**

If `watch-the-alert-path-externally` has archived, retake this delta's `Grounded vocabulary for behavioral requirements` block from main and add this change's seven rows (`dashboard service`, `view`, `chart`, `dashboard group`, `admitted person`, `identity provider`, `browser`).

Run: `LC_ALL=C comm -23 <(rg '^\|' openspec/specs/world-assumptions/spec.md | sort) <(rg '^\|' openspec/changes/serve-the-fleet-dashboard/specs/world-assumptions/spec.md | sort)`

Expected: no output.

- [ ] **Step 4: Archive (tasks.md 6.3)**

Invoke `openspec-archive-change`: sync the deltas, regenerate `satisfaction.md` wholesale, move the folder, open the close-out pull request.

Run: `rg -n 'perses\.scientistexperience' openspec/specs packages/docs/src/content/docs/development/traceability/satisfaction.md`

Expected: no output.

### Task 5: Documentation and decision records

Implements `tasks.md` 5.1–5.3 (design "Implementation surface: artifacts amended when ADR-009 Q5 resolves"; FAI `This capability states its own trust boundary`).
This is pull request 2, started after Task 4 Step 5 so that the documents state observed behaviour.
Every file here is prose: one sentence per line, plain declarative English, durable identifiers only (ADR numbers, file paths, CAM numbers, pull-request numbers), per `skill://preferences-prose-clarity`.

**Files:**
Line numbers are those at `origin/main` `79d5cee3`; each is located by the quoted phrase design "Implementation surface" gives for it, and a line that has moved is found by that phrase.
- Modify: `packages/docs/src/content/docs/development/operations/fleet-observability.md:145-146` ("Nothing reports an outage of ntfy or cinnabar themselves"), `:825` ("an external watch of cinnabar and ntfy themselves (CAM-76)"), and a new section after "Reading failure notices"
- Modify: `docs/notes/development/observability/decisions/ADR-009-alerting.md:7-9` ("except Q5, deferred to the end of implementation"), `:182` ("deferred to Q5."), `:194-195` ("nothing in this decision detects that (Q5)"), "Operating envelope and regulator" (after E9.5), "Failure prevented", "Implementation surface", `:265-267` ("5. Q5: Should cinnabar itself be watched")
- Modify: `docs/notes/development/observability/components/fleet-alert.md:32`, `:164-169`
- Modify: `docs/notes/development/observability/architecture/reference-architecture.md:73`, `:182-183`, `:280-281`, `:286`
- Modify: `docs/notes/development/observability/README.md:19`, `:35`, `:130`, `:143`, `:215` (each "Q5")
- Modify: `docs/notes/development/observability/charter.md` (status, date and version lines; the next version entry)

**Interfaces:**
- Consumes: the recorded times of Task 4 Steps 4 and 5; design D1–D7 and O1–O6.
- Produces: the corpus Task 6 cites and the archive's spec sync relies on.

- [ ] **Step 1: The runbook (tasks.md 5.1)**

Replace the runbook's `:145-146` with:

```markdown
An outage of ntfy or cinnabar themselves is reported by email from healthchecks.io, outside the fleet.
cinnabar's `fleet-deadman` pings the check `fleet-deadman cinnabar` at the end of each 5-minute run that found ntfy refusing anonymous heartbeats, a heartbeat from magnetite in the last 10 minutes, and every alert it raised posted.
When no ping arrives for the check's 5-minute period plus its 10-minute grace, healthchecks.io emails the operator, and it emails again when pings resume.
An email together with `FAILED fleet-deadman on cinnabar` on `fleet-alerts` means the alert path works and only the ping to `hc-ping.com` failed; an email with nothing on `fleet-alerts` means the alert path is down.
```

Add a section `## The external watch` after "Reading failure notices", with these paragraphs, one sentence per line:

```markdown
## The external watch

The check's period, grace and email integration are set in healthchecks.io's web interface, not in the repository; the values in force are period 5 minutes, grace 10 minutes and one email integration.
For maintenance that stops ntfy, caddy or zerotierone on cinnabar, or magnetite's evaluator, for longer than 10 minutes, pause the check in healthchecks.io after the dead-man's last `external ping accepted` and within 15 minutes of it.
For maintenance of magnetite's evaluator, that last ping comes up to 10 minutes after the evaluator stops, because the dead-man pings while a heartbeat is still in its window.
A ping to a paused check resumes it, so the first ping after the maintenance resumes the check by itself.
The ping URL is a credential: anyone holding it can keep the check up.
It lives only in the clan vars generator `fleet-deadman-ping` on cinnabar and reaches curl on stdin.
To rotate it, create a new check with the same settings, run `clan vars generate cinnabar --generator fleet-deadman-ping` and enter the new URL at the hidden prompt, commit the vars, deploy cinnabar, confirm pings on the new check, and delete the old one.
```

Change `:825`'s clause "and an external watch of cinnabar and ntfy themselves (CAM-76)" to name CAM-76 as landed.
Run `rg -n 'healthchecks|fleet-deadman-ping|pause' packages/docs/src/content/docs/development/operations/fleet-observability.md`.

Expected: each term appears.

- [ ] **Step 2: The decision records (tasks.md 5.2)**

Make these amendments in place, each sentence on its own line:

- ADR-009 `:7-9`: drop "except Q5, deferred to the end of implementation" from the status line and add "Amended in place under charter v27: Q5 is resolved by CAM-76 (`openspec/changes/watch-the-alert-path-externally/`)."
- ADR-009 `:182` ("deferred to Q5."): replace the entry with "A hosted dead-man service watching cinnabar: adopted under Q5 as healthchecks.io, pinged by `fleet-deadman` (charter v27)." and move the adopted design into Decision as a new item stating D2's ping conditions, D3's silence on failure, O2's email-only channel and O5's period and grace.
- ADR-009 `:194-195` ("nothing in this decision detects that (Q5)"): "cinnabar is the single delivery path for alerts: while cinnabar or its ntfy is down no alert reaches a human, and healthchecks.io emails the operator once the dead-man's pings have been missing for the check's 5-minute period plus its 10-minute grace (Q5, CAM-76)." and "The watch adds a third-party account, an egress from cinnabar to `hc-ping.com` and one secret, and it fails together with the fleet if an outage takes healthchecks.io down with cinnabar (accepted 2026-11-01)."
- ADR-009 "Operating envelope and regulator", after E9.5: E9.6 and R9.6 exactly as design D7 states them, with "shown able to fail by `deadmanPingFirst`, `deadmanPingNoHeartbeat`, `deadmanPingBeforePosts`, `pingAcceptsAny200` and `pingPrintsConfig`, and at acceptance by stopping ntfy on cinnabar".
- ADR-009 "Failure prevented": "- External watch: an outage of cinnabar, ntfy, caddy or the mesh path is read as a quiet fleet for up to a week."
- ADR-009 "Implementation surface": the option `services.fleet-alert.deadman.pingConfigFile`, `flake.lib.fleetDeadmanPing` and the per-machine generator `fleet-deadman-ping` on cinnabar; `:253`'s "no new listener" stays.
- ADR-009 `:265-267` ("5. Q5: Should cinnabar itself be watched"): append "Resolution: decided by the operator on 2026-11-01 under CAM-76: yes, healthchecks.io, pinged by the dead-man after a passing run with a heartbeat, emailing the operator (charter v27)."
- `components/fleet-alert.md:32`: every ADR-009 question is now answered; `:164-169`: remove the Deferred entry and add the watch to the component's Placement and Configuration surface.
- `architecture/reference-architecture.md:73`: `ext["healthchecks.io check"]` with `deadman -->|"ping after a passing run"| ext` and `ext -->|"email"| human`; `:182-183`, `:280-281`, `:286`: the watch is in place and CAM-72 is unblocked.
- `README.md:19` ("schedules ADR-009 Q5 as CAM-76"), `:35` ("ADR-009 is Accepted except its Q5"), `:130` ("ADR-009 with its Q5 deferred to CAM-76"), `:143` ("Accepted, except Q5, deferred to CAM-76 before S5"), `:215` ("ADR-009 Q5, whether an external dead-man service watches cinnabar itself"): ADR-009 is Accepted with Q5 resolved by CAM-76.
- `charter.md`: the next version entry, v27 (the charter is at v26, `charter.md:9`), in v24's form, "the decisions of CAM-76 (`openspec/changes/watch-the-alert-path-externally/`), the operator's O1 to O6; no earlier text is edited beyond the status, date and version lines, and this charter's D1–D9, the requirements and the acceptance criteria are unchanged", with one sub-bullet listing the amendments above.

Run:

```bash
rg -n 'ADR-009 Q5|except Q5|its Q5|deferred to Q5' docs/notes/development/observability | rg -i defer | rg -v '/charter\.md:'
rg -n 'E9.6|R9.6' docs/notes/development/observability/decisions/ADR-009-alerting.md
```

Expected: the first prints nothing, since the charter's version entries are history and are excluded; the second prints both.

- [ ] **Step 3: Format and open pull request 2 (tasks.md 5.3)**

```bash
nix fmt 2>&1 | tee logs/cam76-evidence/5.3-fmt-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix fmt -- --fail-on-change
```

Expected: exit 0.
Commit as `Record the external watch of cinnabar's alert path in the observability decisions and runbook`, open pull request 2 with that title, and enqueue it once nixbot is green.

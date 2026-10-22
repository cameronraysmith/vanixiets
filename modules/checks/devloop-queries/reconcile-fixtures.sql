-- devloop-reconcile's PostgreSQL side (S2 design D11, tasks.md 4.1), over the
-- window [2026-10-20 00:00, 2026-10-21 00:00) UTC that clockVars'
-- window_start and window_end name. Ids from 9100 keep these rows apart from
-- fixtures.sql, whose rows lie within 30 minutes of the build's clock, after
-- the window. Loaded as postgres after fixtures.sql.
INSERT INTO projects (id, forge, forge_repo_id, owner, name, default_branch, url)
  OVERRIDING SYSTEM VALUE
  VALUES (9100, 'gitea', 'reconcile-fixture', 'reconcile', 'fixture', 'main', 'https://gitea.invalid/reconcile/fixture');
INSERT INTO builds (id, project_id, number, commit_sha, branch, pr_number, status, created_at, started_at, finished_at)
  OVERRIDING SYSTEM VALUE
  VALUES
    -- a pull-request build inside the window
    (9101, 9100, 1, 'c9101', 'pr-41', 41, 'succeeded', '2026-10-20T09:00:00Z', '2026-10-20T09:01:00Z', '2026-10-20T10:00:00.123456Z'),
    -- a merge-queue batch build inside the window
    (9102, 9100, 2, 'c9102', 'gitea-mq/batch/7', NULL, 'succeeded', '2026-10-20T10:30:00Z', '2026-10-20T10:31:00Z', '2026-10-20T11:00:00Z'),
    -- a batch build finishing exactly at the window's end, which is outside it
    (9103, 9100, 3, 'c9103', 'gitea-mq/batch/8', NULL, 'succeeded', '2026-10-20T23:00:00Z', '2026-10-20T23:01:00Z', '2026-10-21T00:00:00Z'),
    -- a build finishing one microsecond before the window
    (9104, 9100, 4, 'c9104', 'main', NULL, 'succeeded', '2026-10-19T23:00:00Z', '2026-10-19T23:01:00Z', '2026-10-19T23:59:59.999999Z'),
    -- a build finishing exactly at the window's start, which is inside it
    (9106, 9100, 6, 'c9106', 'main', NULL, 'succeeded', '2026-10-19T23:30:00Z', '2026-10-19T23:31:00Z', '2026-10-20T00:00:00Z');
INSERT INTO build_attributes (build_id, attr, status, cached, finished_at)
  VALUES
    (9101, 'checks.x86_64-linux.a', 'succeeded', false, '2026-10-20T10:00:00.123456Z'),
    (9101, 'checks.x86_64-linux.cached', 'skipped_local', true, '2026-10-20T10:00:00.123456Z'),
    -- restarted after the window and finished again
    (9102, 'checks.x86_64-linux.restarted', 'succeeded', false, '2026-10-21T00:30:00Z'),
    -- restarted and not finished again
    (9102, 'checks.x86_64-linux.running', 'building', false, NULL),
    (9104, 'checks.x86_64-linux.old', 'succeeded', false, '2026-10-19T23:59:59.999999Z'),
    -- finished exactly at the window's start, which is inside it
    (9106, 'checks.x86_64-linux.midnight', 'succeeded', false, '2026-10-20T00:00:00Z');

-- Fixture rows for checks.x86_64-linux.devloop-queries (design D14), loaded as
-- postgres after the nixbot input's migrations and the rendered grants. Every
-- time is relative to fixture_clock.t0, the load time truncated to the
-- second, so the export queries' `now() - interval '5 minutes'` sees the rows
-- at the ages the assertions name. fixture_clock is not one of the three
-- dumped tables and no reader is granted it.
CREATE TABLE fixture_clock AS SELECT date_trunc('second', now()) AS t0;

INSERT INTO projects (id, forge, forge_repo_id, owner, name, default_branch, url)
OVERRIDING SYSTEM VALUE
VALUES (1, 'gitea', '1', 'sciexp', 'vanixiets', 'main', 'https://gitea.example/sciexp/vanixiets');

INSERT INTO builds (id, project_id, number, commit_sha, branch, pr_number, status, created_at, started_at, finished_at, eval_duration_ms)
OVERRIDING SYSTEM VALUE
SELECT v.id, 1, v.number, v.commit_sha, v.branch, v.pr_number, v.status,
       c.t0 - v.created_ago, c.t0 - v.started_ago, c.t0 - v.finished_ago, v.eval_duration_ms
FROM fixture_clock c,
     (VALUES
       -- finished exactly at the old cursor: a row tied with the cursor
       (101, 1, '1111111111111111111111111111111111111111', 'pr-42', 42::bigint, 'succeeded',
        interval '30 minutes', interval '29 minutes', interval '10 minutes', 1234::bigint),
       -- finished 4 minutes ago, never started, no pull request
       (102, 2, '2222222222222222222222222222222222222222', 'gitea-mq/batch/7', NULL, 'failed',
        interval '20 minutes', NULL, interval '4 minutes', NULL),
       -- finished 7 minutes ago
       (103, 3, '3333333333333333333333333333333333333333', 'main', NULL, 'succeeded',
        interval '15 minutes', interval '14 minutes', interval '7 minutes', 10),
       -- not finished
       (104, 4, '4444444444444444444444444444444444444444', 'main', NULL, 'building',
        interval '2 minutes', interval '1 minute', NULL, NULL)
     ) AS v (id, number, commit_sha, branch, pr_number, status, created_ago, started_ago, finished_ago, eval_duration_ms);

INSERT INTO build_attributes (build_id, attr, system, drv_path, outputs, status, cached, error, started_at, finished_at, eval_wall_ms, eval_alloc_bytes)
SELECT v.build_id, v.attr, 'x86_64-linux', v.drv_path, v.outputs::jsonb, v.status, v.cached, v.error,
       c.t0 - v.started_ago, c.t0 - v.finished_ago, v.eval_wall_ms, v.eval_alloc_bytes
FROM fixture_clock c,
     (VALUES
       -- the abandonment marker, as modules/nixos/nixbot-abandon-optional-attributes.patch writes it
       (101, 'checks.x86_64-linux.marker', '/nix/store/aaaa-marker.drv', '{"out": "/nix/store/aaaa-marker"}',
        'ignored_failure', false, 'not finished when the required attributes had settled',
        interval '11 minutes', interval '10 minutes', 5, 1048576::bigint),
       -- other error text, no outputs
       (101, 'checks.x86_64-linux.other-ignored', '/nix/store/bbbb-other.drv', NULL,
        'ignored_failure', false, 'error: builder for /nix/store/bbbb-other.drv failed with exit code 1',
        interval '11 minutes', interval '10 minutes', NULL, NULL),
       -- a null error, finished 4 minutes ago
       (101, 'checks.x86_64-linux.null-error', '/nix/store/cccc-null.drv', '{"out": "/nix/store/cccc-null"}',
        'ignored_failure', true, NULL,
        NULL, interval '4 minutes', NULL, NULL),
       -- the marker inside longer text: abandoned only under a pattern match
       (101, 'checks.x86_64-linux.marker-in-text', '/nix/store/gggg-in-text.drv', NULL,
        'ignored_failure', false, 'abandoned: not finished when the required attributes had settled (retry 2)',
        interval '11 minutes', interval '10 minutes', NULL, NULL),
       -- the exact marker on a failed row: abandoned only without the status condition
       (101, 'checks.x86_64-linux.failed-marker', '/nix/store/hhhh-failed.drv', NULL,
        'failed', false, 'not finished when the required attributes had settled',
        interval '11 minutes', interval '10 minutes', NULL, NULL),
       (102, 'checks.x86_64-linux.recent', '/nix/store/dddd-recent.drv', '{"out": "/nix/store/dddd-recent"}',
        'succeeded', true, NULL,
        interval '5 minutes', interval '4 minutes', 7, 2097152),
       (103, 'checks.x86_64-linux.old', '/nix/store/eeee-old.drv', '{"out": "/nix/store/eeee-old"}',
        'failed', false, 'boom',
        interval '8 minutes', interval '7 minutes', 9, 4194304),
       (104, 'checks.x86_64-linux.unfinished', '/nix/store/ffff-unfinished.drv', NULL,
        'building', false, NULL,
        interval '1 minute', NULL, NULL, NULL)
     ) AS v (build_id, attr, drv_path, outputs, status, cached, error, started_ago, finished_ago, eval_wall_ms, eval_alloc_bytes);

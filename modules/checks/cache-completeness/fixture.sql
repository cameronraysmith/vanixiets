-- Builds for checks.x86_64-linux.cache-completeness, on nixbot's own schema.
-- The probe's since is 10 hours ago and it settles for an hour: only build 1
-- and build 7, pushes to the default branch finished in that window, count,
-- and of their outputs only missing-1 is not served.
INSERT INTO projects (forge, forge_repo_id, owner, name, url, default_branch)
VALUES ('gitea', '1', 'owner', 'repo', 'https://forge/owner/repo', 'main');

INSERT INTO builds (project_id, number, commit_sha, branch, pr_number, finished_at) VALUES
(1, 1, 'aaaa', 'main', NULL, now() - interval '2 hours'),
-- still settling
(1, 2, 'bbbb', 'main', NULL, now() - interval '20 minutes'),
-- before since
(1, 3, 'cccc', 'main', NULL, now() - interval '12 hours'),
-- a pull request
(1, 4, 'dddd', 'feature', 7, now() - interval '2 hours'),
-- a push to another branch: a gitea-mq batch
(1, 5, 'eeee', 'gitea-mq/batch/1', NULL, now() - interval '2 hours'),
-- still running
(1, 6, 'ffff', 'main', NULL, NULL),
(1, 7, 'gggg', 'main', NULL, now() - interval '90 minutes');

INSERT INTO build_attributes (build_id, attr, system, status, outputs) VALUES
(1, 'served-1', 'x86_64-linux', 'succeeded',
  '{"out": "/nix/store/00000000000000000000000000000001-served-1"}'),
(1, 'missing-1', 'aarch64-darwin', 'skipped_local',
  '{"out": "/nix/store/00000000000000000000000000000002-missing-1"}'),
-- failed: nothing to serve
(1, 'failed', 'x86_64-linux', 'failed',
  '{"out": "/nix/store/00000000000000000000000000000005-failed"}'),
-- buildDependenciesOnly: no output recorded
(1, 'depsonly', 'x86_64-linux', 'succeeded', NULL),
(2, 'settling', 'x86_64-linux', 'succeeded',
  '{"out": "/nix/store/00000000000000000000000000000003-settling"}'),
(3, 'history', 'x86_64-linux', 'skipped_local',
  '{"out": "/nix/store/00000000000000000000000000000004-history"}'),
(4, 'pull-request', 'x86_64-linux', 'skipped_local',
  '{"out": "/nix/store/00000000000000000000000000000006-pull-request"}'),
(5, 'batch', 'x86_64-linux', 'skipped_local',
  '{"out": "/nix/store/00000000000000000000000000000007-batch"}'),
(6, 'running', 'x86_64-linux', 'skipped_local',
  '{"out": "/nix/store/00000000000000000000000000000008-running"}'),
-- served-1 again, in a later build
(7, 'served-1', 'x86_64-linux', 'skipped_local',
  '{"out": "/nix/store/00000000000000000000000000000001-served-1"}');

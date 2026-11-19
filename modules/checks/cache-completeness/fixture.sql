-- Builds for checks.x86_64-linux.cache-completeness, on nixbot's own schema.
-- The probe's since is 10 hours ago and it settles for an hour: only build 1
-- and build 7, builds that reached the default branch and finished in that
-- window, count, and of their outputs only missing-1 is not served.
INSERT INTO projects (forge, forge_repo_id, owner, name, url, default_branch)
VALUES ('gitea', '1', 'owner', 'repo', 'https://forge/owner/repo', 'main');

INSERT INTO builds (project_id, number, commit_sha, branch, pr_number, merged_pr_number, finished_at) VALUES
-- a pull request's build that the default branch's push reused after a
-- fast-forward: nixbot moved its row to the branch and cleared pr_number,
-- as build 2820 (#2726) reads
(1, 1, 'aaaa', 'main', NULL, 4057, now() - interval '2 hours'),
-- still settling
(1, 2, 'bbbb', 'main', NULL, NULL, now() - interval '20 minutes'),
-- before since
(1, 3, 'cccc', 'main', NULL, NULL, now() - interval '12 hours'),
-- a pull request that has not landed
(1, 4, 'dddd', 'feature', 7, NULL, now() - interval '2 hours'),
-- a push to another branch: a gitea-mq batch not reused for the branch
(1, 5, 'eeee', 'gitea-mq/batch/1', NULL, NULL, now() - interval '2 hours'),
-- still running
(1, 6, 'ffff', 'main', NULL, NULL, NULL),
(1, 7, 'gggg', 'main', NULL, NULL, now() - interval '90 minutes');

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

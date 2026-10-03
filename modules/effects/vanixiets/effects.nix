# The vanixiets effects, interpreted by ./registry.nix.
#
# docs is one program in three runs. Its event runs are onEvent effects,
# which nixbot evaluates from the default branch, so the program comes from
# main and the pull request contributes data only. pullRequest sets no nixbot
# `when.permission`: bots such as renovate report no permission though their
# head branches live here, and `when` cannot express "same repository or a
# writer", so the program applies that rule itself; approval of an outside
# pull request is sticky across later pushes, and a preview publishes its
# content with our token. pullRequestClosed tears the pull request's Preview
# down; it shares the per-pull-request lock ({pr} is nixbot's expansion to the
# number) so teardown waits for an in-flight upload rather than racing it.
#
# release-packages publishes from main with the release PAT. Its pullRequest
# run is the release plan: the same program forecasts what merging would
# release, with main's files and only nixbot's read-only forge token, so the
# PAT never reaches a pull request run. Its lock is per pull request, apart
# from the release lock, so a forecast never waits on a release.
#
# browser-evidence uploads the docs browser report nixbot built into R2 under
# per-run temporary credentials, keyed by the report's attribute and output
# path so each tier receives a report once. It runs once per settled pull
# request build: nixbot delivers pull_request after every succeeded build,
# fresh or reused for a head with an identical tree, and build_finished only
# when a build finishes, so pullRequest serves succeeded builds and
# buildFinished, filtered to failed, serves failed ones (and failed builds
# outside a pull request). A reused failed build delivers neither, so a head
# that reuses a failed build gets no evidence run: a known gap. Neither
# trigger sets `when.permission`, which max(actor, author) satisfies and bots
# such as renovate fail; trust is nixbot's CI approval, which holds an
# outside pull request until approved, and the run executes main's code on
# the built report, never the pull request's. A pull request whose report
# main already published (probed read-only in ttl-90d) uploads and comments
# nothing, superseding any earlier comment; otherwise it uploads to ttl-30d,
# writable only there, and comments. All three runs share one lock, so a
# pull request's failed and later succeeded builds never upload or comment
# concurrently; a {pr} lock would not do, since nixbot skips it on an event
# without a pull request. Under it main resolves the build for `--rev` itself.
{ withSystem, ... }:
{
  vanixiets.effects = withSystem "x86_64-linux" (
    { config, ... }:
    {
      docs = {
        program = config.apps.deploy-docs.program;
        rehearsals = [ config.checks.deploy-docs-rehearsal ];
        triggers =
          let
            secrets = [
              "CLOUDFLARE_API_TOKEN"
              "CLOUDFLARE_ACCOUNT_ID"
            ];
          in
          {
            main = {
              args = [ "production" ];
              lock = "deploy-docs";
              inherit secrets;
            };
            pullRequest = {
              args = [ "pull-request" ];
              lock = "docs-preview-{pr}";
              forgeToken = true;
              inherit secrets;
            };
            pullRequestClosed = {
              args = [ "pull-request-closed" ];
              lock = "docs-preview-{pr}";
              inherit secrets;
            };
          };
      };

      browser-evidence = {
        program = config.apps.publish-evidence.program;
        rehearsals = [ config.checks.publish-evidence-rehearsal ];
        triggers =
          let
            secrets = [
              "R2_EVIDENCE_ACCESS_KEY_ID"
              "R2_EVIDENCE_SECRET_ACCESS_KEY"
              "CLOUDFLARE_ACCOUNT_ID"
            ];
          in
          {
            pullRequest = {
              args = [
                "event"
                "--upload"
              ];
              lock = "browser-evidence";
              inherit secrets;
            };
            buildFinished = {
              args = [
                "event"
                "--upload"
              ];
              lock = "browser-evidence";
              inherit secrets;
              when.status = [ "failed" ];
            };
            main = {
              args = [
                "main"
                "--upload"
              ];
              lock = "browser-evidence";
              inherit secrets;
            };
          };
      };

      release-packages = {
        program = config.apps.release-packages.program;
        rehearsals = [ config.checks.release-rehearsal ];
        triggers = {
          main = {
            secrets = [ "GITHUB_TOKEN" ];
            lock = "release-packages";
          };
          pullRequest = {
            args = [ "plan" ];
            secrets = [ ];
            forgeToken = true;
            lock = "release-plan-{pr}";
          };
        };
      };
    }
  );
}

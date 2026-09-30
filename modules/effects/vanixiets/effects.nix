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

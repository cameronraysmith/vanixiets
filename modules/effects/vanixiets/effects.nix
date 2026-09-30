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
{ withSystem, ... }:
{
  vanixiets.effects = withSystem "x86_64-linux" (
    { config, ... }:
    {
      docs = {
        program = config.apps.deploy-docs.program;
        secrets = [
          "CLOUDFLARE_API_TOKEN"
          "CLOUDFLARE_ACCOUNT_ID"
        ];
        rehearsals = [ config.checks.deploy-docs-rehearsal ];
        triggers = {
          main = {
            args = [ "production" ];
            lock = "deploy-docs";
          };
          pullRequest = {
            args = [ "pull-request" ];
            lock = "docs-preview-{pr}";
            forgeToken = true;
          };
          pullRequestClosed = {
            args = [ "pull-request-closed" ];
            lock = "docs-preview-{pr}";
          };
        };
      };

      release-packages = {
        program = config.apps.release-packages.program;
        secrets = [ "GITHUB_TOKEN" ];
        rehearsals = [ config.checks.release-rehearsal ];
        triggers.main.lock = "release-packages";
      };
    }
  );
}

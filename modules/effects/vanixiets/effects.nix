# The vanixiets effects, interpreted by ./registry.nix.
#
# docs-preview runs as a pull_request event effect, which nixbot evaluates
# from the default branch, so its program comes from main and the pull request
# contributes data only. Its lock serialises runs per pull request, and a
# writer must have pushed or authored the pull request: approval of an outside
# pull request is sticky across later pushes, and a preview publishes its
# content with our token.
{ withSystem, ... }:
{
  vanixiets.effects = withSystem "x86_64-linux" (
    { config, ... }:
    {
      deploy-docs = {
        trigger = "push-main";
        program = config.apps.deploy-docs.program;
        args = [ "production" ];
        secrets = [
          "CLOUDFLARE_API_TOKEN"
          "CLOUDFLARE_ACCOUNT_ID"
        ];
        rehearsals = [ config.checks.deploy-docs-rehearsal ];
        lock = "deploy-docs";
      };

      release-packages = {
        trigger = "push-main";
        program = config.apps.release-packages.program;
        secrets = [ "GITHUB_TOKEN" ];
        rehearsals = [ config.checks.release-rehearsal ];
        lock = "release-packages";
      };

      docs-preview = {
        trigger = "pull-request";
        program = config.apps.docs-preview.program;
        secrets = [
          "CLOUDFLARE_API_TOKEN"
          "CLOUDFLARE_ACCOUNT_ID"
        ];
        forgeToken = true;
        rehearsals = [
          config.checks.docs-preview-rehearsal
          config.checks.deploy-docs-rehearsal
        ];
        # {pr} is nixbot's expansion to the pull request number.
        lock = "deploy-docs-preview-{pr}";
        permission = "write";
      };
    }
  );
}

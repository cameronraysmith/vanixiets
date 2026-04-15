{ ... }:
{
  perSystem =
    { config, ... }:
    {
      # Passthru tests hoisted to checks (ironstar pattern: modules/checks/docs.nix:6-7).
      checks.vanixiets-docs-unit = config.packages.vanixiets-docs.tests.unit;
      checks.vanixiets-docs-e2e = config.packages.vanixiets-docs.tests.e2e;

      # Base docs build wired as an effect-input-wire check. The wrangler deploy
      # in .github/workflows/deploy-docs.yaml remains impure; this check ensures
      # the build half is exercised by `nix flake check` following ironstar's
      # package-as-check idiom (modules/rust.nix:249-251).
      checks.vanixiets-docs = config.packages.vanixiets-docs;
    };
}

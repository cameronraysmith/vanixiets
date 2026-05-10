{ ... }:
{
  perSystem =
    { config, ... }:
    {
      # Passthru tests hoisted to checks (ironstar pattern: modules/checks/docs.nix:6-7).
      # Check names drop the vanixiets- prefix for ecosystem alignment; the
      # underlying packages keep the vanixiets-docs* names because they are
      # filesystem-rooted under pkgs/by-name/ and referenced from deploy.nix,
      # release.nix, and preview-version.nix.
      checks.docs-unit = config.packages.vanixiets-docs.tests.unit;
      checks.docs-linkcheck = config.packages.vanixiets-docs.tests.linkcheck;
      checks.docs-e2e = config.packages.vanixiets-docs.tests.e2e;

      # Base docs build wired as an effect-input-wire check. The wrangler deploy
      # in .github/workflows/deploy-docs.yaml remains impure; this check ensures
      # the build half is exercised by `nix flake check` following ironstar's
      # package-as-check idiom (modules/rust.nix:249-251).
      checks.docs = config.packages.vanixiets-docs;
    };
}

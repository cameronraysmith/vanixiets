{ ... }:
{
  perSystem =
    { config, ... }:
    {
      checks.vanixiets-docs-unit = config.packages.vanixiets-docs.tests.unit;
      checks.vanixiets-docs-e2e = config.packages.vanixiets-docs.tests.e2e;
    };
}

{ inputs, ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      shot-scraper = prev.shot-scraper.overridePythonAttrs (old: {
        makeWrapperArgs = (old.makeWrapperArgs or [ ]) ++ [
          "--set"
          "PLAYWRIGHT_BROWSERS_PATH"
          "${inputs.playwright-web-flake.packages.${prev.stdenv.hostPlatform.system}.playwright-driver.browsers
          }"
          "--set"
          "PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS"
          "true"
        ];
      });
    })
  ];
}

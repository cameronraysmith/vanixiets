{
  inputs,
  lib,
  stdenv,
  makeWrapper,
  runCommand,
  bash,
  coreutils,
  gnugrep,
  callPackage,
  makeFontsConf,
  dejavu_fonts,
  withFirefox ? false,
  withWebkit ? false,
  ...
}:
let
  version = "0.1.21";
  pin = lib.importJSON "${inputs.playwright-cli}/pins/cli/${version}.json";
  browsers = (callPackage "${inputs.playwright-cli}/lib/mkBrowsers.nix" { }) (
    lib.filterAttrs (
      name: _: (name != "firefox" || withFirefox) && (name != "webkit" || withWebkit)
    ) pin.browsers
  );
  upstream =
    inputs.playwright-cli.packages.${stdenv.hostPlatform.system}."playwright-cli-${
      lib.replaceStrings [ "." ] [ "_" ] version
    }";
  package = upstream.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];

    # Change only the fallback, not argv or environment browser selection:
    # project config, explicit channels and --browser must retain precedence.
    # Replacing upstream's wrapper also preserves commands with no browser flag.
    postFixup = ''
      substituteInPlace "$out/lib/node_modules/@playwright/cli/node_modules/playwright-core/lib/coreBundle.js" \
        --replace-fail 'browser.launchOptions.channel = "chrome"' \
                       'browser.launchOptions.channel = undefined'
      wrapProgram "$out/bin/playwright-cli" \
        --set PLAYWRIGHT_BROWSERS_PATH "${browsers}" \
        --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1 \
        --set NO_UPDATE_NOTIFIER 1 ${lib.optionalString stdenv.hostPlatform.isLinux "--set-default FONTCONFIG_FILE ${makeFontsConf { fontDirectories = [ dejavu_fonts ]; }}"}
    '';

    passthru = (old.passthru or { }) // {
      inherit browsers;
      playwrightVersion = pin.playwrightVersion;
      skills = "${package.src}/skills";
      tests.smoke =
        runCommand "playwright-cli-smoke"
          {
            # Darwin build accounts cannot initialize Chromium's nested sandbox.
            # Runtime preserves upstream policy (off for bundled Chromium on Linux).
            PLAYWRIGHT_CLI_TEST_NO_SANDBOX = "1";
            nativeBuildInputs = [
              bash
              coreutils
              gnugrep
            ];
            passthru.meta.description = "Launch the agent CLI's pinned browser, interact, snapshot, and close despite a foreign browser path";
          }
          ''
            bash ${./smoke.sh} ${lib.getExe package}
            touch "$out"
          '';
    };

    meta = (old.meta or { }) // {
      license = lib.licenses.asl20;
      platforms = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    };
  });
in
package

# nix-unit cases for lib/pins.nix, run by checks.x86_64-linux.pin-contract
# (modules/checks/pin-contract.nix). Each malformed fixture is a valid one with
# a single defect, and must fail naming the package and the option path.
# `packagePins` holds the `passthru.pin` of every package with a pin.json, and
# `fixedOutputs` each of their sourceBuild artifacts and fixedOutputHash
# companions as `{ at = "<package>.<attribute>"; resolves; }`, where `resolves`
# says whether that attribute carries an `outputHash`.
{
  lib,
  pins,
  packagePins,
  fixedOutputs,
}:
let
  load =
    fixture: name: pin:
    pins.load (builtins.toFile "${fixture}.json" (builtins.toJSON pin)) { inherit name; };

  # Matches across the newlines of a module-system error.
  any = "[\\s\\S]*";
  fails = msg: {
    type = "ThrownError";
    inherit msg;
  };

  icWasm = {
    name = "ic-wasm-bin";
    version = "1.0.0";
    source.githubRelease = {
      owner = "dfinity";
      repo = "ic-wasm";
      tagTemplate = "{version}";
    };
    artifacts.binaries.platformBinaries = {
      urlTemplate = "https://github.com/dfinity/ic-wasm/releases/download/{tag}/ic-wasm-{platform}.tar.xz";
      platforms = {
        x86_64-linux = "x86_64-unknown-linux-gnu";
        aarch64-linux = "aarch64-unknown-linux-gnu";
        x86_64-darwin = "x86_64-apple-darwin";
        aarch64-darwin = "aarch64-apple-darwin";
      };
      checksum.upstreamFile = {
        urlTemplate = "{url}.sha256";
        format.sha256sum = { };
      };
      hashes = {
        x86_64-linux = "sha256-9tQNZ1lvvpGl8sLNusKs4WIwUkbdNbzTDjQjDn+R3/g=";
        aarch64-linux = "sha256-WpvJ1HWrPrjr2sEKwqZWTjcpLgpHJTZG/lC/mQfe4qg=";
        x86_64-darwin = "sha256-XWWCVJDBcr6rz0RElrbkfIKTlRvcDppScF37kku+Re0=";
        aarch64-darwin = "sha256-mfPY2vFvh9UnhlKZx1ws/VC8ndS7FmRQq9H1ziYYmQo=";
      };
    };
    companions = [ ];
  };

  omnigraph = {
    name = "omnigraph";
    version = "0.15.0";
    source.githubRelease = {
      owner = "ModernRelay";
      repo = "omnigraph";
      tagTemplate = "v{version}";
    };
    artifacts = {
      binaries.platformBinaries = {
        urlTemplate = "https://github.com/ModernRelay/omnigraph/releases/download/{tag}/omnigraph-{platform}.tar.gz";
        platforms.x86_64-linux = "linux-x86_64";
        checksum.upstreamFile = {
          urlTemplate = "https://github.com/ModernRelay/omnigraph/releases/download/{tag}/omnigraph-{platform}.sha256";
          format.sha256sum = { };
        };
        hashes.x86_64-linux = "sha256-1zEs5Jq8pHprtHlWtph9MvZQ+pFni+Gr0Q4Cgkk3uxU=";
      };
      skillSrc.sourceBuild = {
        fetcher.fetchFromGitHub = {
          owner = "ModernRelay";
          repo = "omnigraph";
        };
        hash = "sha256-fDjXKhh/jAXST0SGoPsGkFDIZtpGF9NxCxGd7H4snBA=";
        depsHash.none = { };
      };
    };
  };

  claudeCode = {
    name = "claude-code";
    version = "2.1.331";
    source.vendorText = {
      url = "https://downloads.example/claude-code-releases/latest";
      regex = "^(?<version>\\S+)$";
    };
    artifacts.binary.platformBinaries = {
      urlTemplate = "https://downloads.example/claude-code-releases/{version}/{platform}/claude";
      platforms.aarch64-darwin = "darwin-arm64";
      checksum.upstreamFile = {
        urlTemplate = "https://downloads.example/claude-code-releases/{version}/manifest.json";
        format.jsonPointer.pointerTemplate = "/platforms/{platform}/checksum";
      };
      hashes.aarch64-darwin = "sha256-SHRZHcOb/xGIkhuCy+uKROOjOw+SyIiz1DY5uTRBAfc=";
    };
  };

  mergify = {
    name = "mergify-cli-bin";
    version = "2026.9.16.1";
    source.githubRelease = {
      owner = "Mergifyio";
      repo = "mergify-cli";
      tagTemplate = "{version}";
    };
    artifacts.binaries.platformBinaries = {
      urlTemplate = "https://github.com/Mergifyio/mergify-cli/releases/download/{tag}/mergify-{version}-{platform}.tar.gz";
      platforms.x86_64-linux = "x86_64-unknown-linux-gnu";
      checksum.upstreamFile = {
        urlTemplate = "https://github.com/Mergifyio/mergify-cli/releases/download/{tag}/SHA256SUMS";
        format.sha256sum = { };
      };
      hashes.x86_64-linux = "sha256-kH382b2ZvcQGF8DO5waumUFYKU7Ksorc6vQrNlKrshI=";
    };
    rev = "e7c1ebbc281361f0b2b7827cf583f57339c97ebc";
    companions = [
      {
        path = "modules/home/ai/plugins/version-control-and-forge/apm.yml";
        kind.apmRef.git = "Mergifyio/mergify-cli";
      }
      {
        path = "pkgs/by-name/apm-skills-compose/hashes.json";
        kind.fixedOutputHash = {
          package = "apm-skills-compose";
          attr = "apmDepsHash";
          fodAttr = "deps";
        };
      }
    ];
  };

  greptimedb = {
    name = "greptimedb-bin";
    version = "1.2.1";
    source.githubRelease = {
      owner = "GreptimeTeam";
      repo = "greptimedb";
      tagTemplate = "v{version}";
    };
    artifacts = {
      binaries.platformBinaries = {
        urlTemplate = "https://github.com/GreptimeTeam/greptimedb/releases/download/{tag}/greptime-{platform}-{tag}.tar.gz";
        platforms.x86_64-linux = "linux-amd64";
        checksum.upstreamFile = {
          urlTemplate = "https://github.com/GreptimeTeam/greptimedb/releases/download/{tag}/greptime-{platform}-{tag}.sha256sum";
          format.sha256sum = { };
        };
        hashes.x86_64-linux = "sha256-Bi1b6xPeSZHE/sIBsuUHFRi/TKjw1SlH66dXp0wqVCA=";
      };
      dashboard.fileValue = {
        urlTemplate = "https://raw.githubusercontent.com/GreptimeTeam/greptimedb/{tag}/src/servers/dashboard/VERSION";
        regex = "v?([0-9]+\\.[0-9]+\\.[0-9]+)\\s*";
        value = "0.13.13";
      };
    };
  };

  withDashboard =
    fields:
    greptimedb
    // {
      artifacts = greptimedb.artifacts // {
        dashboard.fileValue = fields;
      };
    };

  ouroboros = {
    name = "ouroboros";
    version = "0.55.3";
    source.pypi.package = "ouroboros-ai";
    artifacts.cli.runtimeFetch.probeUrlTemplate = "https://pypi.org/pypi/ouroboros-ai/{version}/json";
  };

  withProbe = runtimeFetch: ouroboros // { artifacts.cli.runtimeFetch = runtimeFetch; };

  withCompanion =
    companion:
    mergify
    // {
      companions = [ companion ];
    };

  mops = {
    name = "mops-bin";
    version = "3.8.0";
    source.githubRelease = {
      owner = "caffeinelabs";
      repo = "mops";
      tagTemplate = "cli-v{version}";
    };
    artifacts.cli.file = {
      urlTemplate = "https://github.com/caffeinelabs/mops/releases/download/{tag}/cli.tgz";
      checksum.prefetch = { };
      hash = "sha256-mHVzKVCzp8USfKW4cf3xPKySpScpHNDDxusACONfZuI=";
    };
  };

  withFile = fields: mops // { artifacts.cli.file = fields; };
in
{
  testValidPinParsesToItself = {
    expr = (load "valid" "ic-wasm-bin" icWasm).pin;
    expected = icWasm // {
      rev = null;
    };
  };

  testValidPinWithCompanionsParsesToItself = {
    expr = (load "companions" "mergify-cli-bin" mergify).pin;
    expected = mergify;
  };

  testPlanExpandsTagPlatformAndUrl = {
    expr = (load "valid" "ic-wasm-bin" icWasm).pinPlan "1.0.0";
    expected =
      let
        release = "https://github.com/dfinity/ic-wasm/releases/download/1.0.0";
        entry = asset: {
          url = "${release}/${asset}";
          checksum.upstreamFile = {
            url = "${release}/${asset}.sha256";
            format.sha256sum.asset = asset;
          };
        };
      in
      {
        version = "1.0.0";
        tag = "1.0.0";
        artifacts.binaries.platformBinaries = {
          x86_64-linux = entry "ic-wasm-x86_64-unknown-linux-gnu.tar.xz";
          aarch64-linux = entry "ic-wasm-aarch64-unknown-linux-gnu.tar.xz";
          x86_64-darwin = entry "ic-wasm-x86_64-apple-darwin.tar.xz";
          aarch64-darwin = entry "ic-wasm-aarch64-apple-darwin.tar.xz";
        };
      };
  };

  testPlanOfANewVersionFollowsIt = {
    expr = ((load "sourceBuild" "omnigraph" omnigraph).pinPlan "0.16.0").artifacts;
    expected = {
      binaries.platformBinaries.x86_64-linux = {
        url = "https://github.com/ModernRelay/omnigraph/releases/download/v0.16.0/omnigraph-linux-x86_64.tar.gz";
        checksum.upstreamFile = {
          url = "https://github.com/ModernRelay/omnigraph/releases/download/v0.16.0/omnigraph-linux-x86_64.sha256";
          format.sha256sum.asset = "omnigraph-linux-x86_64.tar.gz";
        };
      };
      skillSrc.sourceBuild.fetchFromGitHub = {
        owner = "ModernRelay";
        repo = "omnigraph";
        tag = "v0.16.0";
      };
    };
  };

  testPlanOfAVendorSourceHasNoTag = {
    expr = (load "jsonPointer" "claude-code" claudeCode).pinPlan "2.1.331";
    expected = {
      version = "2.1.331";
      tag = null;
      artifacts.binary.platformBinaries.aarch64-darwin = {
        url = "https://downloads.example/claude-code-releases/2.1.331/darwin-arm64/claude";
        checksum.upstreamFile = {
          url = "https://downloads.example/claude-code-releases/2.1.331/manifest.json";
          format.jsonPointer.pointer = "/platforms/darwin-arm64/checksum";
        };
      };
    };
  };

  testPlanRejectsTagForAVendorSource = {
    expr =
      (
        (load "vendorTag" "claude-code" (
          lib.recursiveUpdate claudeCode {
            artifacts.binary.platformBinaries.urlTemplate = "https://downloads.example/{tag}/claude";
          }
        )).pinPlan
          "2.1.331"
      ).artifacts.binary.platformBinaries.aarch64-darwin.url;
    expectedError = fails "pinPlan of claude-code: template https://downloads.example/\\{tag\\}/claude uses a variable other than";
  };

  testUnknownSourceTagFails = {
    expr = (load "unknown-source" "ic-wasm-bin" (icWasm // { source.gitlab.project = "x"; })).pin;
    expectedError = fails "option `source' is not of type `attribute-tagged union${any}pin of package ic-wasm-bin";
  };

  testPlatformWithoutHashFails = {
    expr =
      (load "missing-hash" "ic-wasm-bin" (
        icWasm
        // {
          artifacts.binaries.platformBinaries = icWasm.artifacts.binaries.platformBinaries // {
            hashes = removeAttrs icWasm.artifacts.binaries.platformBinaries.hashes [ "x86_64-darwin" ];
          };
        }
      )).pin;
    expectedError = fails "pin of package ic-wasm-bin\\) is malformed:${any}artifacts\\.binaries\\.platformBinaries\\.hashes: no hash for platform x86_64-darwin";
  };

  testCompanionWithParentComponentFails = {
    expr =
      (load "dotdot" "mergify-cli-bin" (withCompanion {
        path = "modules/../flake.nix";
        kind.apmRef.git = "Mergifyio/mergify-cli";
      })).pin;
    expectedError = fails "pin of package mergify-cli-bin\\) is malformed:${any}companions\\.0\\.path: modules/\\.\\./flake\\.nix has a `\\.\\.` component";
  };

  testCompanionInsideThePackageFails = {
    expr =
      (load "inside" "mergify-cli-bin" (withCompanion {
        path = "pkgs/by-name/mergify-cli-bin/extra.json";
        kind.fixedOutputHash = {
          package = "mergify-cli-bin";
          attr = "hash";
          fodAttr = "src";
        };
      })).pin;
    expectedError = fails "pin of package mergify-cli-bin\\) is malformed:${any}companions\\.0\\.path: pkgs/by-name/mergify-cli-bin/extra\\.json lies inside pkgs/by-name/mergify-cli-bin/";
  };

  testNameMismatchFails = {
    expr = (load "wrong-name" "ic-wasm-bin" (icWasm // { name = "icp-cli-bin"; })).pin;
    expectedError = fails "pin of package ic-wasm-bin\\) is malformed:${any}name: the pin names icp-cli-bin, but package ic-wasm-bin reads it";
  };

  testFixedOutputHashOnNixFileFails = {
    expr =
      (load "nix-companion" "mergify-cli-bin" (withCompanion {
        path = "pkgs/by-name/apm-skills-compose/package.nix";
        kind.fixedOutputHash = {
          package = "apm-skills-compose";
          attr = "apmDepsHash";
          fodAttr = "deps";
        };
      })).pin;
    expectedError = fails "pin of package mergify-cli-bin\\) is malformed:${any}companions\\.0\\.path: pkgs/by-name/apm-skills-compose/package\\.nix is a fixedOutputHash companion, which must name a JSON file";
  };

  testFixedOutputHashWithoutFodAttrFails = {
    expr =
      (load "no-fod-attr" "mergify-cli-bin" (withCompanion {
        path = "pkgs/by-name/apm-skills-compose/hashes.json";
        kind.fixedOutputHash = {
          package = "apm-skills-compose";
          attr = "apmDepsHash";
        };
      })).pin;
    expectedError = fails "pin of package mergify-cli-bin\\) is malformed:${any}companions\\.0\\.kind\\.fixedOutputHash\\.fodAttr: `' is not an attribute name";
  };

  testFixedOutputHashWithEmptyFodAttrFails = {
    expr =
      (load "empty-fod-attr" "mergify-cli-bin" (withCompanion {
        path = "pkgs/by-name/apm-skills-compose/hashes.json";
        kind.fixedOutputHash = {
          package = "apm-skills-compose";
          attr = "apmDepsHash";
          fodAttr = "";
        };
      })).pin;
    expectedError = fails "pin of package mergify-cli-bin\\) is malformed:${any}companions\\.0\\.kind\\.fixedOutputHash\\.fodAttr: `' is not an attribute name";
  };

  testFixedOutputHashWithDottedFodAttrFails = {
    expr =
      (load "dotted-fod-attr" "mergify-cli-bin" (withCompanion {
        path = "pkgs/by-name/apm-skills-compose/hashes.json";
        kind.fixedOutputHash = {
          package = "apm-skills-compose";
          attr = "apmDepsHash";
          fodAttr = "passthru.deps";
        };
      })).pin;
    expectedError = fails "pin of package mergify-cli-bin\\) is malformed:${any}companions\\.0\\.kind\\.fixedOutputHash\\.fodAttr: `passthru\\.deps' is not an attribute name";
  };

  testApmRefWithoutRevFails = {
    expr = (load "no-rev" "mergify-cli-bin" (removeAttrs mergify [ "rev" ])).pin;
    expectedError = fails "pin of package mergify-cli-bin\\) is malformed:${any}rev: required by an apmRef companion or a gitCommit source, and absent";
  };

  testValidFileValuePinParsesToItself = {
    expr = (load "fileValue" "greptimedb-bin" greptimedb).pin;
    expected = greptimedb // {
      rev = null;
      companions = [ ];
    };
  };

  testPlanExpandsAFileValueAtTheTag = {
    expr = ((load "fileValue" "greptimedb-bin" greptimedb).pinPlan "1.3.1").artifacts.dashboard;
    expected.fileValue = {
      url = "https://raw.githubusercontent.com/GreptimeTeam/greptimedb/v1.3.1/src/servers/dashboard/VERSION";
      inherit (greptimedb.artifacts.dashboard.fileValue) regex;
    };
  };

  testFileValueWithEmptyValueFails = {
    expr =
      (load "empty-value" "greptimedb-bin" (
        withDashboard (greptimedb.artifacts.dashboard.fileValue // { value = ""; })
      )).pin;
    expectedError = fails "artifacts\\.dashboard\\.fileValue\\.value' is not of type `non-empty string'";
  };

  testFileValueWithoutRegexFails = {
    expr =
      (load "no-regex" "greptimedb-bin" (
        withDashboard (removeAttrs greptimedb.artifacts.dashboard.fileValue [ "regex" ])
      )).pin;
    expectedError = fails "artifacts\\.dashboard\\.fileValue\\.regex' was accessed but has no value defined";
  };

  testPlanRejectsPlatformInAFileValue = {
    expr =
      (
        (load "fileValue-platform" "greptimedb-bin" (
          withDashboard (
            greptimedb.artifacts.dashboard.fileValue
            // {
              urlTemplate = "https://raw.githubusercontent.com/GreptimeTeam/greptimedb/{tag}/{platform}/VERSION";
            }
          )
        )).pinPlan
          "1.2.1"
      ).artifacts.dashboard.fileValue.url;
    expectedError = fails "pinPlan of greptimedb-bin: template https://raw\\.githubusercontent\\.com/GreptimeTeam/greptimedb/\\{tag\\}/\\{platform\\}/VERSION uses a variable other than";
  };

  testValidRuntimeFetchPinParsesToItself = {
    expr = (load "runtimeFetch" "ouroboros" ouroboros).pin;
    expected = ouroboros // {
      rev = null;
      companions = [ ];
    };
  };

  testPlanExpandsARuntimeFetchProbe = {
    expr = (load "runtimeFetch" "ouroboros" ouroboros).pinPlan "0.65.7";
    expected = {
      version = "0.65.7";
      tag = null;
      artifacts.cli.runtimeFetch.probeUrl = "https://pypi.org/pypi/ouroboros-ai/0.65.7/json";
    };
  };

  testPlanRejectsTagInAPypiProbe = {
    expr =
      (
        (load "probe-tag" "ouroboros" (withProbe {
          probeUrlTemplate = "https://pypi.org/pypi/ouroboros-ai/{tag}/json";
        })).pinPlan
          "0.55.3"
      ).artifacts.cli.runtimeFetch.probeUrl;
    expectedError = fails "pinPlan of ouroboros: template https://pypi\\.org/pypi/ouroboros-ai/\\{tag\\}/json uses a variable other than \\{version\\}";
  };

  testRuntimeFetchWithAHashFails = {
    expr =
      (load "probe-hash" "ouroboros" (withProbe {
        inherit (ouroboros.artifacts.cli.runtimeFetch) probeUrlTemplate;
        hash = "sha256-Bi1b6xPeSZHE/sIBsuUHFRi/TKjw1SlH66dXp0wqVCA=";
      })).pin;
    expectedError = fails "artifacts\\.cli\\.runtimeFetch\\.hash' does not exist";
  };

  testRuntimeFetchWithoutProbeFails = {
    expr = (load "no-probe" "ouroboros" (withProbe { })).pin;
    expectedError = fails "artifacts\\.cli\\.runtimeFetch\\.probeUrlTemplate' was accessed but has no value defined";
  };

  testValidFilePinParsesToItself = {
    expr = (load "file" "mops-bin" mops).pin;
    expected = mops // {
      rev = null;
      companions = [ ];
    };
  };

  testPlanExpandsAFileAtTheTag = {
    expr = (load "file" "mops-bin" mops).pinPlan "3.9.0";
    expected = {
      version = "3.9.0";
      tag = "cli-v3.9.0";
      artifacts.cli.file = {
        url = "https://github.com/caffeinelabs/mops/releases/download/cli-v3.9.0/cli.tgz";
        checksum.prefetch = { };
      };
    };
  };

  testPlanExpandsAFileChecksumFile = {
    expr =
      (
        (load "file-upstream" "mops-bin" (
          withFile (
            mops.artifacts.cli.file
            // {
              checksum.upstreamFile = {
                urlTemplate = "{url}.sha256";
                format.sha256sum = { };
              };
            }
          )
        )).pinPlan
          "3.9.0"
      ).artifacts.cli.file.checksum;
    expected.upstreamFile = {
      url = "https://github.com/caffeinelabs/mops/releases/download/cli-v3.9.0/cli.tgz.sha256";
      format.sha256sum.asset = "cli.tgz";
    };
  };

  testFileWithoutHashFails = {
    expr =
      (load "file-no-hash" "mops-bin" (withFile (removeAttrs mops.artifacts.cli.file [ "hash" ]))).pin;
    expectedError = fails "artifacts\\.cli\\.file\\.hash' was accessed but has no value defined";
  };

  testPlanRejectsPlatformInAFile = {
    expr =
      (
        (load "file-platform" "mops-bin" (
          withFile (
            mops.artifacts.cli.file
            // {
              urlTemplate = "https://github.com/caffeinelabs/mops/releases/download/{tag}/cli-{platform}.tgz";
            }
          )
        )).pinPlan
          "3.8.0"
      ).artifacts.cli.file.url;
    expectedError = fails "pinPlan of mops-bin: template https://github\\.com/caffeinelabs/mops/releases/download/\\{tag\\}/cli-\\{platform\\}\\.tgz uses a variable other than";
  };

  testFileWithInvalidSriFails = {
    expr =
      (load "file-hex" "mops-bin" (
        withFile (
          mops.artifacts.cli.file
          // {
            hash = "sha256:9875732950b3a7c5147ca5b871fdf03cac92a527291cd0c3c6eb0008e35f66e2";
          }
        )
      )).pin;
    expectedError = fails "option `artifacts\\.cli\\.file\\.hash' is not of type `string matching the pattern";
  };

  testFileWithUnknownChecksumTagFails = {
    expr =
      (load "file-checksum-tag" "mops-bin" (
        withFile (mops.artifacts.cli.file // { checksum.sha512sums = { }; })
      )).pin;
    expectedError = fails "option `artifacts\\.cli\\.file\\.checksum' is not of type `attribute-tagged union${any}pin of package mops-bin";
  };

  testEmptyArtifactsFail = {
    expr = (load "no-artifacts" "ouroboros" (ouroboros // { artifacts = { }; })).pin;
    expectedError = fails "pin of package ouroboros\\) is malformed:${any}artifacts: holds no artifact entry";
  };

  testEveryFixedOutputAttributeResolves = {
    expr = map (f: f.at) (lib.filter (f: !f.resolves) fixedOutputs);
    expected = [ ];
  };

  testEveryPackagePinNamesItsPackage = {
    expr = lib.mapAttrs (_: pin: pin.name) packagePins;
    expected = lib.mapAttrs (name: _: name) packagePins;
  };

  testSomePackageHasAPin = {
    expr = packagePins != { };
    expected = true;
  };

  testSomeFixedOutputIsRecorded = {
    expr = fixedOutputs != [ ];
    expected = true;
  };
}

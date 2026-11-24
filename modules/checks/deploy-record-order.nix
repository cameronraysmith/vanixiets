# checks.x86_64-linux.deploy-record-order: the order judge of
# flake.lib.deployRecordObligations (modules/system/deploy-record.nix) over
# literal activation scripts. It accepts a darwin script that reads the
# previous system before launchd reloads activate-system and before the
# relink, and a NixOS script that runs the record before the relink; it finds
# exactly one problem in each mutant: a darwin script without the read, one
# that reads after the activate-system reload (F86: the profile already names
# the new system), one that reads after the relink, one whose record does not
# take the read, and a NixOS script whose record runs after the relink.
# It then runs the record script itself against a stand-in link that already
# names the new system, as on darwin after the reload: given the earlier read
# it writes that as previous_closure, given an empty read it writes none, and
# without one it reads the link, as on NixOS.
#
# The real scripts are judged by modules/checks/machines.nix on every
# nixos-<host> and darwin-<host> check; the fixtures are literals, so this
# check runs on x86_64-linux only.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      o = self.lib.deployRecordObligations;
      script = "/nix/store/00000000000000000000000000000000-deploy-record-h/bin/deploy-record-h";
      read = ''
        deployRecordPrevious=
        if [ -e /run/current-system ]; then
          deployRecordPrevious=$(readlink -f /run/current-system)
        fi
      '';
      reload = "launchctl load -w '/Library/LaunchDaemons/org.nixos.activate-system.plist'\n";
      record = "${script} \"$systemConfig\" \"$deployRecordPrevious\"\n";
      relink = "ln -sfn \"$(readlink -f \"$systemConfig\")\" /run/current-system\n";
      darwin = text: {
        isDarwin = true;
        inherit text;
        problems = 1;
      };
      cases = {
        darwinAccepted = darwin (read + reload + record + relink) // {
          problems = 0;
        };
        nixosAccepted = {
          isDarwin = false;
          text = "${script} \"$systemConfig\"\n" + relink;
          problems = 0;
        };
        darwinNoRead = darwin (reload + "${script} \"$systemConfig\"\n" + relink);
        darwinReadAfterReload = darwin (reload + read + record + relink);
        darwinReadAfterRelink = darwin (relink + read + reload + record);
        darwinRecordWithoutRead = darwin (read + reload + "${script} \"$systemConfig\"\n" + relink);
        nixosRecordAfterRelink = {
          isDarwin = false;
          text = relink + "${script} \"$systemConfig\"\n";
          problems = 1;
        };
      };
      wrong = lib.filterAttrs (
        _: case:
        lib.length (
          o.orderProblems {
            name = "h";
            inherit script;
            inherit (case) isDarwin text;
          }
        ) != case.problems
      ) cases;
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        deploy-record-order = {
          class = "medium";
          measured = false;
        };
      };
      checks.deploy-record-order =
        assert lib.assertMsg (
          wrong == { }
        ) "deploy-record-order: the judge misjudges ${toString (lib.attrNames wrong)}";
        let
          record = self.lib.deployRecordScript {
            inherit pkgs;
            hostName = "h";
            file = "/build/records.jsonl";
            currentSystem = "/build/current-system";
          };
        in
        pkgs.runCommand "deploy-record-order" { nativeBuildInputs = [ pkgs.jq ]; } ''
          mkdir -p /build/old /build/new
          ln -s /build/new /build/current-system
          fail() { echo "deploy-record-order: $*"; exit 1; }
          ${record} /build/new /build/old
          jq -e '.closure == "/build/new" and .previous_closure == "/build/old"' <<<"$(tail -n 1 /build/records.jsonl)" >/dev/null ||
            fail "the earlier read was not written as previous_closure: $(tail -n 1 /build/records.jsonl)"
          ${record} /build/new ""
          jq -e 'has("previous_closure") | not' <<<"$(tail -n 1 /build/records.jsonl)" >/dev/null ||
            fail "an empty read wrote a previous_closure: $(tail -n 1 /build/records.jsonl)"
          ${record} /build/new
          jq -e '.previous_closure == "/build/new"' <<<"$(tail -n 1 /build/records.jsonl)" >/dev/null ||
            fail "without a read the link was not read: $(tail -n 1 /build/records.jsonl)"
          touch $out
        '';
    };
}

# checks.x86_64-linux.darwin-uid-preflight: each darwin host's activation-time
# uid comparison (home-manager-integration.uidPreflight,
# modules/system/home-manager-integration.nix) passes when every attached
# account has its recorded uid or is absent, and fails naming the account when
# one has its recorded uid + 1; each attached account is the mismatched one in
# turn. A stub `id` first on PATH stands in for macOS's Directory Services
# lookup, so this shows how the rendered text behaves, not any Mac's accounts.
#
# The cases run the rendered bash, so the check is a build, not a
# flake.lib.mkJudgeCheck judge over Nix values: a judge of the text would
# accept a script that names the right accounts but compares wrongly.
# The attribute name is a literal; the host list is read from
# flake.fleet.hosts in the value. One system: the derivation is a bash script
# under a stub and does not differ by system.
{ config, lib, ... }:
let
  inherit (config) flake;
in
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      testSizes.checks = {
        # nixbot: no runs yet, too few to class (declare-test-size-classes design D4)
        darwin-uid-preflight = {
          class = "medium";
          measured = false;
        };
      };
      checks.darwin-uid-preflight =
        let
          hosts = lib.attrNames (lib.filterAttrs (_: h: h.class == "darwin") flake.fleet.hosts);
          table = uids: lib.concatStrings (lib.mapAttrsToList (n: v: "${n} ${toString v}\n") uids);
          caseOf =
            host:
            let
              cfg = flake.darwinConfigurations.${host}.config.home-manager-integration;
              uids = lib.mapAttrs (_: a: a.uid) cfg.attachments;
              script = pkgs.writeText "${host}-uid-preflight" cfg.uidPreflight;
            in
            ''
              matches ${host} ${script} ${pkgs.writeText "${host}-uids" (table uids)}
              absent ${host} ${script}
            ''
            + lib.concatMapStrings (account: ''
              mismatch ${host} ${script} ${
                pkgs.writeText "${host}-uids-${account}" (table (uids // { ${account} = uids.${account} + 1; }))
              } ${account}
            '') (lib.attrNames uids);
        in
        pkgs.runCommand "darwin-uid-preflight" { } ''
          mkdir stub
          cat > stub/id <<'EOF'
          #!${pkgs.runtimeShell}
          [ "$1" = -u ] || exit 2
          while read -r n u; do
            if [ "$n" = "$2" ]; then echo "$u"; exit 0; fi
          done < "$UID_TABLE"
          exit 1
          EOF
          chmod +x stub/id
          export PATH="$PWD/stub:$PATH"
          fail() { echo "darwin-uid-preflight: $*" >&2; exit 1; }
          # Every attached account at its recorded uid: passes.
          matches() {
            UID_TABLE=$3 ${pkgs.bash}/bin/bash -e "$2" || fail "$1: failed with every account at its recorded uid"
          }
          # No attached account exists yet: passes.
          absent() {
            UID_TABLE=/dev/null ${pkgs.bash}/bin/bash -e "$2" || fail "$1: failed with every account absent"
          }
          # One attached account at its recorded uid + 1: fails, naming it.
          mismatch() {
            if UID_TABLE=$3 ${pkgs.bash}/bin/bash -e "$2" 2>err; then
              fail "$1: passed with $4 at its recorded uid + 1"
            fi
            grep -q "^  $1: account $4 has uid " err || { cat err >&2; fail "$1: did not name $4"; }
          }
          ${lib.concatMapStrings caseOf hosts}
          touch $out
        '';
    };
}

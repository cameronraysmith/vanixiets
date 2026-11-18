# checks.x86_64-linux.darwin-mesh-resolver-flags: every darwin machine's
# /etc/resolver file for the mesh zone (always) and for .zt (where the host
# renders one) asks configd for A and AAAA records (finding F34).
#
# A resolver file without a `flags` line inherits configd's global query
# flags, which on a Mac with no IPv6 default route request A records only, and
# getaddrinfo with AI_ADDRCONFIG then never asks for the AAAA records that
# are the zone's only records. configd reads the first `flags` line of the
# file, case-insensitively, and its words replace those inherited flags
# (configd-1405.100.8 dnsinfo/dnsinfo_flatfile.c:74,380-394,520-522), so the
# judge below reads only that line and needs both `a` and `aaaa` in it.
#
# The host list is the darwin machines of clan.inventory (static data); the
# rendered texts are evaluated only when this check is. The judge runs over
# two mutants first, a file without a `flags` line and one whose line lacks
# `aaaa`, and must reject both. The texts are platform-independent, so the
# check runs on x86_64-linux only, where nixbot builds.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      darwinHosts = builtins.attrNames (
        lib.filterAttrs (_: machine: machine.machineClass == "darwin") self.clan.inventory.machines
      );
      zones = [
        {
          zone = self.lib.fleet.domain;
          required = true;
        }
        {
          zone = "zt";
          required = false;
        }
      ];
      etcFile =
        host: zone: self.darwinConfigurations.${host}.config.environment.etc."resolver/${zone}" or null;
      files = lib.concatMap (
        host:
        lib.concatMap (
          { zone, required }:
          let
            file = etcFile host zone;
            rendered = file != null && file.enable;
          in
          assert lib.assertMsg (
            rendered || !required
          ) "darwin-mesh-resolver-flags: ${host} renders no enabled /etc/resolver/${zone}";
          lib.optional rendered {
            name = "${host}-${zone}";
            path = pkgs.writeText "resolver-${host}-${zone}" file.text;
          }
        ) zones
      ) darwinHosts;
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.darwin-mesh-resolver-flags =
        assert lib.assertMsg (
          darwinHosts != [ ]
        ) "darwin-mesh-resolver-flags: no darwin machines in the inventory";
        pkgs.runCommand "darwin-mesh-resolver-flags" { } ''
          set -uo pipefail
          # The words after the first line whose first word is `flags`.
          requests_aaaa() {
            awk 'tolower($1) == "flags" { for (i = 2; i <= NF; i++) w[tolower($i)] = 1; found = 1; exit }
                 END { exit !(found && w["a"] && w["aaaa"]) }' "$1"
          }

          printf 'nameserver fd09::53\n' > no-flags
          printf 'nameserver fd09::53\nflags a\nflags a aaaa\n' > a-only
          for mutant in no-flags a-only; do
            if requests_aaaa "$mutant"; then echo "FAIL: the judge accepts mutant $mutant"; exit 1; fi
            echo "mutant $mutant rejected"
          done

          failed=0
          ${lib.concatMapStrings (f: ''
            if requests_aaaa ${f.path}; then
              echo "ok: ${f.name}"
            else
              echo "FAIL: ${f.name} has no first \`flags\` line naming both a and aaaa:"
              cat ${f.path}
              failed=1
            fi
          '') files}
          [ "$failed" = 0 ] || exit 1
          touch $out
        '';
    };
}

# checks.x86_64-linux.darwin-mesh-resolver-flags: every darwin machine's
# /etc/resolver file for the mesh zone (always) asks configd for AAAA records
# only, and its file for .zt (where the host renders one) for A and AAAA
# records (finding F34, design D7).
#
# A resolver file without a `flags` line inherits configd's global query
# flags, which on a Mac with no IPv6 default route request A records only, and
# getaddrinfo with AI_ADDRCONFIG then never asks for the AAAA records that
# are the mesh zone's only records. configd reads the first `flags` line of
# the file, case-insensitively, and its words replace those inherited flags
# (configd-1405.100.8 dnsinfo/dnsinfo_flatfile.c:74,380-394,520-522), so the
# judge below reads only that line and needs exactly the zone's words in it:
# `aaaa` for the mesh zone, whose A question would otherwise stall
# getaddrinfo for 30 s when both resolvers are unreachable, even for names
# /etc/hosts answers (modules/system/mesh-dns.nix); `a aaaa` for .zt, whose
# service names have A records on ZeroTier's IPv4.
#
# The host list is the darwin machines of clan.inventory (static data); the
# rendered texts are evaluated only when this check is. The judge runs over
# three mutants first and must reject each: a mesh-zone file without a
# `flags` line, a mesh-zone file whose first `flags` line is `a aaaa`, and a
# .zt file whose first `flags` line is `aaaa`. The texts are
# platform-independent, so the check runs on x86_64-linux only, where nixbot
# builds.
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
          flags = "aaaa";
        }
        {
          zone = "zt";
          required = false;
          flags = "a aaaa";
        }
      ];
      etcFile =
        host: zone: self.darwinConfigurations.${host}.config.environment.etc."resolver/${zone}" or null;
      files = lib.concatMap (
        host:
        lib.concatMap (
          {
            zone,
            required,
            flags,
          }:
          let
            file = etcFile host zone;
            rendered = file != null && file.enable;
          in
          assert lib.assertMsg (
            rendered || !required
          ) "darwin-mesh-resolver-flags: ${host} renders no enabled /etc/resolver/${zone}";
          lib.optional rendered {
            name = "${host}-${zone}";
            inherit flags;
            path = pkgs.writeText "resolver-${host}-${zone}" file.text;
          }
        ) zones
      ) darwinHosts;
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = {
        # nixbot: 0 runs, too few to class (design D4)
        darwin-mesh-resolver-flags = {
          class = "medium";
          measured = false;
        };
      };
      checks.darwin-mesh-resolver-flags =
        assert lib.assertMsg (
          darwinHosts != [ ]
        ) "darwin-mesh-resolver-flags: no darwin machines in the inventory";
        pkgs.runCommand "darwin-mesh-resolver-flags" { } ''
          set -uo pipefail
          # Whether the words after the first line whose first word is `flags`
          # are, as a set, exactly the words of $2.
          flags_are() {
            awk -v want="$2" '
              BEGIN { n = split(want, x, " "); for (i = 1; i <= n; i++) need[x[i]] = 1 }
              tolower($1) == "flags" { for (i = 2; i <= NF; i++) got[tolower($i)] = 1; found = 1; exit }
              END {
                if (!found) exit 1
                for (k in need) if (!(k in got)) exit 1
                for (k in got) if (!(k in need)) exit 1
              }' "$1"
          }

          printf 'nameserver fd09::53\n' > mesh-no-flags
          printf 'nameserver fd09::53\nflags a aaaa\nflags aaaa\n' > mesh-a-aaaa
          printf 'nameserver fd09::53\nflags aaaa\nflags a aaaa\n' > zt-aaaa
          for mutant in mesh-no-flags:aaaa mesh-a-aaaa:aaaa 'zt-aaaa:a aaaa'; do
            if flags_are "''${mutant%%:*}" "''${mutant#*:}"; then echo "FAIL: the judge accepts mutant $mutant"; exit 1; fi
            echo "mutant $mutant rejected"
          done

          failed=0
          ${lib.concatMapStrings (f: ''
            if flags_are ${f.path} ${lib.escapeShellArg f.flags}; then
              echo "ok: ${f.name}"
            else
              echo "FAIL: ${f.name}'s first \`flags\` line is not exactly \`flags ${f.flags}\`:"
              cat ${f.path}
              failed=1
            fi
          '') files}
          [ "$failed" = 0 ] || exit 1
          touch $out
        '';
    };
}

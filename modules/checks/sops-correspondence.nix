# checks.x86_64-linux.sops-correspondence: every public key the legacy sops
# tree names corresponds to what the repository records for it.
#
# Public data only: .sops.yaml, sops/users/*/key.json, sops/machines/*/key.json,
# the sops metadata of every file under secrets/, users' meta.sshKeys and
# flake.lib.darwinHostKeys. No host configuration is evaluated, so the key set
# is static (one name, one system).
#
# Fails when:
# - a user anchor, or a clan user's sops/users/<u>/key.json, differs from
#   ssh-to-age of the first meta.sshKeys entry of the user it maps to;
# - a machine anchor differs from sops/machines/<m>/key.json;
# - a host-key anchor differs from ssh-to-age of the pinned darwin host key;
# - a file under secrets/ carries recipients other than the anchors of the
#   first .sops.yaml rule whose path_regex matches it, or matches no rule;
# - an anchor is not classified below, a classified name has no anchor, or a
#   clan user directory is unmapped;
# - the fleet deployer's reach differs from flake.lib.fleetDeployer: before
#   its keys are committed, sops/users/fleet-deployer and any fleet-deployers
#   group must not exist; after, the user's key.json must be keys.age, the
#   group must hold only that user, every target's machine key must name the
#   group, and no other machine key, shared var or other machine's var may;
# - the scan finds no anchor, no rule or no file.
# Each failure mode has a mutant case that must fail, so the check cannot pass
# vacuously.
#
# path_regex is matched with jq's Oniguruma `test`, while sops uses Go RE2; the
# patterns in .sops.yaml use only anchors, literal dots, `.*`, alternation and
# groups, on which both agree. A pattern outside that subset needs this check
# revisited.
{ config, lib, ... }:
let
  users = config.flake.users;
  firstLoginKey = name: builtins.head users.${name}.meta.sshKeys;

  # .sops.yaml anchor -> flake user whose first login key it must be the image of
  userAnchors = {
    admin-user = "crs58";
    raquel-user = "raquel";
    janettesmith-user = "janettesmith";
    christophersmith-user = "christophersmith";
    tara-user = "tara";
  };
  # sops/users/<name>/key.json -> flake user (cameron is an alias of crs58)
  clanUsers = [
    "cameron"
    "crs58"
    "raquel"
    "janettesmith"
    "christophersmith"
  ];
  # anchor = clan machine name: every enrolled NixOS host. A darwin host's
  # machine key is no .sops.yaml recipient; its anchor, where it has one, is
  # its pinned host key below.
  machineAnchors = lib.attrNames (
    lib.filterAttrs (_: host: host.enrolled && host.class == "nixos") config.flake.lib.hosts
  );
  # anchor -> host in flake.lib.darwinHostKeys
  hostKeyAnchors = {
    blackphos = "blackphos";
  };
  # Keys with no person, machine or host-key counterpart in the repository:
  # ci is the CI runner's SOPS_AGE_KEY; ubuntu-user is the Devin profile's key,
  # which has no meta.sshKeys; claude-sandbox-user is the Claude Code cloud
  # environment's SOPS_AGE_KEY, whose profile has no meta.sshKeys either.
  # dev is deliberately in no class.
  runnerAnchors = [
    "ci"
    "ubuntu-user"
    "claude-sandbox-user"
  ];
  recoveryAnchors = [ "admin" ];

  tsv = attrs: lib.concatStrings (lib.mapAttrsToList (k: v: "${k}\t${v}\n") attrs);
  lines = lib.concatMapStrings (x: "${x}\n");

  # The fleet deployer (modules/lib/fleet-deployer.nix): a clan user mapped to
  # its own committed age key rather than to a person's login key.
  inherit (config.flake.lib) fleetDeployer;
  deployerAge = if fleetDeployer.keys == null then "" else fleetDeployer.keys.age;
in
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = {
        # nixbot: median 29 s, slowest 70 s, 8 runs in 30 days
        sops-correspondence.class = "small";
      };
      checks.sops-correspondence =
        pkgs.runCommand "sops-correspondence"
          {
            nativeBuildInputs = [
              pkgs.ssh-to-age
              pkgs.jq
              pkgs.yq-go
            ];
            userAnchors = tsv (lib.mapAttrs (_: firstLoginKey) userAnchors);
            clanUsers = tsv (lib.genAttrs clanUsers firstLoginKey);
            hostKeyAnchors = tsv (lib.mapAttrs (_: h: config.flake.lib.darwinHostKeys.${h}) hostKeyAnchors);
            machineAnchors = lines machineAnchors;
            otherAnchors = lines (runnerAnchors ++ recoveryAnchors);
            inherit deployerAge;
            deployerTargets = lines fleetDeployer.targets;
            passAsFile = [
              "userAnchors"
              "clanUsers"
              "hostKeyAnchors"
              "machineAnchors"
              "otherAnchors"
              "deployerTargets"
            ];
            tree = lib.fileset.toSource {
              root = ../..;
              fileset = lib.fileset.unions [
                ../../.sops.yaml
                ../../sops/users
                ../../sops/machines
                ../../secrets
                (lib.fileset.maybeMissing ../../sops/secrets)
                (lib.fileset.maybeMissing ../../sops/groups)
                (lib.fileset.maybeMissing ../../vars)
              ];
            };
            passthru.meta.description = "sops recipients correspond to the public keys the repository records";
          }
          ''
            set -uo pipefail

            # verify_tree <dir>: prints one line per failure; returns non-zero on any.
            verify_tree() {
              local d=$1 fails=0 n_anchors n_rules n_files=0
              fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
              yq '.keys[] | anchor + " " + .' "$d/.sops.yaml" > anchors
              n_anchors=$(wc -l < anchors)
              n_rules=$(yq '.creation_rules | length' "$d/.sops.yaml")
              key_of() { awk -v a="$1" '$1 == a { print $2 }' anchors; }

              cut -f1 "$userAnchorsPath" "$hostKeyAnchorsPath" > classified
              cat "$machineAnchorsPath" "$otherAnchorsPath" >> classified
              while read -r a _; do
                grep -qx -- "$a" classified || fail "anchor '$a' is not classified"
              done < anchors
              while read -r a; do
                [ -n "$(key_of "$a")" ] || fail "classified name '$a' has no anchor"
              done < classified

              while IFS=$'\t' read -r a ssh; do
                [ "$(key_of "$a")" = "$(printf '%s\n' "$ssh" | ssh-to-age)" ] \
                  || fail "user anchor '$a' is not ssh-to-age of its user's first login key"
              done < "$userAnchorsPath"
              while IFS=$'\t' read -r u ssh; do
                [ "$(jq -r '.[0].publickey' "$d/sops/users/$u/key.json" 2>/dev/null)" = "$(printf '%s\n' "$ssh" | ssh-to-age)" ] \
                  || fail "clan user '$u' key.json is not ssh-to-age of its first login key"
              done < "$clanUsersPath"
              for dir in "$d"/sops/users/*/; do
                u=$(basename "$dir")
                [ "$u" = fleet-deployer ] && continue
                cut -f1 "$clanUsersPath" | grep -qx -- "$u" || fail "clan user '$u' is not mapped to a flake user"
              done
              while read -r m; do
                [ "$(key_of "$m")" = "$(jq -r '.[0].publickey' "$d/sops/machines/$m/key.json" 2>/dev/null)" ] \
                  || fail "machine anchor '$m' differs from sops/machines/$m/key.json"
              done < "$machineAnchorsPath"
              while IFS=$'\t' read -r a ssh; do
                [ "$(key_of "$a")" = "$(printf '%s\n' "$ssh" | ssh-to-age)" ] \
                  || fail "host-key anchor '$a' is not ssh-to-age of its pinned host key"
              done < "$hostKeyAnchorsPath"

              while IFS= read -r -d "" f; do
                n_files=$((n_files + 1))
                rel=''${f#"$d"/}
                rule=-1
                for ((i = 0; i < n_rules; i++)); do
                  re=$(yq ".creation_rules[$i].path_regex" "$d/.sops.yaml")
                  if jq -en --arg p "$rel" --arg re "$re" '$p | test($re)' > /dev/null; then rule=$i; break; fi
                done
                if [ "$rule" -lt 0 ]; then fail "$rel matches no creation rule"; continue; fi
                want=$(yq ".creation_rules[$rule].key_groups[0].age[] | alias" "$d/.sops.yaml" \
                  | while read -r a; do key_of "$a"; done | sort)
                case "$f" in
                  *.yaml | *.yml) have=$(yq '.sops.age[].recipient' "$f" | sort) ;;
                  *) have=$(jq -r '.sops.age[].recipient' "$f" | sort) ;;
                esac
                [ "$want" = "$have" ] || fail "$rel recipients differ from rule $rule"
              done < <(find "$d/secrets" -type f ! -name '.*' -print0 | sort -z)

              # The fleet deployer's reach.
              if [ -z "$deployerAge" ]; then
                [ ! -e "$d/sops/users/fleet-deployer" ] || fail "sops/users/fleet-deployer exists before flake.lib.fleetDeployer.keys"
                [ ! -e "$d/sops/groups/fleet-deployers" ] || fail "sops/groups/fleet-deployers exists before flake.lib.fleetDeployer.keys"
              else
                [ "$(jq -r '.[0].publickey' "$d/sops/users/fleet-deployer/key.json" 2>/dev/null)" = "$deployerAge" ] \
                  || fail "clan user 'fleet-deployer' key.json is not flake.lib.fleetDeployer.keys.age"
                [ "$(ls "$d/sops/groups/fleet-deployers/users" 2>/dev/null)" = fleet-deployer ] \
                  || fail "sops group fleet-deployers does not hold exactly fleet-deployer"
                while read -r m; do
                  [ -e "$d/sops/secrets/$m-age.key/groups/fleet-deployers" ] \
                    || fail "$m-age.key does not name the fleet-deployers group"
                done < "$deployerTargetsPath"
              fi
              while IFS= read -r -d "" g; do
                rel=''${g#"$d"/}
                case "$rel" in
                  sops/secrets/*-age.key/groups/fleet-deployers)
                    m=''${rel#sops/secrets/}; m=''${m%-age.key/groups/fleet-deployers} ;;
                  vars/per-machine/*)
                    m=''${rel#vars/per-machine/}; m=''${m%%/*} ;;
                  *) m="" ;;
                esac
                if [ -z "$m" ] || ! grep -qx -- "$m" "$deployerTargetsPath"; then
                  fail "$rel gives the fleet deployer a secret outside its targets' machine keys and vars"
                fi
              done < <(find "$d/sops/secrets" "$d/vars" \( -path '*/groups/fleet-deployers' -o -path '*/users/fleet-deployer' \) -print0 2>/dev/null | sort -z)

              [ "$n_anchors" -gt 0 ] || fail "no anchors in .sops.yaml"
              [ "$n_rules" -gt 0 ] || fail "no creation rules in .sops.yaml"
              [ "$n_files" -gt 0 ] || fail "no secret files under secrets/"
              echo "compared $n_anchors anchors, $n_rules rules, $n_files files: $fails failures"
              [ "$fails" -eq 0 ]
            }

            verify_tree "$tree" || { echo "sops correspondence failed"; exit 1; }

            # Mutants: each plants one defect and must fail.
            mutant() {
              local name=$1; shift
              rm -rf m; cp -r "$tree" m; chmod -R u+w m
              "$@"
              if verify_tree m > mutant.log; then
                echo "mutant '$name' passed; the check is vacuous for it"; cat mutant.log; exit 1
              fi
              echo "mutant '$name' failed as expected: $(grep -m1 FAIL mutant.log)"
            }
            other=$(yq '.keys[] | select(anchor == "admin")' "$tree/.sops.yaml")
            swap() { sed -i "s/$(yq ".keys[] | select(anchor == \"$1\")" m/.sops.yaml)/$other/" m/.sops.yaml; }
            mutant user-anchor swap raquel-user
            mutant machine-anchor swap magnetite
            mutant host-key-anchor swap blackphos
            mutant rule-recipients awk -i inplace '
              { print }
              /secrets\/shared/ { inrule = 1 }
              inrule && /- \*admin-user/ { print "        - *ci"; inrule = 0 }
            ' m/.sops.yaml
            mutant unclassified-anchor sed -i "s/^keys:$/keys:\n  - \&stranger $other/" m/.sops.yaml
            mutant dev-reintroduced sed -i "s/^keys:$/keys:\n  - \&dev age1js028xag70wpwpp47elpq50mjjv7zn7sxuwuhk8yltkjzqzdvq5qq8w8cy/" m/.sops.yaml
            mutant empty-secrets sh -c 'rm -rf m/secrets && mkdir m/secrets'
            mutant deployer-reaches-stibnite sh -c 'mkdir -p m/sops/secrets/stibnite-age.key/groups && ln -s ../../../groups/fleet-deployers m/sops/secrets/stibnite-age.key/groups/fleet-deployers'
            mutant deployer-reads-shared sh -c 'mkdir -p m/vars/shared/ntfy-alerter/token/users && ln -s ../../../../../sops/users/fleet-deployer m/vars/shared/ntfy-alerter/token/users/fleet-deployer'
            if [ -z "$deployerAge" ]; then
              mutant deployer-user-early sh -c 'mkdir -p m/sops/users/fleet-deployer && echo "[{\"publickey\":\"age1x\",\"type\":\"age\"}]" > m/sops/users/fleet-deployer/key.json'
            else
              mutant deployer-key-changed sh -c "sed -i 's/$deployerAge/$other/' m/sops/users/fleet-deployer/key.json"
              first=$(head -1 "$deployerTargetsPath")
              mutant deployer-group-missing rm "m/sops/secrets/$first-age.key/groups/fleet-deployers"
            fi

            touch "$out"
          '';
    };
}

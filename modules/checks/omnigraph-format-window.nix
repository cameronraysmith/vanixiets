# Behavioural check: the packaged omnigraph still opens magnetite's cluster
# root, and the storage-format floor recorded beside the root is the binary's.
#
# A cluster graph keeps the storage format it was created with: a normal open
# never migrates it, and `omnigraph upgrade` refuses cluster graphs (omnigraph
# 0.16.0 crates/omnigraph-cli/src/upgrade.rs). A release whose readable range
# no longer includes that format therefore cannot serve the root at all. The
# range is printed offline by `omnigraph version --json` as
# `internal_schema.serves` ([lowest, highest]; docs/user/install.md), so the
# check runs the packaged binary and compares it with
# services.omnigraph.cluster.createdAtFormat, the format magnetite's root was
# created at, and services.omnigraph.cluster.servesFloor, the floor the
# configuration records so that evaluation (which cannot run the binary) can
# warn while the root sits on the floor. Outcomes, first match wins:
#
#   createdAtFormat outside serves  fail: the root must be recreated
#   servesFloor != serves[0]        fail: update the recorded floor
#   otherwise                       pass
#
# An omnigraph update is the change that moves `serves`, so the pull request
# carrying it is where this fails.
{ self, lib, ... }:
let
  formatWindow =
    pkgs:
    {
      omnigraph,
      storageUri,
      createdAtFormat,
      servesFloor,
    }:
    pkgs.runCommand "omnigraph-format-window"
      {
        nativeBuildInputs = [
          omnigraph
          pkgs.jq
        ];
        meta.description = "behavioural check: the packaged omnigraph reads the storage format magnetite's cluster root was created at, and the recorded floor is the binary's";
      }
      ''
        set -euo pipefail
        export HOME="$TMPDIR/home" OMNIGRAPH_HOME="$TMPDIR/omnigraph-home"
        mkdir -p "$HOME" "$OMNIGRAPH_HOME"
        omnigraph version --json > version.json
        if ! read -r version lo hi < <(jq -er '
            [.version, .internal_schema.serves[0], .internal_schema.serves[1]]
            | if (.[0] | type) == "string" and (.[1:] | all(type == "number"))
              then map(tostring) | join(" ") else error("malformed") end' version.json); then
          cat version.json >&2
          echo "FAIL: omnigraph version --json reported no internal_schema.serves range" >&2
          exit 1
        fi
        created=${toString createdAtFormat}
        floor=${toString servesFloor}
        echo "omnigraph $version reads storage formats $lo-$hi; ${storageUri} was created at $created; recorded floor $floor"

        if [ "$created" -lt "$lo" ] || [ "$created" -gt "$hi" ]; then
          cat >&2 <<EOF
        FAIL: omnigraph $version reads storage formats $lo-$hi, and the graphs of
        ${storageUri} were created at format $created
        (services.omnigraph.cluster.createdAtFormat), so the server can no longer
        open this root. A cluster graph cannot be upgraded in place: recreate the
        root under a new suffix (services.omnigraph.storageUri) and set
        createdAtFormat to the format this omnigraph writes. A root holding
        anything but example data must first be exported with the omnigraph
        release that still reads it.
        EOF
          exit 1
        fi

        if [ "$floor" != "$lo" ]; then
          {
            echo "FAIL: omnigraph $version reads storage formats $lo-$hi, and the repository records floor $floor (services.omnigraph.cluster.servesFloor); update servesFloor to $lo."
            if [ "$created" = "$lo" ]; then
              echo "The root ${storageUri} was created at format $created, this release's floor: the next release that raises the floor will not open it, so plan its recreation."
            fi
          } >&2
          exit 1
        fi

        touch "$out"
      '';
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      omnigraph = self.nixosConfigurations.magnetite.config.services.omnigraph;
    in
    {
      # 4 to 6 s: six builds on magnetite's store, 2026-11-25, evaluation
      # included.
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-format-window.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-format-window = formatWindow pkgs {
          inherit (omnigraph) storageUri;
          inherit (omnigraph.cluster) createdAtFormat servesFloor;
          omnigraph = omnigraph.package;
        };
      };
    };
}

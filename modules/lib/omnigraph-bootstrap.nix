# Create-once bootstrap for an omnigraph cluster storage root.
#
# omnigraph-server refuses to start on a root without cluster state, and a
# root imported but never applied boots serving no graphs. Running
# `omnigraph cluster apply` automatically on every start would fix a fresh
# root, but it would also silently recreate an empty cluster over a root that
# was lost, which is why services.omnigraph keeps `cluster.apply.auto` off.
#
# This program separates the two cases with an initialization marker kept
# outside the root, so it survives loss of the root: strip trailing slashes
# from the storage URI, split it into parent and basename, and the marker is
# `<parent>/_omnigraph-markers/<basename>.initialized`
# (s3://sciexp/omnigraph/clusters/dev-graph-v9 ->
# s3://sciexp/omnigraph/clusters/_omnigraph-markers/dev-graph-v9.initialized).
# A sibling `<root>.initialized` would share the root's string prefix, so a
# prefix delete of the root would take the marker with it; a separate
# directory does not. The cluster state comes from
# `omnigraph cluster status --json`, which is read-only and lock-free:
#
#   state found,  marker present  no-op
#   state found,  marker absent   write the marker (adopt the existing root)
#   state absent, marker absent   run applyProgram, then write the marker
#   state absent, marker present  refuse: the root was lost; never apply
#
# A failed status call, an unreadable marker or a failed apply exits 1
# without writing the marker; systemd surfaces the failure, nothing retries.
#
# An s3:// root keeps its marker as an S3 object. Requests are path-style
# (`<endpoint>/<bucket>/<key>`) and SigV4-signed by curl, with the endpoint
# taken from AWS_ENDPOINT_URL_S3, else AWS_ENDPOINT_URL, the region from
# AWS_REGION and the credentials from AWS_ACCESS_KEY_ID and
# AWS_SECRET_ACCESS_KEY, the environment the omnigraph units already carry.
# The credentials reach curl through a config on stdin, not its argv. A plain
# path or file:// root keeps its marker as a local file. Any other root makes
# the program exit 1 naming the unsupported scheme, as does a root with no
# basename once trailing slashes are stripped (`s3://bucket/`, `/`), which
# has no parent to hold its marker.
#
# applyProgram is the caller's converge program (import tolerating existing
# state, then apply); it is invoked, never reimplemented here.
{ lib, ... }:
let
  markerDirName = "_omnigraph-markers";

  stripSlashes = s: if lib.hasSuffix "/" s then stripSlashes (lib.removeSuffix "/" s) else s;

  # { kind = "s3"; marker; bucket; key; } | { kind = "local"; marker; }
  # | { kind = "unsupported"; reason; }
  markerFor =
    storageUri:
    let
      unsupported = reason: {
        kind = "unsupported";
        inherit reason;
      };
      noBasename = unsupported "the storage root ${storageUri} has no basename after stripping trailing slashes, so it has no parent to hold its marker";
      siblingMarker =
        segments:
        lib.init segments
        ++ [
          markerDirName
          "${lib.last segments}.initialized"
        ];
    in
    if lib.hasPrefix "s3://" storageUri then
      let
        segments = lib.splitString "/" (stripSlashes (lib.removePrefix "s3://" storageUri));
        bucket = builtins.head segments;
        key = lib.concatStringsSep "/" (siblingMarker (builtins.tail segments));
      in
      if builtins.length segments < 2 then
        noBasename
      else if builtins.match "[a-z0-9][a-z0-9.-]*" bucket == null then
        unsupported "cannot parse an S3 bucket name from ${storageUri}"
      else if builtins.match "[A-Za-z0-9._~-]+(/[A-Za-z0-9._~-]+)*" key == null then
        unsupported "the S3 key of ${storageUri} must use only A-Za-z0-9._~- in non-empty segments"
      else
        {
          kind = "s3";
          marker = "s3://${bucket}/${key}";
          inherit bucket key;
        }
    else if
      lib.hasPrefix "file://" storageUri || builtins.match "[A-Za-z][A-Za-z0-9+.-]*:.*" storageUri == null
    then
      let
        path = stripSlashes (lib.removePrefix "file://" storageUri);
        segments = lib.splitString "/" path;
      in
      if path == "" then
        noBasename
      else
        {
          kind = "local";
          marker = lib.concatStringsSep "/" (siblingMarker segments);
        }
    else
      unsupported "unsupported storage scheme in ${storageUri}; only s3://, file:// and plain paths are supported";
in
{
  flake.lib.omnigraphBootstrap =
    pkgs:
    {
      omnigraph,
      applyProgram,
      configDir,
      storageUri,
    }:
    let
      location = markerFor storageUri;

      s3Functions = ''
        s3_endpoint=''${AWS_ENDPOINT_URL_S3:-''${AWS_ENDPOINT_URL:-}}
        for required in s3_endpoint AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
          if [ -z "''${!required:-}" ]; then
            err "cannot read the marker $marker: $required is unset (the endpoint comes from AWS_ENDPOINT_URL_S3 or AWS_ENDPOINT_URL); nothing was applied"
            exit 1
          fi
        done
        object_url="''${s3_endpoint%/}/"${lib.escapeShellArg "${location.bucket}/${location.key}"}

        # Prints the HTTP status. The credentials go through a curl config on
        # stdin so they never appear in the process list.
        s3_request() {
          local user=''${AWS_ACCESS_KEY_ID}:''${AWS_SECRET_ACCESS_KEY}
          user=''${user//\\/\\\\}
          user=''${user//\"/\\\"}
          printf 'user = "%s"\n' "$user" \
            | curl --config - --silent --show-error \
                --connect-timeout 10 --max-time 60 \
                --output /dev/null --write-out '%{http_code}' \
                --aws-sigv4 "aws:amz:''${AWS_REGION}:s3" \
                "$@" "$object_url"
        }

        probe_marker() {
          local code
          if ! code=$(s3_request --head); then
            err "HEAD $object_url for the marker $marker failed; nothing was applied"
            exit 1
          fi
          case "$code" in
            200) marker_present=true ;;
            404) marker_present=false ;;
            *)
              err "HEAD $object_url for the marker $marker answered HTTP $code; cannot tell whether the root was initialized, nothing was applied"
              exit 1
              ;;
          esac
        }

        write_marker() {
          local code
          if ! code=$(s3_request --request PUT \
              --header 'Content-Type: application/json' \
              --data-binary "$(marker_body "$1")"); then
            err "PUT $object_url for the marker $marker failed"
            exit 1
          fi
          case "$code" in
            2??) ;;
            *)
              err "PUT $object_url for the marker $marker answered HTTP $code"
              exit 1
              ;;
          esac
        }
      '';

      localFunctions = ''
        marker_dir=$(dirname -- "$marker")

        probe_marker() {
          if [ -e "$marker" ]; then
            marker_present=true
          elif [ -d "$marker_dir" ] && [ ! -x "$marker_dir" ]; then
            err "cannot search $marker_dir for the marker $marker; nothing was applied"
            exit 1
          else
            marker_present=false
          fi
        }

        write_marker() {
          mkdir -p -- "$marker_dir"
          marker_body "$1" > "$marker.tmp.$$"
          mv -f -- "$marker.tmp.$$" "$marker"
        }
      '';

      bootstrapText = ''
        storage_uri=${lib.escapeShellArg storageUri}
        marker=${lib.escapeShellArg location.marker}
        config_dir=${lib.escapeShellArg (toString configDir)}

        say() { printf 'omnigraph-cluster-bootstrap: %s\n' "$*"; }
        err() { printf 'omnigraph-cluster-bootstrap: %s\n' "$*" >&2; }

        marker_body() {
          jq -cn --arg uri "$storage_uri" --arg reason "$1" \
            --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{storage_uri: $uri, reason: $reason, written_at: $at}'
        }

        ${if location.kind == "s3" then s3Functions else localFunctions}

        if ! status_output=$(omnigraph cluster status --config "$config_dir" --json); then
          printf '%s\n' "$status_output" >&2
          err "omnigraph cluster status failed for $storage_uri; nothing was applied"
          exit 1
        fi
        if ! state_found=$(jq -r '.state_observations.state_found' <<<"$status_output") \
          || { [ "$state_found" != true ] && [ "$state_found" != false ]; }; then
          printf '%s\n' "$status_output" >&2
          err "omnigraph cluster status reported no boolean .state_observations.state_found for $storage_uri; nothing was applied"
          exit 1
        fi

        marker_present=
        probe_marker

        if [ "$state_found" = true ] && [ "$marker_present" = true ]; then
          say "cluster state and marker $marker present; nothing to do"
        elif [ "$state_found" = true ]; then
          write_marker adopted-existing-root
          say "cluster state present without a marker; adopted $storage_uri and wrote $marker"
        elif [ "$marker_present" = false ]; then
          say "no cluster state and no marker: initializing $storage_uri"
          if ! ${lib.escapeShellArg (toString applyProgram)}; then
            err "initializing $storage_uri failed; the marker $marker was not written, so the next start retries"
            exit 1
          fi
          write_marker first-initialization
          say "initialized $storage_uri and wrote $marker"
        else
          cat >&2 <<EOF
        omnigraph-cluster-bootstrap: REFUSING TO INITIALIZE $storage_uri
        The marker $marker exists, so this storage root was initialized before,
        but it no longer holds cluster state (__cluster/state.json): the root was
        lost or emptied. Applying now would create a new, empty cluster in its
        place, so nothing was applied.
        Restore the root from backup, then: systemctl restart omnigraph-cluster-bootstrap
        To deliberately start over with an empty cluster, delete the marker
        $marker and then: systemctl restart omnigraph-cluster-bootstrap
        EOF
          exit 1
        fi
      '';

      unsupportedText = ''
        printf 'omnigraph-cluster-bootstrap: %s; nothing was applied\n' ${lib.escapeShellArg location.reason} >&2
        exit 1
      '';
    in
    pkgs.writeShellApplication {
      name = "omnigraph-cluster-bootstrap";
      runtimeInputs = [
        omnigraph
        pkgs.curl
        pkgs.jq
        pkgs.coreutils
      ];
      text = if location.kind == "unsupported" then unsupportedText else bootstrapText;
    };
}

# Create-once bootstrap for an omnigraph cluster storage root, and the
# one-time seed load of an example graph the bootstrap created.
#
# omnigraph-server refuses to start on a root without applied cluster state.
# Running `omnigraph cluster apply` automatically on every start would fix a
# fresh root, but it would also silently recreate an empty cluster over a root
# that was lost, which is why services.omnigraph keeps `cluster.apply.auto`
# off.
#
# This program separates the two cases with an initialization marker kept
# outside the root, so it survives loss of the root: strip trailing slashes
# from the storage URI, split it into parent and basename, and the marker is
# `<parent>/_omnigraph-markers/<basename>.initialized`
# (s3://sciexp/omnigraph/clusters/cookbooks-f17 ->
# s3://sciexp/omnigraph/clusters/_omnigraph-markers/cookbooks-f17.initialized).
# A sibling `<root>.initialized` would share the root's string prefix, so a
# prefix delete of the root would take the marker with it; a separate
# directory does not. The cluster state comes from
# `omnigraph --target <storageUri> cluster status --json`, which is read-only
# and takes no lock. It succeeds with the ledger's status when the root holds
# state, and fails with the single diagnostic `state_missing` when it does not;
# any other outcome is an error:
#
#   state found,  marker present  no-op
#   state found,  marker absent   write the marker (adopt the existing root)
#   state absent, marker absent   create a local root's directory if it is
#                                 missing (never for s3://), write a
#                                 seed-pending marker per seeded graph, run
#                                 applyProgram, then write the marker
#   state absent, marker present  refuse: the root was lost; never apply
#
# A failed status call, an unreadable marker or a failed apply exits 1
# without writing the marker; systemd surfaces the failure, nothing retries.
#
# Seed-pending markers. Each graph in `seededGraphs` gets
# `<parent>/_omnigraph-markers/<basename>.<graph>.seed-pending`, written only
# on first initialization and before the apply, so every point at which that
# branch can stop leaves the marker beside a root that the seed load still
# has to fill:
#
#   stop before the apply converges  no state, no marker: the next start
#                                    takes this branch again and rewrites the
#                                    pending marker
#   stop after the apply converges,  state, no marker: the next start adopts
#   before the marker is written     the root, and the pending marker written
#                                    before the apply is still there
#
# The adopt and no-op branches never write one, so a root initialized
# earlier, or by hand, is never seeded. flake.lib.omnigraphSeed loads the seed
# while the pending marker exists and deletes it once the load is known to
# have committed.
#
# An s3:// root keeps its markers as S3 objects. Requests are path-style
# (`<endpoint>/<bucket>/<key>`) and SigV4-signed by curl, with the endpoint
# taken from AWS_ENDPOINT_URL_S3, else AWS_ENDPOINT_URL, the region from
# AWS_REGION and the credentials from AWS_ACCESS_KEY_ID and
# AWS_SECRET_ACCESS_KEY, the environment the omnigraph units already carry.
# The credentials reach curl through a config on stdin, not its argv. A plain
# path or file:// root keeps its markers as local files. Any other root makes
# the program exit 1 naming the unsupported scheme, as does a root with no
# basename once trailing slashes are stripped (`s3://bucket/`, `/`), which
# has no parent to hold its marker.
#
# applyProgram is the caller's converge program (apply, then release an
# admission lock the apply retained); it is invoked, never reimplemented here.
{ lib, ... }:
let
  markerDirName = "_omnigraph-markers";

  stripSlashes = s: if lib.hasSuffix "/" s then stripSlashes (lib.removeSuffix "/" s) else s;

  # The marker `<parent>/_omnigraph-markers/<basename>.<suffix>` of a storage
  # root.
  # { kind = "s3"; marker; } | { kind = "local"; marker; }
  # | { kind = "unsupported"; reason; }
  markerFor =
    storageUri: suffix:
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
          "${lib.last segments}.${suffix}"
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
          root = path;
          marker = lib.concatStringsSep "/" (siblingMarker segments);
        }
    else
      unsupported "unsupported storage scheme in ${storageUri}; only s3://, file:// and plain paths are supported";

  # The seed-pending marker of one graph, or the reason it cannot have one.
  pendingMarkerFor =
    storageUri: graph:
    if builtins.match "[A-Za-z0-9_-]+" graph == null then
      {
        kind = "unsupported";
        reason = "the graph id ${graph} must use only A-Za-z0-9_- to name its seed-pending marker";
      }
    else
      markerFor storageUri "${graph}.seed-pending";

  # Shell functions over markers named by URI: probe_marker <uri> sets
  # marker_present, write_marker <uri> <body>, delete_marker <uri>. Each
  # failure names the marker and ends with $nothing_done.
  s3Functions = ''
    s3_endpoint=''${AWS_ENDPOINT_URL_S3:-''${AWS_ENDPOINT_URL:-}}
    s3_require_environment() {
      local required
      for required in s3_endpoint AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
        if [ -z "''${!required:-}" ]; then
          err "cannot read the marker $1: $required is unset (the endpoint comes from AWS_ENDPOINT_URL_S3 or AWS_ENDPOINT_URL); $nothing_done"
          exit 1
        fi
      done
    }

    # Prints the HTTP status. The credentials go through a curl config on
    # stdin so they never appear in the process list.
    s3_request() { # <marker uri> <curl arguments>
      local object_url="''${s3_endpoint%/}/''${1#s3://}"
      shift
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

    probe_marker() { # <marker uri>
      local code
      s3_require_environment "$1"
      if ! code=$(s3_request "$1" --head); then
        err "HEAD for the marker $1 failed; $nothing_done"
        exit 1
      fi
      case "$code" in
        200) marker_present=true ;;
        404) marker_present=false ;;
        *)
          err "HEAD for the marker $1 answered HTTP $code; cannot tell whether it exists, $nothing_done"
          exit 1
          ;;
      esac
    }

    write_marker() { # <marker uri> <body>
      local code
      if ! code=$(s3_request "$1" --request PUT \
          --header 'Content-Type: application/json' \
          --data-binary "$2"); then
        err "PUT for the marker $1 failed"
        exit 1
      fi
      case "$code" in
        2??) ;;
        *)
          err "PUT for the marker $1 answered HTTP $code"
          exit 1
          ;;
      esac
    }

    delete_marker() { # <marker uri>
      local code
      if ! code=$(s3_request "$1" --request DELETE); then
        err "DELETE for the marker $1 failed"
        exit 1
      fi
      case "$code" in
        2??) ;;
        *)
          err "DELETE for the marker $1 answered HTTP $code"
          exit 1
          ;;
      esac
    }
  '';

  localFunctions = ''
    probe_marker() { # <marker path>
      local marker_dir
      marker_dir=$(dirname -- "$1")
      if [ -e "$1" ]; then
        marker_present=true
      elif [ -d "$marker_dir" ] && [ ! -x "$marker_dir" ]; then
        err "cannot search $marker_dir for the marker $1; $nothing_done"
        exit 1
      else
        marker_present=false
      fi
    }

    write_marker() { # <marker path> <body>
      mkdir -p -- "$(dirname -- "$1")"
      printf '%s\n' "$2" > "$1.tmp.$$"
      mv -f -- "$1.tmp.$$" "$1"
    }

    delete_marker() { # <marker path>
      rm -f -- "$1"
    }
  '';

  markerFunctions = kind: if kind == "s3" then s3Functions else localFunctions;

  unsupportedProgram =
    pkgs: name: reason: what:
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        printf '%s: %s; %s\n' ${lib.escapeShellArg name} ${lib.escapeShellArg reason} ${lib.escapeShellArg what} >&2
        exit 1
      '';
    };
in
{
  flake.lib.omnigraphBootstrap =
    pkgs:
    {
      omnigraph,
      applyProgram,
      storageUri,
      seededGraphs ? [ ],
    }:
    let
      location = markerFor storageUri "initialized";
      pending = map (graph: {
        inherit graph;
        location = pendingMarkerFor storageUri graph;
      }) seededGraphs;
      unsupported = lib.findFirst (l: l.kind == "unsupported") null (
        [ location ] ++ map (p: p.location) pending
      );

      bootstrapText = ''
        storage_uri=${lib.escapeShellArg storageUri}
        marker=${lib.escapeShellArg location.marker}
        pending_markers=(${lib.escapeShellArgs (map (p: p.location.marker) pending)})
        pending_graphs=(${lib.escapeShellArgs (map (p: p.graph) pending)})
        nothing_done="nothing was applied"

        say() { printf 'omnigraph-cluster-bootstrap: %s\n' "$*"; }
        err() { printf 'omnigraph-cluster-bootstrap: %s\n' "$*" >&2; }

        marker_body() {
          jq -cn --arg uri "$storage_uri" --arg reason "$1" \
            --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{storage_uri: $uri, reason: $reason, written_at: $at}'
        }

        pending_body() {
          jq -cn --arg uri "$storage_uri" --arg graph "$1" \
            --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{storage_uri: $uri, graph: $graph, reason: "first-initialization", written_at: $at}'
        }

        ${markerFunctions location.kind}

        status_rc=0
        status_output=$(omnigraph --target "$storage_uri" cluster status --json) || status_rc=$?
        if [ "$status_rc" -eq 0 ] \
          && jq -e '.ledger_id | type == "string"' <<<"$status_output" >/dev/null 2>&1; then
          state_found=true
        elif [ "$status_rc" -ne 0 ] \
          && jq -e '.ok == false and ([.diagnostics[]?.code] == ["state_missing"])' \
            <<<"$status_output" >/dev/null 2>&1; then
          state_found=false
        else
          printf '%s\n' "$status_output" >&2
          err "omnigraph cluster status for $storage_uri exited $status_rc without a ledger status or a state_missing refusal; nothing was applied"
          exit 1
        fi

        marker_present=
        probe_marker "$marker"

        if [ "$state_found" = true ] && [ "$marker_present" = true ]; then
          say "cluster state and marker $marker present; nothing to do"
        elif [ "$state_found" = true ]; then
          write_marker "$marker" "$(marker_body adopted-existing-root)"
          say "cluster state present without a marker; adopted $storage_uri and wrote $marker"
        elif [ "$marker_present" = false ]; then
          say "no cluster state and no marker: initializing $storage_uri"
          ${lib.optionalString (location.kind == "local") ''
            # omnigraph's apply refuses a local root whose directory does not
            # exist. This runs as the unit's user, inside its StateDirectory
            # (the only local storage the units can write), so the directory
            # is owned by the user every omnigraph unit runs as, mode 0700.
            root_dir=${lib.escapeShellArg location.root}
            if [ ! -e "$root_dir" ]; then
              (umask 0077 && mkdir -p -- "$root_dir")
              say "created the local storage root directory $root_dir"
            fi
          ''}
          for i in "''${!pending_markers[@]}"; do
            write_marker "''${pending_markers[$i]}" "$(pending_body "''${pending_graphs[$i]}")"
            say "marked the seed of graph ''${pending_graphs[$i]} pending: ''${pending_markers[$i]}"
          done
          if ! ${lib.escapeShellArg (toString applyProgram)}; then
            err "initializing $storage_uri failed; the marker $marker was not written, so the next start retries"
            exit 1
          fi
          write_marker "$marker" "$(marker_body first-initialization)"
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
    in
    if unsupported != null then
      unsupportedProgram pkgs "omnigraph-cluster-bootstrap" unsupported.reason "nothing was applied"
    else
      pkgs.writeShellApplication {
        name = "omnigraph-cluster-bootstrap";
        runtimeInputs = [
          omnigraph
          pkgs.curl
          pkgs.jq
          pkgs.coreutils
        ];
        text = bootstrapText;
      };

  # Loads `seedFile` into `graph` through the running server, once, while the
  # graph's seed-pending marker exists; see the header for when the bootstrap
  # writes it.
  #
  # The load is `POST <serverUrl>/graphs/<graph>/load/ndjson?mode=append&branch=main`
  # with the HTTP contract the packaged omnigraph reports
  # (`omnigraph version --json`, `http_contract`) and the bearer token read
  # from `$CREDENTIALS_DIRECTORY/<tokenCredential>`, passed to curl in a config
  # on stdin. The mode is explicit because the HTTP default is `merge`. One
  # load is one graph commit, all or nothing, and `append` refuses an id that
  # already exists, so:
  #
  #   marker absent                         exit 0, nothing sent
  #   200 with an append commit             delete the marker, exit 0
  #   409 key_conflict, effects none        the seed is already there (an
  #                                         earlier attempt committed and its
  #                                         answer was lost): delete the
  #                                         marker, exit 0
  #   a refusal with effects unknown        exit 1, keep the marker, and name
  #                                         the graph, the marker and the
  #                                         command that clears it once a
  #                                         person has checked the graph holds
  #                                         its seed
  #   anything else (another status, a      exit 1 and keep the marker; the
  #   timeout, no connection, a marker      next start retries
  #   that cannot be read)
  #
  # A replay meets key_conflict only when the server checks keys before
  # anything else. omnigraph 0.16.0 checks edge cardinality first: replaying a
  # seed that writes edges under a `@card` maximum (at most one edge of a type
  # per source, say) into a graph that already holds it is refused with
  # `400 bad_request`, a `@card` violation, and effects `unknown`, though the
  # graph does not change, and the load API takes no idempotency key that
  # would return the first result instead. Such a seed's unit therefore stays
  # failed after a committed load whose answer was lost, until a person checks
  # the graph and clears the marker with the command the unit prints:
  # `<this program> --clear-pending` run through `systemd-run` with the unit's
  # storage environment, which deletes the marker and loads nothing. The
  # request timeout keeps that case rare: 600 s, against requests to R2 that
  # stall for 8 to 20 s (about 50 s under overload) and seed loads that take
  # well under a second against a local root.
  #
  # Nothing here deletes, recreates or applies a graph or a root.
  flake.lib.omnigraphSeed =
    pkgs:
    {
      omnigraph,
      storageUri,
      graph,
      seedFile,
      serverUrl,
      tokenCredential,
      timeout ? 600,
      # The storage credentials file and environment of the unit, which the
      # printed clearing command passes on to its run.
      environmentFile ? null,
      environment ? { },
    }:
    let
      location = pendingMarkerFor storageUri graph;
      name = "omnigraph-seed-${graph}";
    in
    if location.kind == "unsupported" then
      unsupportedProgram pkgs name location.reason "nothing was loaded"
    else
      pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = [
          omnigraph
          pkgs.curl
          pkgs.jq
          pkgs.coreutils
        ];
        text = ''
          storage_uri=${lib.escapeShellArg storageUri}
          graph=${lib.escapeShellArg graph}
          marker=${lib.escapeShellArg location.marker}
          load_url=${lib.escapeShellArg "${serverUrl}/graphs/${graph}/load/ndjson?mode=append&branch=main"}
          nothing_done="nothing was loaded"

          say() { printf '%s: %s\n' ${lib.escapeShellArg name} "$*"; }
          err() { printf '%s: %s\n' ${lib.escapeShellArg name} "$*" >&2; }
          clear_command=${
            lib.escapeShellArg (
              lib.concatStringsSep " " (
                [
                  "systemd-run"
                  "--wait"
                  "--pipe"
                  "--collect"
                ]
                ++ lib.optional (environmentFile != null) (
                  lib.escapeShellArg "--property=EnvironmentFile=${toString environmentFile}"
                )
                ++ lib.mapAttrsToList (k: v: lib.escapeShellArg "--setenv=${k}=${v}") environment
              )
            )
          }" $(readlink -f -- "$0") --clear-pending"

          ${markerFunctions location.kind}

          if [ "''${1-}" = --clear-pending ]; then
            marker_present=
            probe_marker "$marker"
            if [ "$marker_present" = false ]; then
              say "no seed pending for graph $graph of $storage_uri ($marker is absent); nothing to clear"
            else
              delete_marker "$marker"
              say "cleared the pending seed of graph $graph: deleted $marker; $nothing_done"
            fi
            exit 0
          fi
          marker_present=
          probe_marker "$marker"
          if [ "$marker_present" = false ]; then
            say "no seed pending for graph $graph of $storage_uri ($marker is absent); nothing to do"
            exit 0
          fi

          token_file="''${CREDENTIALS_DIRECTORY:-}/"${lib.escapeShellArg tokenCredential}
          if [ -z "''${CREDENTIALS_DIRECTORY:-}" ] || [ ! -r "$token_file" ]; then
            err "the bearer token credential ${tokenCredential} is not readable; $nothing_done and $marker is kept"
            exit 1
          fi
          if ! contract=$(omnigraph version --json | jq -er '.http_contract | strings'); then
            err "omnigraph version --json reported no http_contract; $nothing_done and $marker is kept"
            exit 1
          fi

          response=$(mktemp)
          trap 'rm -f -- "$response"' EXIT
          say "seed pending ($marker): loading ${seedFile} into graph $graph with mode append"
          token=$(cat -- "$token_file")
          token=''${token//\\/\\\\}
          token=''${token//\"/\\\"}
          if ! code=$(printf 'header = "Authorization: Bearer %s"\n' "$token" \
              | curl --config - --silent --show-error \
                  --connect-timeout 10 --max-time ${toString timeout} \
                  --request POST \
                  --header "Omnigraph-Http-Api: $contract" \
                  --header 'Content-Type: application/x-ndjson' \
                  --data-binary @${seedFile} \
                  --output "$response" --write-out '%{http_code}' \
                  "$load_url"); then
            err "the load request to $load_url did not complete; whether it committed is unknown, so $marker is kept and the next start retries"
            exit 1
          fi

          if [ "$code" = 200 ] \
            && jq -e '.mode == "append" and (.commit.graph_commit_id | type == "string")' "$response" >/dev/null 2>&1; then
            delete_marker "$marker"
            say "loaded $(jq -r '.total_entities' "$response") entities into graph $graph in commit $(jq -r '.commit.graph_commit_id' "$response"); deleted $marker"
          elif [ "$code" = 409 ] \
            && jq -e '(.key_conflict | type == "object") and .disposition.effects == "none"' "$response" >/dev/null 2>&1; then
            delete_marker "$marker"
            say "graph $graph already holds the seed (append refused with key_conflict: $(jq -r '.error // .message // empty' "$response")); deleted $marker"
          elif jq -e '.disposition.effects == "unknown"' "$response" >/dev/null 2>&1; then
            cat -- "$response" >&2
            printf '\n' >&2
            cat >&2 <<EOF
          ${name}: the load into graph $graph answered HTTP $code: $(jq -r '.error // .message // empty' "$response")
          The server cannot say whether the load changed anything. The pending marker
          $marker
          is kept, so the next start loads again. A seed that writes edges under a
          @card maximum is refused this way at every start once the graph holds it,
          which is the case after an earlier load committed and its answer was lost.
          Check whether graph $graph holds its seed: its snapshot,
          GET ${serverUrl}/graphs/$graph/snapshot as an actor that may read it, lists
          the entity count of every type. If it does, clear the marker as root with:
            $clear_command
          EOF
            exit 1
          else
            cat -- "$response" >&2
            printf '\n' >&2
            err "the load answered HTTP $code without an append commit or a key_conflict that changed nothing; $marker is kept and the next start retries"
            exit 1
          fi
        '';
      };
}

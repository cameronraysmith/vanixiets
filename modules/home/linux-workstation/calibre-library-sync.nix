# Read-only Google Drive remote and an on-demand Drive -> pyrite mirror of the
# Calibre libraries the operator maintains on stibnite. calibre's FAQ warns
# that a library kept inside a cloud-sync folder loses data, so pyrite never
# opens the Drive copy: it mirrors it into ~/Calibre/<library> and only reads
# the mirror. Local edits there are overwritten by the next sync.
#
# The mirror runs only when the operator asks for it, never on a timer, so a
# sync cannot start while Calibre has a mirrored metadata.db open. Point
# Calibre at ~/Calibre/<library> once through "Switch/create library"; that
# list lives in Calibre's own mutable configuration and is not declared here.
#
# The remote lives in its own rclone config, rendered by sops-nix from a
# template, rather than in programs.rclone: home-manager's rclone-config
# service injects secrets as `rclone config update` arguments, and pyrite's
# /proc lets other accounts read every process's argv. The secrets come from
# the user's default sops file (crs58's, which cameron folds to); a graphical
# home whose sops file lacks the two keys fails at build time naming them.
{ ... }:
{
  flake.modules.homeManager.linux-workstation =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      libraryRoot = "${config.home.homeDirectory}/Calibre";
      gdriveConfig = config.sops.templates."rclone-gdrive.conf".path;

      # Ad-hoc access to the Drive remote, e.g. `rclone-gdrive lsd gdrive:Library`.
      rclone-gdrive = pkgs.writeShellApplication {
        name = "rclone-gdrive";
        runtimeInputs = [ config.programs.rclone.package ];
        text = ''
          exec rclone --config ${lib.escapeShellArg gdriveConfig} "$@"
        '';
      };

      calibre-library-sync = pkgs.writeShellApplication {
        name = "calibre-library-sync";
        runtimeInputs = [
          config.programs.rclone.package
          pkgs.procps
          pkgs.coreutils
          pkgs.util-linux
          pkgs.jq
        ];
        text = ''
          readonly remote_root="gdrive:Library"
          readonly local_root=${lib.escapeShellArg libraryRoot}
          readonly all_libraries=(theory experiment philosophy)

          # A library removal in calibre deletes a book's format files, its
          # cover, metadata.opf and its directories: a handful of files per
          # book. 100 per library admits a session of a few dozen removals,
          # yet stops a sync from an emptied or mistyped Drive folder from
          # erasing a library of ~1000-2500 files.
          readonly max_delete=100

          # Size plus modification time, rclone's default, rather than
          # --checksum: Drive keeps the modification time the uploader set at
          # millisecond precision, and rclone falls back to Drive's MD5 when
          # sizes match but times differ. --checksum would instead read and
          # hash all ~16 GB of the local mirror on every run. Four transfers
          # and eight checkers are rclone's defaults, which stay under Drive's
          # per-user request rate; --fast-list lists each library in a few
          # recursive calls instead of one call per book directory.
          readonly common=(--config ${lib.escapeShellArg gdriveConfig} --drive-skip-gdocs --fast-list --transfers 4 --checkers 8)

          usage() {
            cat <<'EOF'
          Usage: calibre-library-sync [options]

          Mirror the Calibre libraries from gdrive:Library/<name> into
          ~/Calibre/<name> (one-way: Drive is the source of truth). Shows a dry
          run first and asks before changing anything.

          Options:
            --dry-run          show what would change, then stop
            --yes, -y          skip the confirmation prompt
            --bwlimit RATE     pass a bandwidth limit to rclone (e.g. 2M);
                               default unlimited
            --library NAME     only this library; repeatable
                               (theory, experiment, philosophy)
            -h, --help         show this help

          Refuses to run while Calibre (GUI, calibre-parallel or calibre-server)
          is running for this user.
          EOF
          }

          die() {
            echo "calibre-library-sync: $*" >&2
            exit 1
          }

          libraries=()
          add_library() {
            local name=$1 known existing
            for known in "''${all_libraries[@]}"; do
              if [[ $name == "$known" ]]; then
                for existing in "''${libraries[@]}"; do
                  [[ $existing == "$name" ]] && return 0
                done
                libraries+=("$name")
                return 0
              fi
            done
            die "unknown library '$name' (expected one of: ''${all_libraries[*]})"
          }

          assume_yes=0
          dry_run_only=0
          bwlimit=""
          while (($#)); do
            case $1 in
              --yes | -y) assume_yes=1 ;;
              --dry-run) dry_run_only=1 ;;
              --bwlimit)
                (($# >= 2)) || die "--bwlimit needs a rate"
                bwlimit=$2
                shift
                ;;
              --bwlimit=*) bwlimit=''${1#*=} ;;
              --library)
                (($# >= 2)) || die "--library needs a name"
                add_library "$2"
                shift
                ;;
              --library=*) add_library "''${1#*=}" ;;
              -h | --help)
                usage
                exit 0
                ;;
              *)
                usage >&2
                die "unknown argument: $1"
                ;;
            esac
            shift
          done
          if ((''${#libraries[@]} == 0)); then
            libraries=("''${all_libraries[@]}")
          fi

          # Matches the GUI, calibre-parallel and calibre-server whether the
          # command line shows the wrapper (.../bin/calibre) or the Python
          # script it execs (.../bin/.calibre-wrapped), from any store path.
          # This script's own command line ends in /bin/calibre-library-sync,
          # which the pattern rejects, and pgrep never reports itself.
          require_calibre_closed() {
            local status=0
            pgrep -u "$(id -u)" -f '/bin/\.?calibre(-parallel|-server)?(-wrapped)?( |$)' >/dev/null || status=$?
            case $status in
              0) die "Calibre is running; quit it (and any calibre-server) before syncing" ;;
              1) ;;
              *) die "pgrep failed with status $status" ;;
            esac
          }

          human() {
            numfmt --to=iec --suffix=B "$1"
          }

          require_calibre_closed

          log=$(mktemp)
          trap 'rm -f "$log"' EXIT

          # The dry run omits --max-delete so the summary reports every
          # deletion; the guard is enforced on that count below and again by
          # rclone during the real run.
          total=0
          over_guard=()
          echo "Dry run: gdrive:Library -> $local_root"
          for library in "''${libraries[@]}"; do
            if ! rclone sync --dry-run "''${common[@]}" \
              --use-json-log --log-level NOTICE --stats 0 \
              "$remote_root/$library" "$local_root/$library" 2>"$log"; then
              jq -Rr '. as $line | (try fromjson catch {level: "error", msg: $line}) | select(.level == "error") | .msg' <"$log" >&2
              die "dry run of '$library' failed; nothing was changed"
            fi
            summary=$(jq -Rnr '
              [inputs | fromjson? | select(.skipped == "copy" or .skipped == "delete")] as $actions
              | [ ($actions | map(select(.skipped == "copy")) | length),
                  ($actions | map(select(.skipped == "copy") | .size // 0) | add // 0),
                  ($actions | map(select(.skipped == "delete")) | length),
                  ($actions | map(select(.skipped == "delete") | .size // 0) | add // 0) ]
              | @tsv' <"$log")
            read -r copies copy_bytes deletes delete_bytes <<<"$summary"
            printf '  %-11s copy %5d files (%s)   delete %5d files (%s)\n' \
              "$library" "$copies" "$(human "$copy_bytes")" "$deletes" "$(human "$delete_bytes")"
            total=$((total + copies + deletes))
            if ((deletes > max_delete)); then
              over_guard+=("$library")
            fi
          done

          if ((''${#over_guard[@]} > 0)); then
            die "more than $max_delete deletions in: ''${over_guard[*]}; check gdrive:Library before syncing"
          fi
          if ((total == 0)); then
            echo "Mirror is up to date."
            exit 0
          fi
          if ((dry_run_only)); then
            exit 0
          fi

          if ((!assume_yes)); then
            [[ -t 0 ]] || die "stdin is not a terminal; pass --yes to sync without a prompt"
            answer=""
            read -r -p "Sync these changes into $local_root? [y/N] " answer || true
            case $answer in
              y | Y | yes | YES) ;;
              *)
                echo "Not syncing."
                exit 0
                ;;
            esac
          fi

          # Calibre may have been opened while the prompt waited.
          require_calibre_closed
          mkdir -p "$local_root"

          rate=()
          if [[ -n $bwlimit ]]; then
            rate=(--bwlimit "$bwlimit")
          fi
          progress=(--stats 10s --stats-one-line)
          if [[ -t 1 ]]; then
            progress=(--progress)
          fi

          # Best-effort class at its lowest level rather than the idle class:
          # idle I/O can starve indefinitely while the desktop is busy, and the
          # network, not the disk, bounds this job anyway.
          failed=()
          for library in "''${libraries[@]}"; do
            echo "Syncing $library"
            if ! nice -n 10 ionice -c 2 -n 7 rclone sync "''${common[@]}" \
              --max-delete "$max_delete" "''${rate[@]}" \
              --log-level NOTICE "''${progress[@]}" \
              "$remote_root/$library" "$local_root/$library"; then
              failed+=("$library")
            fi
          done
          if ((''${#failed[@]} > 0)); then
            die "sync failed for: ''${failed[*]}"
          fi
          echo "Done."
        '';
      };
    in
    {
      sops.secrets = {
        rclone-gdrive-client-secret.mode = "0400";
        rclone-gdrive-token.mode = "0400";
      };

      # drive.readonly makes the credential unable to modify Drive, whatever
      # rclone is asked to do with this remote. The token is rclone's
      # single-line JSON, as an INI value must be. 0600 rather than sops-nix's
      # 0400 lets rclone write refreshed access tokens back; the next
      # activation renders the file afresh from sops, whose refresh token
      # stays valid.
      sops.templates."rclone-gdrive.conf" = {
        mode = "0600";
        content = ''
          [gdrive]
          type = drive
          client_id = 257102176304-ch96da6l1f53lg9tp23u991hhfn7pb1j.apps.googleusercontent.com
          scope = drive.readonly
          client_secret = ${config.sops.placeholder.rclone-gdrive-client-secret}
          token = ${config.sops.placeholder.rclone-gdrive-token}
        '';
      };

      home.packages = [
        calibre-library-sync
        rclone-gdrive
      ];
    };
}

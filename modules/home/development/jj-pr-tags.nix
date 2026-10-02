# Pull request numbers next to bookmarks in `jj log` and jjui, kept current in
# the background, plus jjui keys to open, enqueue, and dequeue a bookmark's PR.
#
# jj has no forge integration, so `jj-pr-sync` caches `gh pr list` as a jj
# config file in conf.d scoped to one repository (`--when.repositories`); the
# commit-labels template reads it. Running it once in a repository registers
# the repository; a user service then refreshes every registered repository
# every five minutes. A failed refresh keeps the previous mapping, so being
# offline or signed out leaves tags stale rather than gone.
#
# Tags read `#N` for an open PR, `#N⇡` for an open PR queued for gitea-mq
# (auto-merge enabled or labelled merge-queue), `#N✓` merged, `#N✗` closed.
{ ... }:
let
  # Verbatim body of jj's builtin `format_commit_labels(commit)` alias
  # (cli/src/config/templates.toml); jj-pr-tags-rehearsal fails when the
  # packaged jj changes it.
  builtinCommitLabels = ''
    separate(" ",
      coalesce(
        if(commit.hidden(), label("hidden", "(hidden)")),
        if(commit.divergent(), label("divergent", "(divergent)")),
      ),
      if(commit.conflict(), label("conflict", "(conflict)")),
    )
  '';

  prTag = name: ''config("pr-numbers." ++ json(${name}))'';

  commitLabels = ''
    separate(" ",
      ${builtinCommitLabels},
      commit.bookmarks().filter(|b| ${prTag "b.name()"}).map(|b|
        label("pr", ${prTag "b.name()"}.as_string())
      ).join(" "),
    )
  '';

  refreshInterval = 300;

  mkSync =
    pkgs: gh:
    pkgs.writeShellApplication {
      name = "jj-pr-sync";
      runtimeInputs = [
        gh
        pkgs.jaq
        pkgs.jujutsu
        pkgs.coreutils
        pkgs.gnused
        pkgs.flock
      ];
      text = ''
        usage() {
          echo "usage: jj-pr-sync [--all] [--quiet]"
          echo "  (no flag)  register the current repository and refresh it"
          echo "  --all      refresh every registered repository (the background service)"
        }
        all=0 quiet=0
        for arg in "$@"; do
          case "$arg" in
            --all) all=1 ;;
            --quiet) quiet=1 ;;
            -h | --help) usage; exit 0 ;;
            *) usage >&2; exit 2 ;;
          esac
        done

        confd="''${XDG_CONFIG_HOME:-$HOME/.config}/jj/conf.d"
        mkdir -p "$confd"
        exec 9>"$confd/.jj-pr-sync.lock"
        if ! flock -n 9; then
          [ "$quiet" = 1 ] || echo "jj-pr-sync: another refresh is running" >&2
          exit 0
        fi

        log() { if [ "$all" = 1 ]; then echo "$(date -u +%FT%TZ) $*" >&2; else echo "$*" >&2; fi; }

        # write_cache SLUG REPO_PATH FILE: replaces FILE only after a complete fetch.
        write_cache() {
          local slug="$1" repo="$2" out="$3" prs tmp
          if ! prs="$(gh pr list --repo "$slug" --state all --limit "''${JJ_PR_SYNC_LIMIT:-1000}" \
            --json number,state,headRefName,autoMergeRequest,labels 2>/dev/null)"; then
            log "jj-pr-sync: $slug: GitHub unreachable or not signed in; keeping the previous mapping"
            return 1
          fi
          tmp="$(mktemp "$out.XXXXXX")"
          if ! {
            printf '# jj-pr-sync %s\n' "$slug"
            printf -- '--when.repositories = [%s]\n\n[pr-numbers]\n' "$(printf '%s' "$repo" | jaq -Rr tojson)"
            printf '%s' "$prs" | jaq -r '
              group_by(.headRefName)
              | map((map(select(.state == "OPEN")) | max_by(.number)) // max_by(.number))
              | sort_by(.headRefName)[]
              | "\(.headRefName | tojson) = \(("#\(.number)" + (
                  if .state != "OPEN" then {"MERGED": "✓", "CLOSED": "✗"}[.state]
                  elif .autoMergeRequest != null or ([(.labels // [])[].name] | index("merge-queue") != null) then "⇡"
                  else "" end
                )) | tojson)"
            '
          } >"$tmp"; then
            rm -f "$tmp"
            log "jj-pr-sync: $slug: unexpected response; keeping the previous mapping"
            return 1
          fi
          mv -f "$tmp" "$out"
          [ "$quiet" = 1 ] || log "jj-pr-sync: $slug: $(grep -c '^"' "$out") branches -> $out"
        }

        if [ "$all" = 1 ]; then
          shopt -s nullglob
          for f in "$confd"/pr-numbers-*.toml; do
            slug="$(sed -n '1s/^# jj-pr-sync //p' "$f")"
            repo="$(sed -n 's/^--when\.repositories = \["\(.*\)"\]$/\1/p' "$f")"
            if [ -z "$slug" ] || [ -z "$repo" ]; then
              log "jj-pr-sync: $f predates registration; run jj-pr-sync once in that repository"
              continue
            fi
            if [ ! -d "$repo" ]; then
              rm -f "$f"
              log "jj-pr-sync: $slug: $repo no longer exists; unregistered"
              continue
            fi
            write_cache "$slug" "$repo" "$f" || true
          done
          exit 0
        fi

        root="$(jj root)"
        repo="$root/.jj/repo"
        if [ -f "$repo" ]; then
          repo="$(cat "$repo")"
          case "$repo" in /*) ;; *) repo="$root/.jj/$repo" ;; esac
        fi
        repo="$(cd "$repo" && pwd -P)"
        slug="$(cd "$root" && gh repo view --json nameWithOwner | jaq -r .nameWithOwner)"
        write_cache "$slug" "$repo" \
          "$confd/pr-numbers-$(basename "$root")-$(printf '%s' "$repo" | sha256sum | cut -c1-8).toml"
      '';
    };

  # `jj-pr open|enqueue|enqueue-stack|dequeue BOOKMARK`, run from jjui.
  # Enqueueing follows the landing protocol: a single PR gets auto-merge
  # (rebase); a stack is authorized by the `merge-queue` label on its topmost PR
  # only, and no stack member ever gets auto-merge. Dequeueing undoes either;
  # gitea-mq treats auto_merge_disabled and unlabeled as a dequeue.
  mkPr =
    pkgs: gh: sync:
    pkgs.writeShellApplication {
      name = "jj-pr";
      # `$h` in the jaq program is a jq variable, not a shell expansion.
      excludeShellChecks = [ "SC2016" ];
      runtimeInputs = [
        gh
        pkgs.jaq
        sync
      ];
      text = ''
        usage="usage: jj-pr open|enqueue|enqueue-stack|dequeue BOOKMARK"
        [ $# -eq 2 ] || { echo "$usage" >&2; exit 2; }
        cmd="$1" bookmark="$2"

        case "$cmd" in
          open) exec gh pr view "$bookmark" --web ;;
          dequeue) json=number,state,mergedAt,autoMergeRequest,labels ;;
          enqueue | enqueue-stack) json=number,state,isDraft,baseRefName,headRefName,autoMergeRequest,labels ;;
          *) echo "jj-pr: unknown command $cmd" >&2; echo "$usage" >&2; exit 2 ;;
        esac

        pr="$(gh pr view "$bookmark" --json "$json")"
        field() { printf '%s' "$pr" | jaq -r "$1"; }
        number="$(field .number)"
        auto="$(field '.autoMergeRequest != null')"
        labelled="$(field '[.labels[].name] | index("merge-queue") != null')"

        if [ "$cmd" = dequeue ]; then
          case "$(field .state)" in
            MERGED) echo "#$number already merged at $(field .mergedAt); too late to dequeue." >&2; exit 1 ;;
            OPEN) ;;
            *) echo "#$number is $(field .state | tr '[:upper:]' '[:lower:]'); nothing to dequeue." >&2; exit 1 ;;
          esac
          if [ "$auto" != true ] && [ "$labelled" != true ]; then
            echo "#$number is not queued; nothing to do."
            exit 0
          fi
          if [ "$auto" = true ]; then
            gh pr merge "$number" --disable-auto
            echo "#$number: auto-merge disabled; gitea-mq drops it from the queue, including an in-flight batch."
          fi
          if [ "$labelled" = true ]; then
            gh pr edit "$number" --remove-label merge-queue
            echo "#$number: merge-queue label removed; gitea-mq drops the stack from the queue, including an in-flight batch."
          fi
          jj-pr-sync --quiet || true
          exit 0
        fi

        [ "$(field .state)" = OPEN ] || { echo "#$number is $(field .state | tr '[:upper:]' '[:lower:]'); nothing to enqueue." >&2; exit 1; }
        [ "$(field .isDraft)" = false ] || { echo "#$number is a draft; mark it ready first." >&2; exit 1; }

        default="$(gh repo view --json defaultBranchRef | jaq -r .defaultBranchRef.name)"
        head="$(field .headRefName)" base="$(field .baseRefName)"
        children="$(gh pr list --state open --limit 1000 --json number,baseRefName |
          jaq -r --arg h "$head" '[.[] | select(.baseRefName == $h) | "#\(.number)"] | join(" ")')"
        stacked=0
        if [ "$base" != "$default" ] || [ -n "$children" ]; then stacked=1; fi

        if [ "$cmd" = enqueue ]; then
          [ "$stacked" = 0 ] || { echo "#$number is part of a stack; authorize the stack with G M on its topmost PR." >&2; exit 1; }
          if [ "$auto" = true ]; then
            echo "#$number already has auto-merge ($(field .autoMergeRequest.mergeMethod | tr '[:upper:]' '[:lower:]')); nothing to do."
            exit 0
          fi
          gh pr merge "$number" --auto --rebase
          echo "#$number: auto-merge (rebase) enabled; gitea-mq lands it once its required checks pass."
        else
          [ "$stacked" = 1 ] || { echo "#$number is a single PR, not a stack; use G m." >&2; exit 1; }
          [ -z "$children" ] || { echo "#$number is not the top of its stack ($children build on it); label the topmost PR." >&2; exit 1; }
          if [ "$labelled" = true ]; then
            echo "#$number already carries merge-queue; nothing to do."
            exit 0
          fi
          gh pr edit "$number" --add-label merge-queue
          echo "#$number: labelled merge-queue; the stack below it lands together."
        fi
        jj-pr-sync --quiet || true
      '';
    };

  bookmarkLua = ''
    local function quote(s)
      local q = string.char(39)
      return q .. s:gsub(q, q .. "\\" .. q .. q) .. q
    end
    local function bookmark()
      local id = context.change_id()
      if not id then return nil end
      local out, err = jj("log", "-r", id, "--no-graph", "-T", 'local_bookmarks.map(|b| b.name() ++ "\n").join("")')
      if err then flash({ text = err, error = true }) return nil end
      local names = split_lines(out)
      if #names == 0 then flash("no bookmark on this revision") return nil end
      if #names == 1 then return names[1] end
      return choose({ options = names, title = "pull request for" })
    end
  '';

  prAction = name: second: desc: command: {
    inherit name desc;
    seq = [
      "shift+g"
      second
    ];
    scope = "revisions";
    lua = ''
      ${bookmarkLua}
      local name = bookmark()
      if name then exec_shell("jj-pr ${command} " .. quote(name)) end
    '';
  };

  jjuiActions = [
    (prAction "pr-open" "o" "open the bookmark's pull request" "open")
    (prAction "pr-enqueue" "m" "enqueue the bookmark's pull request" "enqueue")
    (prAction "pr-enqueue-stack" "shift+m" "enqueue the stack topped by the bookmark's pull request"
      "enqueue-stack"
    )
    (prAction "pr-dequeue" "d" "dequeue the bookmark's pull request" "dequeue")
  ];
in
{
  flake.lib.jjPrTags = {
    inherit
      builtinCommitLabels
      commitLabels
      mkSync
      mkPr
      jjuiActions
      ;
  };

  flake.modules.homeManager.development =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      sync = mkSync pkgs pkgs.gh;
      refresh = [
        "${sync}/bin/jj-pr-sync"
        "--all"
        "--quiet"
      ];
    in
    {
      home.packages = [
        sync
        (mkPr pkgs pkgs.gh sync)
      ];
      programs.jujutsu.settings.template-aliases."format_commit_labels(commit)" = commitLabels;
      programs.jjui.settings.actions = jjuiActions;

      launchd.agents.jj-pr-sync = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        enable = true;
        config = {
          ProgramArguments = refresh;
          StartInterval = refreshInterval;
          RunAtLoad = true;
          ProcessType = "Background";
          LowPriorityIO = true;
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/jj-pr-sync.log";
        };
      };

      systemd.user = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        services.jj-pr-sync = {
          Unit.Description = "Refresh jj pull request tags";
          Service = {
            Type = "oneshot";
            ExecStart = lib.escapeShellArgs refresh;
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };
        timers.jj-pr-sync = {
          Unit.Description = "Refresh jj pull request tags";
          Timer = {
            OnStartupSec = "1min";
            OnUnitActiveSec = "${toString refreshInterval}s";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}

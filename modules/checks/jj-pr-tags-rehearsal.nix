# Behavioural check for jj PR tags (modules/home/development/jj-pr-tags.nix).
#
# Everything runs against a stubbed `gh` backed by fixture files, in scratch
# jj repositories:
# - jj-pr-sync registration and rendering: a reused branch resolves to its open
#   PR, an open PR queued by auto-merge or by the merge-queue label is marked,
#   a merged slash-named branch is marked, a PR-less bookmark renders nothing,
#   and the mapping stays inside its repository;
# - jj-pr-sync --all: refreshes every registered repository, keeps a file
#   untouched when GitHub is unreachable for it, and unregisters a repository
#   that no longer exists;
# - jj-pr enqueue / enqueue-stack / dequeue: the landing protocol's decisions,
#   asserted on the gh calls actually made;
# - the jjui G-prefix sequences collide with no default binding of the
#   packaged jjui, and the override still embeds jj's builtin labels alias.
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      tags = self.lib.jjPrTags;
      ghStub = pkgs.writeShellApplication {
        name = "gh";
        excludeShellChecks = [ "SC2016" ];
        runtimeInputs = [
          pkgs.jaq
          pkgs.coreutils
        ];
        text = ''
          D="$GH_STUB_DIR"
          echo "$*" >>"$D/calls"
          case "$1 $2" in
            "repo view") cat "$D/repo.json" ;;
            "pr list")
              slug=""
              while [ $# -gt 0 ]; do [ "$1" = --repo ] && slug="$2"; shift; done
              if [ -n "$slug" ]; then
                f="$D/prs/$(printf '%s' "$slug" | tr / _).json"
                [ -f "$f" ] || { echo "network down" >&2; exit 1; }
                cat "$f"
              else
                cat "$D/prs/open.json"
              fi
              ;;
            "pr view") jaq -s --arg b "$3" 'add | .[] | select(.headRefName == $b)' "$D/prs/open.json" "$D/prs/merged.json" ;;
            "pr merge" | "pr edit") ;;
            *) echo "unexpected gh call: $*" >&2; exit 1 ;;
          esac
        '';
      };
      sync = tags.mkSync pkgs ghStub;
      pr = tags.mkPr pkgs ghStub sync;
      fixtures = {
        "o_synced.json" =
          let
            pr' =
              number: head: state: extra:
              {
                inherit number state;
                headRefName = head;
                autoMergeRequest = null;
                labels = [ ];
              }
              // extra;
          in
          [
            (pr' 10 "feature" "CLOSED" { labels = [ { name = "merge-queue"; } ]; })
            (pr' 12 "feature" "OPEN" { })
            (pr' 14 "feature" "CLOSED" { })
            (pr' 20 "renovate/astro" "MERGED" { })
            (pr' 21 "auto" "OPEN" { autoMergeRequest.mergeMethod = "REBASE"; })
            (pr' 22 "stacked-base" "OPEN" { })
            (pr' 23 "stacked-top" "OPEN" {
              labels = [
                { name = "dependencies"; }
                { name = "merge-queue"; }
              ];
            })
          ];
        "merged.json" = [
          {
            number = 25;
            headRefName = "landed";
            state = "MERGED";
            mergedAt = "2026-09-30T12:00:00Z";
            autoMergeRequest = null;
            labels = [ ];
          }
        ];
        "open.json" =
          let
            pr' =
              number: head: base: extra:
              {
                inherit number;
                headRefName = head;
                baseRefName = base;
                state = "OPEN";
                isDraft = false;
                autoMergeRequest = null;
                labels = [ ];
              }
              // extra;
          in
          [
            (pr' 30 "single" "main" { })
            (pr' 31 "queued" "main" { autoMergeRequest.mergeMethod = "REBASE"; })
            (pr' 32 "draft" "main" { isDraft = true; })
            (pr' 40 "stack-bottom" "main" { })
            (pr' 41 "stack-middle" "stack-bottom" { })
            (pr' 42 "stack-top" "stack-middle" { })
            (pr' 44 "lstack-bottom" "main" { })
            (pr' 45 "lstack-top" "lstack-bottom" { labels = [ { name = "merge-queue"; } ]; })
          ];
      };
      fixtureDir = pkgs.linkFarm "jj-pr-fixtures" (
        pkgs.lib.mapAttrsToList (name: value: {
          inherit name;
          path = pkgs.writeText name (builtins.toJSON value);
        }) fixtures
      );
      aliasConfig = (pkgs.formats.toml { }).generate "jj-pr-tags-alias.toml" {
        template-aliases."format_commit_labels(commit)" = tags.commitLabels;
      };
      firstKeys = pkgs.writeText "jj-pr-first-keys" (
        pkgs.lib.concatMapStringsSep "\n" (a: builtins.head a.seq) tags.jjuiActions
      );
    in
    {
      checks.jj-pr-tags-rehearsal =
        pkgs.runCommand "jj-pr-tags-rehearsal"
          {
            nativeBuildInputs = [
              ghStub
              sync
              pr
              pkgs.jujutsu
              pkgs.gnugrep
              pkgs.gnused
              pkgs.diffutils
            ];
            meta.description = "behavioural check: jj-pr-sync keeps PR tags current per repository and jj-pr enqueues by the landing protocol";
          }
          ''
            fail() { echo "FAIL: $*" >&2; exit 1; }
            export HOME="$PWD/home" XDG_CONFIG_HOME="$PWD/home/.config" GH_STUB_DIR="$PWD/gh"
            mkdir -p "$XDG_CONFIG_HOME/jj" "$GH_STUB_DIR/prs"
            cp ${fixtureDir}/* "$GH_STUB_DIR/prs/"
            chmod u+w "$GH_STUB_DIR"/prs/*
            cat ${aliasConfig} >"$XDG_CONFIG_HOME/jj/config.toml"
            printf '[user]\nname = "t"\nemail = "t@example.invalid"\n' >>"$XDG_CONFIG_HOME/jj/config.toml"
            confd="$XDG_CONFIG_HOME/jj/conf.d"

            builtin="$(sed -n "/^.format_commit_labels(commit). = [']\{3\}$/,/^[']\{3\}$/p" ${pkgs.jujutsu.src}/cli/src/config/templates.toml | sed '1d;$d')"
            ours=${pkgs.lib.escapeShellArg (pkgs.lib.removeSuffix "\n" tags.builtinCommitLabels)}
            [ "$builtin" = "$ours" ] || { diff <(echo "$builtin") <(echo "$ours") || true; fail "jj's builtin format_commit_labels changed"; }

            bindings=${pkgs.jjui.src}/internal/config/default/bindings.toml
            while read -r key; do
              if grep -E "scope *= *\"(revisions|ui)\"" "$bindings" | grep -qE "(key|seq) *= *(\[ *)?\"($key|G)\""; then
                fail "jjui already binds $key in the revisions scope"
              fi
            done <${firstKeys}

            labels() { jj log --no-graph -r "$1" -T 'format_commit_labels(self) ++ "\n"'; }

            echo '{"nameWithOwner":"o/synced","defaultBranchRef":{"name":"main"}}' >"$GH_STUB_DIR/repo.json"
            jj git init --colocate synced >/dev/null 2>&1
            cd synced
            jj new -m one >/dev/null 2>&1 && jj bookmark create feature -r @ >/dev/null
            jj new -m two >/dev/null 2>&1 && jj bookmark create renovate/astro -r @ >/dev/null
            jj new -m three >/dev/null 2>&1 && jj bookmark create untracked -r @ >/dev/null
            jj new -m four >/dev/null 2>&1 && jj bookmark create auto -r @ >/dev/null
            jj new -m five >/dev/null 2>&1 && jj bookmark create stacked-top -r @ >/dev/null
            jj-pr-sync

            [ "$(labels feature)" = "#12" ] || fail "reused branch: got '$(labels feature)'"
            [ "$(labels renovate/astro)" = "#20✓" ] || fail "merged slash branch: got '$(labels renovate/astro)'"
            [ -z "$(labels untracked)" ] || fail "PR-less bookmark: got '$(labels untracked)'"
            [ "$(labels auto)" = "#21⇡" ] || fail "auto-merge queued single: got '$(labels auto)'"
            [ "$(labels stacked-top)" = "#23⇡" ] || fail "labelled stack top: got '$(labels stacked-top)'"

            cd ..
            jj git init --colocate other >/dev/null 2>&1
            cd other
            jj new -m one >/dev/null 2>&1 && jj bookmark create feature -r @ >/dev/null
            [ -z "$(labels feature)" ] || fail "mapping leaked into another repository"
            cd ..

            # --all: a new PR appears, then GitHub becomes unreachable, then the repository goes away.
            echo '[{"headRefName":"feature","number":50,"state":"OPEN"}]' >"$GH_STUB_DIR/prs/o_synced.json"
            jj-pr-sync --all --quiet
            (cd synced && [ "$(labels feature)" = "#50" ]) || fail "--all did not refresh"
            rm "$GH_STUB_DIR/prs/o_synced.json"
            before="$(cat "$confd"/pr-numbers-synced-*.toml)"
            jj-pr-sync --all --quiet 2>/dev/null
            [ "$(cat "$confd"/pr-numbers-synced-*.toml)" = "$before" ] || fail "unreachable GitHub changed the cached mapping"
            (cd synced && [ "$(labels feature)" = "#50" ]) || fail "tags lost while offline"
            rm -rf synced
            all_out="$(jj-pr-sync --all 2>&1)"
            registered=("$confd"/pr-numbers-synced-*.toml)
            [ "''${#registered[@]}" -eq 0 ] || [ ! -e "''${registered[0]}" ] \
              || fail "removed repository stayed registered: $all_out"

            # jj-pr: landing-protocol decisions, judged by the mutating gh calls made.
            jj git init --colocate land >/dev/null 2>&1
            cd land
            mutations() { grep -E '^pr (merge|edit)' "$GH_STUB_DIR/calls" || true; }
            expect() {
              local want="$1" status="$2"; shift 2
              : >"$GH_STUB_DIR/calls"
              set +e; said="$(jj-pr "$@" 2>&1)"; rc=$?; set -e
              [ "$rc" = "$status" ] || fail "jj-pr $*: exit $rc, want $status: $said"
              [ "$(mutations)" = "$want" ] || fail "jj-pr $*: gh mutations '$(mutations)', want '$want'"
            }
            expect "pr merge 30 --auto --rebase" 0 enqueue single
            expect "" 0 enqueue queued
            expect "" 1 enqueue draft
            expect "" 1 enqueue stack-middle
            expect "" 1 enqueue stack-bottom
            expect "pr edit 42 --add-label merge-queue" 0 enqueue-stack stack-top
            expect "" 1 enqueue-stack stack-middle
            expect "" 1 enqueue-stack single
            expect "" 0 enqueue-stack lstack-top

            expect "pr merge 31 --disable-auto" 0 dequeue queued
            expect "pr edit 45 --remove-label merge-queue" 0 dequeue lstack-top
            expect "" 0 dequeue single
            expect "" 1 dequeue landed
            [[ "$said" == *"merged at 2026-09-30T12:00:00Z"* ]] || fail "dequeue landed: '$said'"

            touch "$out"
          '';
    };
}

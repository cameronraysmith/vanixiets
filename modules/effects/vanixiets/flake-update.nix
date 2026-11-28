# flake-update: the program behind the scheduled flake-update effect
# (./effects.nix), and checks.flake-update-rehearsal, which runs the same
# program against a fake forge.
#
# Both come from mkFlakeUpdate, a function of pkgs and the nix executable
# nixbot's script runs, so the rehearsal differs from production only in a
# stand-in nix. The program (./flake-update.sh) mints an installation token
# of the vanixiets-flake-updater App and runs nixbot's vendored flakeUpdate
# script (inputs.nixbot, herculesCI/nixbot-flake-update.py) with it: one
# branch `update-<input>` and pull request per moved root input, every input
# but playwright-web-flake and nixpkgs, no auto-merge, commits by the App's
# bot user.
#
# The rehearsal, after nixbot's checks/effects-lib-flake-update.nix: a bare
# repository behind git's smart HTTP and a fake GitHub API on 127.0.0.1
# (./flake-update-forge.py), a checkout set up as nixbot sets one up (its
# token in origin and in insteadOf entries), a test App key generated in the
# build, and a stand-in nix that rewrites flake.lock and commits as
# `nix flake update <input> --commit-lock-file` does, deterministically, so a
# second run sees no input move.
#   case 1: two runs over a lock with nixpkgs, playwright-web-flake, systems
#     and utils. Each signs a JWT the forge verifies against the test key and
#     App id, logs the installation it found, mints a token restricted to the
#     repository and two permissions, makes every later API and git request
#     with it and revokes it at exit. After the first, update-systems and
#     update-utils are one bot-authored commit ahead of main and have pull
#     requests, and no update-nixpkgs or update-playwright-web-flake exists;
#     the second changes no branch head.
#   case 2: the installation lookup answers 404: the program fails, names no
#     installation, and makes no push and no pull request call.
#   case 3, after every run: no file in the checkout, its git objects, the
#     forge's or $HOME holds a line of the key, the program's private
#     directory is gone, and while nixbot's script ran (checked by the
#     stand-in nix) no FLAKE_UPDATER_* variable or file held the key.
#
# x86_64-linux only, the system the effects are bound to.
{ inputs, lib, ... }:
let
  identity = {
    name = "vanixiets-flake-updater[bot]";
    email = "246545483+vanixiets-flake-updater[bot]@users.noreply.github.com";
  };

  mkFlakeUpdate =
    pkgs: nix:
    let
      update = (inputs.nixbot.lib.effects { inherit pkgs; }).flakeUpdate {
        perInput = true;
        updateBranch = "update";
        excludeInputs = [
          "playwright-web-flake"
          # Removed when the held nixpkgs update is unblocked.
          "nixpkgs"
        ];
        forgeType = "github";
        createPullRequest = true;
        autoMergeMethod = null;
        inherit nix;
      };
    in
    pkgs.writeShellApplication {
      name = "flake-update";
      runtimeInputs = [
        pkgs.git
        pkgs.curl
        pkgs.jq
        pkgs.gh-token
        pkgs.coreutils
      ];
      text = ''
        nixbot_flake_update=(${update.effectScript})
        export GIT_AUTHOR_NAME=${lib.escapeShellArg identity.name}
        export GIT_AUTHOR_EMAIL=${lib.escapeShellArg identity.email}
        export GIT_COMMITTER_NAME=${lib.escapeShellArg identity.name}
        export GIT_COMMITTER_EMAIL=${lib.escapeShellArg identity.email}
        ${builtins.readFile ./flake-update.sh}
      '';
    };

  mkRehearsal =
    pkgs:
    let
      appId = "4242";
      author = "${identity.name} <${identity.email}>";

      standInNix = pkgs.writeShellApplication {
        name = "nix";
        runtimeInputs = [
          pkgs.git
          pkgs.jq
          pkgs.coreutils
          pkgs.gnugrep
        ];
        text = ''
          printf '%s\n' "$*" >>"$FAKE_NIX_CALLS"
          # nixbot's script starts without the key: no variable holds it and
          # no file under the run's TMPDIR, HOME or checkout contains it.
          key_line="$(cat "$FAKE_NIX_KEY_LINE")"
          if [ -n "''${FLAKE_UPDATER_APP_ID+x}''${FLAKE_UPDATER_PRIVATE_KEY+x}" ]; then
            echo "a FLAKE_UPDATER_* variable reached nixbot's script" >>"$FAKE_NIX_VIOLATIONS"
          fi
          if grep -rlF -- "$key_line" "$TMPDIR" "$HOME" "$PWD" >>"$FAKE_NIX_VIOLATIONS"; then
            echo "^ held a line of the key while nixbot's script ran" >>"$FAKE_NIX_VIOLATIONS"
          fi
          input=""
          summary=""
          while [ $# -gt 0 ]; do
            case "$1" in
              update)
                input="$2"
                shift
                ;;
              --commit-lockfile-summary)
                summary="$2"
                shift
                ;;
            esac
            shift
          done
          jq --arg input "$input" '.nodes[$input].locked.rev = "moved-\($input)"' flake.lock >flake.lock.new
          mv flake.lock.new flake.lock
          git commit -q -m "$summary" -m "Updated input '$input'" flake.lock
        '';
      };

      program = lib.getExe (mkFlakeUpdate pkgs standInNix);

      seedLock = builtins.toJSON {
        nodes = {
          root.inputs = {
            nixpkgs = "nixpkgs";
            playwright-web-flake = "playwright-web-flake";
            systems = "systems";
            utils = "utils";
          };
          nixpkgs.locked.rev = "base";
          playwright-web-flake.locked.rev = "base";
          systems.locked.rev = "base";
          utils.locked.rev = "base";
        };
        root = "root";
        version = 7;
      };

      pull = input: {
        method = "POST";
        path = "/api/v3/repos/acme/widget/pulls";
        auth = "minted";
        body = {
          base = "main";
          body = "Updated input '${input}'";
          head = "update-${input}";
          title = "Update ${input}";
        };
      };
      lookup = {
        method = "GET";
        path = "/api/v3/repos/acme/widget/installation";
        auth = "jwt";
        body = null;
      };
      mintRequest = {
        permissions = {
          contents = "write";
          pull_requests = "write";
        };
        repositories = [ "widget" ];
      };
      run = [
        lookup
        {
          method = "POST";
          path = "/api/v3/app/installations/777/access_tokens";
          auth = "jwt";
          body = mintRequest;
        }
        (pull "systems")
        (pull "utils")
        {
          method = "DELETE";
          path = "/api/v3/installation/token";
          auth = "minted";
          body = null;
        }
      ];
      requestLines =
        entries: pkgs.writeText "requests" (lib.concatMapStrings (e: builtins.toJSON e + "\n") entries);

      # Case 3 runs after every run of the others.
      cases = [
        "1"
        "2"
      ];
    in
    pkgs.runCommand "flake-update-rehearsal"
      {
        nativeBuildInputs = [
          pkgs.git
          pkgs.jq
          pkgs.openssl
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.diffutils
          (pkgs.python3.withPackages (ps: [ ps.cryptography ]))
        ];
        meta.description = "behavioural check: the flake-update program against a fake forge";
      }
      ''
        set -euo pipefail
        fail() {
          echo "flake-update-rehearsal: $*" >&2
          exit 1
        }
        cd "$TMPDIR"
        export HOME="$TMPDIR/harness-home" GIT_CONFIG_NOSYSTEM=1
        mkdir -p "$HOME" key

        openssl genrsa -traditional -out key/app.pem 2048 2>/dev/null
        openssl rsa -in key/app.pem -pubout -out key/app.pub 2>/dev/null
        # An interior line of the key, the needle of every case 3 search.
        sed -n 5p key/app.pem >key/line
        # Stands in for a token the run must never use.
        echo '{ "token": { "data": { "token": "checkout-token" } } }' >nixbot-secrets.json

        forge_root="$TMPDIR/forge"
        bare="$forge_root/acme/widget.git"
        forge_pid=""
        trap '[ -z "$forge_pid" ] || kill "$forge_pid" 2>/dev/null || true' EXIT

        seed() {
          rm -rf "$forge_root" seed
          mkdir -p "$forge_root/acme"
          git init -q --bare -b main "$bare"
          git -C "$bare" config http.receivepack true
          git clone -q "$bare" seed 2>/dev/null
          printf '%s\n' ${lib.escapeShellArg seedLock} >seed/flake.lock
          git -C seed add flake.lock
          git -C seed -c user.name=seed -c user.email=seed@example.com commit -qm init
          git -C seed push -q origin HEAD:main
          rm -rf seed
          base="$(git -C "$bare" rev-parse main)"
        }

        start_forge() {
          rm -f port requests git-requests
          touch requests git-requests
          python3 ${./flake-update-forge.py} port requests git-requests "$forge_root" key/app.pub ${appId} "$1" &
          forge_pid=$!
          while [ ! -s port ]; do sleep 0.1; done
          port="$(cat port)"
        }

        stop_forge() {
          kill "$forge_pid"
          wait "$forge_pid" 2>/dev/null || true
          forge_pid=""
        }

        heads() {
          git -C "$bare" for-each-ref --format='%(refname:short) %(objectname)' refs/heads
        }

        # run_program <label>: a fresh checkout as nixbot sets one up, then
        # the program as the registry's entry point runs it.
        run_program() {
          rm -rf checkout home run-tmp nix-calls violations
          mkdir home run-tmp
          touch nix-calls violations
          git clone -q "$bare" checkout
          git -C checkout remote set-url origin "http://x-access-token:checkout-token@127.0.0.1:$port/acme/widget.git"
          for prefix in "http://127.0.0.1:$port/" "git@127.0.0.1:"; do
            git -C checkout config --add \
              url."http://x-access-token:checkout-token@127.0.0.1:$port/".insteadOf "$prefix"
          done
          status=0
          (
            cd checkout
            FLAKE_UPDATER_PRIVATE_KEY="$(cat "$TMPDIR/key/app.pem")"
            export FLAKE_UPDATER_PRIVATE_KEY
            exec env -i PATH=${pkgs.coreutils}/bin HOME="$TMPDIR/home" TMPDIR="$TMPDIR/run-tmp" \
              GIT_CONFIG_NOSYSTEM=1 \
              HERCULES_CI_SECRETS_JSON="$TMPDIR/nixbot-secrets.json" \
              FLAKE_UPDATER_APP_ID=${appId} \
              FLAKE_UPDATER_PRIVATE_KEY="$FLAKE_UPDATER_PRIVATE_KEY" \
              FAKE_NIX_CALLS="$TMPDIR/nix-calls" \
              FAKE_NIX_VIOLATIONS="$TMPDIR/violations" \
              FAKE_NIX_KEY_LINE="$TMPDIR/key/line" \
              ${program}
          ) >"$1.out" 2>&1 || status=$?
          sed "s/^/$1> /" "$1.out"
        }

        check_no_key() {
          if [ -s violations ]; then
            cat violations >&2
            fail "$1: case 3: the key was within reach of nixbot's script"
          fi
          line="$(cat key/line)"
          if grep -rlF -- "$line" checkout home run-tmp "$forge_root"; then
            fail "$1: case 3: the files above hold a line of the key"
          fi
          for repo in checkout/.git "$bare"; do
            if git --git-dir="$repo" cat-file --batch-all-objects --batch | grep -qF -- "$line"; then
              fail "$1: case 3: a git object in $repo holds a line of the key"
            fi
          done
          if [ -n "$(ls -A run-tmp)" ]; then
            fail "$1: case 3: the program left $(ls -A run-tmp) in its TMPDIR"
          fi
        }

        check_jwt() {
          invalid="$(jq -r 'select(.auth // "" | startswith("jwt-invalid")) | "\(.method) \(.path): \(.auth)"' requests)"
          [ -z "$invalid" ] || fail "$1: JWT check: $invalid"
        }

        check_auth() {
          bad="$(jq -c 'select(.auth != "jwt" and .auth != "minted" and (.auth // "" | startswith("jwt-invalid") | not))' requests)"
          [ -z "$bad" ] || fail "$1: authentication check: API calls not made with the minted token: $bad"
          bad="$(jq -c 'select(.token != "minted" or .user != "x-access-token")' git-requests)"
          [ -z "$bad" ] || fail "$1: authentication check: git requests not made with the minted token: $bad"
          # git's store helper rewrites the entry with the port's colon encoded.
          grep -Eqx "http://x-access-token:minted-token@127\.0\.0\.1(:|%3a)$port" home/.git-credentials ||
            fail "$1: authentication check: the credential store does not hold the minted token"
          if grep -q checkout-token home/.git-credentials; then
            fail "$1: authentication check: the credential store holds the checkout's token"
          fi
          grep -qx "access-tokens = 127.0.0.1:$port=minted-token" home/.config/nix/nix.conf ||
            fail "$1: authentication check: nix's access token is not the minted token"
        }

        case_1() {
          seed
          start_forge installed

          run_program "case 1 run 1"
          check_no_key "case 1 run 1"
          check_jwt "case 1 run 1"
          check_auth "case 1 run 1"
          grep -qxF "flake-update: App installation 777 on acme/widget" "case 1 run 1.out" ||
            fail "case 1 run 1: the log does not name the installation it looked up"
          mint="$(jq -c 'select(.path | endswith("/access_tokens")) | .body' requests | sort -u)"
          [ "$mint" = ${lib.escapeShellArg (builtins.toJSON mintRequest)} ] ||
            fail "case 1 run 1: the mint request is not restricted to the repository and two permissions: $mint"
          [ "$status" = 0 ] || fail "case 1 run 1: the program exited $status"
          [ "$(tail -n1 requests | jq -r '"\(.method) \(.path) \(.auth)"')" = "DELETE /api/v3/installation/token minted" ] ||
            fail "case 1 run 1: the minted token was not revoked at exit"
          grep -q '"request":"POST git-receive-pack?"' git-requests || fail "case 1 run 1: nothing was pushed"
          for branch in $(git -C "$bare" for-each-ref --format='%(refname:short)' refs/heads); do
            case "$branch" in
              main | update-systems | update-utils) ;;
              *) fail "case 1 run 1: unexpected branch $branch" ;;
            esac
          done
          for input in systems utils; do
            branch="update-$input"
            git -C "$bare" rev-parse -q --verify "refs/heads/$branch" >/dev/null ||
              fail "case 1 run 1: missing branch $branch"
            [ "$(git -C "$bare" rev-parse "$branch^")" = "$base" ] &&
              [ "$(git -C "$bare" rev-list --count "main..$branch")" = 1 ] ||
              fail "case 1 run 1: $branch is not one commit ahead of main"
            who="$(git -C "$bare" log -1 --format='%an <%ae>|%cn <%ce>' "$branch")"
            [ "$who" = ${lib.escapeShellArg "${author}|${author}"} ] ||
              fail "case 1 run 1: commit author and committer of $branch are '$who', expected '${author}'"
          done
          [ "$(grep -c . nix-calls)" = 2 ] || fail "case 1 run 1: expected one update per input: $(cat nix-calls)"

          before="$(heads)"
          run_program "case 1 run 2"
          check_no_key "case 1 run 2"
          check_jwt "case 1 run 2"
          check_auth "case 1 run 2"
          [ "$status" = 0 ] || fail "case 1 run 2: the program exited $status"
          [ "$(heads)" = "$before" ] || fail "case 1 run 2: a branch head changed with no input moved"

          stop_forge
          diff -u ${requestLines (run ++ run)} requests || fail "case 1: unexpected API requests"
        }

        case_2() {
          seed
          start_forge uninstalled
          before="$(heads)"
          run_program "case 2"
          check_no_key "case 2"
          check_jwt "case 2"
          if grep -qF "flake-update: App installation" "case 2.out"; then
            fail "case 2: the log names an installation the lookup did not find"
          fi
          [ "$status" != 0 ] || fail "case 2: the program succeeded without an installation"
          [ "$(heads)" = "$before" ] || fail "case 2: a branch changed without an installation"
          if grep -q receive-pack git-requests; then fail "case 2: something was pushed"; fi
          stop_forge
          diff -u ${requestLines [ lookup ]} requests || fail "case 2: requests beyond the installation lookup"
        }

        ${lib.concatMapStrings (c: "case_${c}\n") cases}
        touch $out
      '';
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      linux = system == "x86_64-linux";
    in
    {
      apps = lib.optionalAttrs linux {
        flake-update = {
          type = "app";
          program = lib.getExe (mkFlakeUpdate pkgs pkgs.nix);
        };
      };
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        flake-update-rehearsal = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs linux {
        flake-update-rehearsal = mkRehearsal pkgs;
      };
    };
}

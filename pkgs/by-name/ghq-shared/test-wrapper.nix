{
  runCommand,
  bash,
  git,
  ghq,
  ghq-sync,
  ghq-shared,
}:
# Delegation depends only on the caller's effective ghq root: plain nixpkgs ghq
# unless that root resolves to the shared root, including through a symbolic
# link to it (darwin's /var is one). The built wrapper runs with only its fixed
# host paths (ghq, the writer client, the shared root) pointed into the sandbox.
runCommand "ghq-shared-test-wrapper"
  {
    nativeBuildInputs = [ git ];
  }
  ''
    set -euo pipefail
    work=$(mktemp -d)
    mkdir -p "$work/shared" "$work/other" "$work/home"
    ln -s "$work/shared" "$work/shared-link"
    printf '#!${bash}/bin/bash\necho "real $*"\n' > "$work/real"
    printf '#!${bash}/bin/bash\necho "client $*"\ncase "$*" in *fail*) exit 3 ;; esac\n' > "$work/client"
    chmod +x "$work/real" "$work/client"
    cp ${ghq-shared}/bin/ghq "$work/ghq"
    chmod u+w "$work/ghq"
    substituteInPlace "$work/ghq" \
      --replace-fail ${ghq}/bin/ghq "$work/real" \
      --replace-fail ${ghq-shared}/libexec/ghq-shared/ghq-writer-client "$work/client" \
      --replace-fail shared_root=/var/lib/ghq "shared_root=$work/shared-link"

    export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
    unset GHQ_ROOT
    # expect STATUS OUTPUT ARGS...: ghq ARGS exits STATUS printing exactly OUTPUT.
    expect() {
      local want_status=$1 want=$2 got status=0
      shift 2
      got=$("$work/ghq" "$@" 2>&1) || status=$?
      if [ "$status" != "$want_status" ] || [ "$got" != "$want" ]; then
        printf 'FAIL: ghq %s -> exit %s:\n%s\nwant exit %s:\n%s\n' "$*" "$status" "$got" "$want_status" "$want"
        exit 1
      fi
      echo "ok: ghq $* -> exit $status"
    }
    nl=$'\n'

    echo "case: ghq.root unset"
    expect 0 "real get github.com/a/b" get github.com/a/b
    expect 0 "real create x" create x

    echo "case: ghq.root another path"
    git config --global ghq.root "$work/other"
    expect 0 "real get github.com/a/b" get github.com/a/b
    expect 0 "real rm x" rm x

    echo "case: ghq.root the shared root, by its real path"
    git config --global ghq.root "$work/shared"
    expect 0 "client get --lazy github.com/a/b" get --shallow --partial blobless github.com/a/b
    expect 0 "real list" list
    expect 2 "ghq: create is unavailable: this host's ghq tree is shared and only its writer account changes it" create x
    expect 3 "client get github.com/a/fail''${nl}client get github.com/a/b" get github.com/a/fail github.com/a/b

    echo "case: a directory under the shared root names its repository"
    mkdir -p "$work/shared/github.com/o/r/.git" "$work/shared/github.com/o/r/sub/dir" "$work/outside"
    (cd "$work/shared/github.com/o/r" && expect 0 "client get --update github.com/o/r" get -u .)
    (cd "$work/shared/github.com/o/r/sub/dir" && expect 0 "client get github.com/o/r" get .)
    expect 0 "client get github.com/o/r" get "$work/shared/github.com/o/r/sub"
    expect 0 "client get github.com/o/r" get "$work/shared-link/github.com/o/r/sub"
    expect 2 "ghq: $work/outside is outside the shared ghq root $work/shared-link" get "$work/outside"
    expect 2 "ghq: $work/outside is outside the shared ghq root $work/shared-link" get github.com/a/b "$work/outside"
    (cd "$work/outside" && expect 2 "ghq: . is outside the shared ghq root $work/shared-link" get .)
    expect 2 "ghq: $work/shared/github.com is not inside a repository under $work/shared-link" get "$work/shared/github.com"

    echo "case: a submodule's working tree names its superproject"
    mkdir -p "$work/shared/github.com/o/r/mod/dir" "$work/shared/github.com/o/r/.git/modules"
    git init -q --separate-git-dir "$work/shared/github.com/o/r/.git/modules/mod" "$work/shared/github.com/o/r/mod"
    (cd "$work/shared/github.com/o/r/mod/dir" && expect 0 "client get github.com/o/r" get .)

    echo "case: ghq-sync names the repository for a directory under ghq root"
    for dir in sub mod/dir; do
      got=$(cd "$work/shared-link/github.com/o/r/$dir" && GHQ_ROOT="$work/shared-link" ${ghq-sync}/bin/ghq-sync -n -u .)
      want="would run: ghq get --shallow --partial blobless --no-recursive -P -u github.com/o/r"
      [ "$got" = "$want" ] || { echo "FAIL: ghq-sync in $dir -> '$got', want '$want'"; exit 1; }
      echo "ok: ghq-sync -n -u . in $dir -> $got"
    done

    echo "case: ghq-sync --tags applies to fetch mode only"
    usage=$(${ghq-sync}/bin/ghq-sync --help)
    for mode in "--deepen 1" --full; do
      status=0
      got=$(GHQ_ROOT="$work/shared-link" ${ghq-sync}/bin/ghq-sync --tags $mode github.com/o/r 2>&1) || status=$?
      want="error: --tags cannot be combined with --deepen or --full''${nl}''${nl}$usage"
      if [ "$status" != 2 ] || [ "$got" != "$want" ]; then
        printf 'FAIL: ghq-sync --tags %s -> exit %s:\n%s\n' "$mode" "$status" "$got"
        exit 1
      fi
      echo "ok: ghq-sync --tags $mode -> exit 2"
    done

    echo "case: GHQ_ROOT overrides git configuration"
    GHQ_ROOT="$work/other" expect 0 "real get github.com/a/b" get github.com/a/b

    echo "case: writer unreachable fails, no fallback"
    printf '#!${bash}/bin/bash\necho unreachable >&2; exit 69\n' > "$work/client"
    expect 69 "unreachable" get github.com/a/b
    touch $out
  ''

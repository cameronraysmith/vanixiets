{
  runCommand,
  bash,
  git,
  coreutils,
  shellcheck,
}:
# Delegation depends only on the caller's effective ghq root: plain nixpkgs ghq
# unless that root resolves to the shared root, including through a symbolic
# link to it (darwin's /var is one).
runCommand "ghq-shared-test-wrapper"
  {
    nativeBuildInputs = [
      bash
      git
      coreutils
      shellcheck
    ];
  }
  ''
    set -euo pipefail
    work=$(mktemp -d)
    mkdir -p "$work/shared" "$work/other" "$work/home"
    ln -s "$work/shared" "$work/shared-link"
    printf '#!${bash}/bin/bash\necho "real $*"\n' > "$work/real"
    printf '#!${bash}/bin/bash\necho "client $*"\n' > "$work/client"
    chmod +x "$work/real" "$work/client"
    { echo '#!${bash}/bin/bash'; echo 'set -euo pipefail'; cat ${./ghq.sh}; } > "$work/ghq"
    substituteInPlace "$work/ghq" \
      --replace-fail @ghq@ "$work/real" \
      --replace-fail @client@ "$work/client" \
      --replace-fail @root@ "$work/shared-link" \
      --replace-fail @git@ ${git}/bin/git \
      --replace-fail @realpath@ ${coreutils}/bin/realpath
    chmod +x "$work/ghq"
    shellcheck "$work/ghq"

    export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
    unset GHQ_ROOT
    expect() {
      local want=$1; shift
      local got
      got=$("$work/ghq" "$@" 2>&1) || true
      if [ "$got" != "$want" ]; then
        echo "FAIL: ghq $* -> '$got', want '$want'"
        exit 1
      fi
      echo "ok: ghq $* -> $got"
    }

    echo "case: ghq.root unset"
    expect "real get github.com/a/b" get github.com/a/b
    expect "real create x" create x

    echo "case: ghq.root another path"
    git config --global ghq.root "$work/other"
    expect "real get github.com/a/b" get github.com/a/b
    expect "real rm x" rm x

    echo "case: ghq.root the shared root, by its real path"
    git config --global ghq.root "$work/shared"
    expect "client get --lazy github.com/a/b" get --shallow --partial blobless github.com/a/b
    expect "real list" list
    expect "ghq: create is unavailable: this host's ghq tree is shared and only its writer account changes it" create x

    echo "case: GHQ_ROOT overrides git configuration"
    GHQ_ROOT="$work/other" expect "real get github.com/a/b" get github.com/a/b

    echo "case: writer unreachable fails, no fallback"
    printf '#!${bash}/bin/bash\necho unreachable >&2; exit 69\n' > "$work/client"
    if "$work/ghq" get github.com/a/b 2>/dev/null; then
      echo "FAIL: unreachable writer succeeded"
      exit 1
    fi
    echo "ok: unreachable writer fails"
    touch $out
  ''

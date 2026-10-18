# passthru.tests.token-transport (design D2, D19): with NTFY_TOKEN_FILE set,
# ntfy-send hands the token to curl only on stdin, as the header file that
# `-H @-` reads, so it is on no argv. It runs the source script, not the built
# wrapper, so that NTFY_CURL_BIN can name a curl stub recording its argv and
# stdin. The same assertions run against a mutant of the script that passes the
# header with -H and must reject it.
{
  runCommand,
  bash,
}:
runCommand "ntfy-send-test-token-transport" { } ''
  set -euo pipefail
  work=$(mktemp -d)
  token=tk_AbCdEfGhIjKlMnOpQrStUvWxYz012
  printf '%s' "$token" > "$work/token"
  cat > "$work/curl" <<'STUB'
  #!${bash}/bin/bash
  printf '%s\n' "$@" > "$REC/argv"
  cat > "$REC/stdin"
  STUB
  chmod +x "$work/curl"
  export NTFY_CURL_BIN="$work/curl"
  caller=$(printf '%s\n' -H "Title: t" -d hello https://ntfy.zt/fleet-acceptance)

  # run SCRIPT ENV...: runs SCRIPT under `env ENV...` with the stub recording
  # into a fresh $REC; sets $status.
  run() {
    local script=$1
    shift
    REC=$(mktemp -d)
    export REC
    status=0
    env "$@" ${bash}/bin/bash "$script" hello fleet-acceptance -H "Title: t" < /dev/null || status=$?
  }

  # cases SCRIPT: returns 0 when every assertion holds, 1 at the first failure.
  cases() {
    local script=$1

    run "$script" NTFY_TOKEN_FILE="$work/token"
    [ "$status" = 0 ] || { echo "FAIL: token set: exit $status"; return 1; }
    if grep -qF "$token" "$REC/argv"; then echo "FAIL: token set: the token is on curl's argv"; return 1; fi
    [ "$(cat "$REC/stdin")" = "Authorization: Bearer $token" ] || { echo "FAIL: token set: stdin is not exactly the header"; return 1; }
    [ "$(cat "$REC/argv")" = "$(printf '%s\n' -sfk -m 5 -H @-)"$'\n'"$caller" ] || { echo "FAIL: token set: argv is not -H @- before the caller's arguments"; return 1; }
    echo "ok: token set: header on stdin, -H @- on argv, token on no argv"

    run "$script" -u NTFY_TOKEN_FILE
    [ "$status" = 0 ] || { echo "FAIL: token unset: exit $status"; return 1; }
    [ ! -s "$REC/stdin" ] || { echo "FAIL: token unset: curl got stdin"; return 1; }
    [ "$(cat "$REC/argv")" = "$(printf '%s\n' -sfk -m 5)"$'\n'"$caller" ] || { echo "FAIL: token unset: argv changed"; return 1; }
    echo "ok: token unset: argv unchanged, no stdin"

    run "$script" NTFY_TOKEN_FILE=
    [ "$status" = 0 ] || { echo "FAIL: token empty: exit $status"; return 1; }
    [ ! -s "$REC/stdin" ] || { echo "FAIL: token empty: curl got stdin"; return 1; }
    [ "$(cat "$REC/argv")" = "$(printf '%s\n' -sfk -m 5)"$'\n'"$caller" ] || { echo "FAIL: token empty: argv changed"; return 1; }
    echo "ok: token empty: argv unchanged, no stdin"

    run "$script" NTFY_TOKEN_FILE="$work/missing"
    [ "$status" != 0 ] || { echo "FAIL: unreadable token file: exit 0"; return 1; }
    [ ! -e "$REC/argv" ] || { echo "FAIL: unreadable token file: curl ran"; return 1; }
    echo "ok: unreadable token file: exit $status before curl"
  }

  cases ${./ntfy-send.sh}

  ${bash}/bin/bash ${./ntfy-send.sh} --help | grep -q '^  NTFY_TOKEN_FILE '
  echo "ok: --help documents NTFY_TOKEN_FILE"

  # The negative control: the header on argv instead of stdin.
  substitute ${./ntfy-send.sh} "$work/mutant.sh" \
    --replace-fail '-H @- "$@"' '-H "Authorization: Bearer $token" "$@"'
  if cases "$work/mutant.sh"; then
    echo "FAIL: the mutant passing the header on argv was accepted"
    exit 1
  fi
  echo "ok: the mutant passing the header on argv was rejected"
  touch "$out"
''

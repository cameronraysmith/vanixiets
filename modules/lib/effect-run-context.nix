# Fail-closed guard confining the herculesCI effects to pushes to main.
#
# Effects hold secrets, so only code from main may run them. The primary
# control is nixbot's gating: nixbot reads nixbot.toml from the default
# branch, and with effects_branches empty and effects_on_pull_requests false
# it runs onPush effects only for pushes to main. Pull requests and gitea-mq
# batches build an effect's dependencies without running it.
#
# This fragment is the backstop in case that gating is ever misconfigured. An
# effect declaring idTokenAudiences receives NIXBOT_ID_TOKEN_REQUEST_URL and
# NIXBOT_ID_TOKEN_REQUEST_TOKEN, and the token minted from that endpoint
# carries the event and ref nixbot is running it for. Any other event or ref
# ends the effect before it touches a secret or the network, with exit 0: a
# run nixbot should not have started is skipped, not failed, so a required
# nixbot/effects status stays green while main's nixbot.toml still admits
# such runs (as it does for the change that introduced this guard). A missing
# endpoint or a failed fetch is an error and exits 1; no path proceeds
# without positive evidence.
#
# The effect reads its own token's claims without verifying the signature. It
# fetched the token from nixbot over an authenticated endpoint reachable only
# inside its own sandbox, so a signature check would re-verify the transport it
# already trusts. The guard protects against misclassification of the run, not
# against tampering with effect code; that is prevented by effects never
# running pull request code.
#
# Interpolate mainOnlyGuard first in an effectScript, declare
# `idTokenAudiences = builtins.toJSON [ runContext.audience ];` (mkEffect
# attributes become environment strings), and put curl, jq and coreutils in
# the effect's inputs. On success it exports CI_BRANCH=main.
{
  flake.lib.effectRunContext = {
    # Any string works; nixbot checks only that the requested audience is one
    # the effect declared, and imposes no format.
    audience = "vanixiets-ci";

    mainOnlyGuard = ''
      if [ -z "''${NIXBOT_ID_TOKEN_REQUEST_URL:-}" ] || [ -z "''${NIXBOT_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
        echo "EFFECT-GUARD: NIXBOT_ID_TOKEN_REQUEST_URL and NIXBOT_ID_TOKEN_REQUEST_TOKEN are required; declare idTokenAudiences on the effect" >&2
        exit 1
      fi

      if ! _ci_response="$(curl -fsS -X POST "$NIXBOT_ID_TOKEN_REQUEST_URL" \
        -H "Authorization: Bearer $NIXBOT_ID_TOKEN_REQUEST_TOKEN" \
        -H 'Content-Type: application/json' \
        --data '{"audience":"vanixiets-ci"}')" \
        || ! _ci_token="$(printf '%s' "$_ci_response" | jq -re .token)"; then
        echo "EFFECT-GUARD: failed to obtain an id token from nixbot" >&2
        exit 1
      fi

      # JWT payloads are unpadded base64url.
      _ci_payload="$(printf '%s' "$_ci_token" | cut -d. -f2 | tr '_-' '/+')"
      case $(( ''${#_ci_payload} % 4 )) in
        2) _ci_payload="$_ci_payload==" ;;
        3) _ci_payload="$_ci_payload=" ;;
      esac
      if ! _ci_claims="$(printf '%s' "$_ci_payload" | base64 -d)"; then
        echo "EFFECT-GUARD: failed to decode the id token payload" >&2
        exit 1
      fi

      _ci_event="$(printf '%s' "$_ci_claims" | jq -r '.event // ""')" || _ci_event=""
      _ci_ref="$(printf '%s' "$_ci_claims" | jq -r '.ref // ""')" || _ci_ref=""
      if [ "$_ci_event" != push ] || [ "$_ci_ref" != refs/heads/main ]; then
        echo "EFFECT-GUARD: skipping outside a push to main (event=$_ci_event ref=$_ci_ref)" >&2
        exit 0
      fi
      unset _ci_response _ci_token _ci_payload _ci_claims _ci_event _ci_ref

      CI_BRANCH=main
      export CI_BRANCH
      echo "CI-RUN-CONTEXT: branch=main is_main=true"
    '';
  };
}

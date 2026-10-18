# ntfy-send: post a push notification to the fleet's ntfy server (ntfy.zt).
# One source for every delivery: the home-manager tools command installs it,
# and system units run it from ExecStart.
#
# Endpoint security software on Darwin blocks ad-hoc signed (Nix store)
# binaries from TCP connections over ZeroTier. The preamble injects
# NTFY_CURL_BIN, the eval-time-resolved curl path, so Darwin uses /usr/bin/curl
# while Linux uses the curl from runtimeInputs.
#
# NTFY_TOKEN_FILE, when set and non-empty, names a file holding an ntfy access
# token, such as the `alerter` token that fleet-* topics require. The script
# reads it with bash's $(< file) and prints `Authorization: Bearer <token>` with
# the printf builtin into curl's stdin, which curl reads with `-H @-`, so the
# token is on no process's argv. Unset, the post is anonymous, which host
# topics accept. passthru.tests.token-transport runs the source script against
# a recording curl stub, with a mutant that passes the header on argv.
{
  lib,
  stdenv,
  curl,
  callPackage,
  writeShellApplication,
}:
writeShellApplication {
  name = "ntfy-send";
  runtimeInputs = lib.optional (!stdenv.hostPlatform.isDarwin) curl;
  text = ''
    export NTFY_CURL_BIN=${if stdenv.hostPlatform.isDarwin then "/usr/bin/curl" else "curl"}
    ${builtins.readFile ./ntfy-send.sh}
  '';
  passthru.tests.token-transport = callPackage ./test-token-transport.nix { };
  meta = {
    description = "Send push notification via ntfy.zt (Apple-signed curl on Darwin)";
    license = lib.licenses.mit;
    mainProgram = "ntfy-send";
  };
}

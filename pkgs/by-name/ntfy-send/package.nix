# ntfy-send: post a push notification to the fleet's ntfy server (ntfy.zt).
# One source for every delivery: the home-manager tools command installs it,
# and system units run it from ExecStart.
#
# Endpoint security software on Darwin blocks ad-hoc signed (Nix store)
# binaries from TCP connections over ZeroTier. The preamble injects
# NTFY_CURL_BIN, the eval-time-resolved curl path, so Darwin uses /usr/bin/curl
# while Linux uses PATH curl.
{
  lib,
  stdenv,
  writeShellApplication,
}:
writeShellApplication {
  name = "ntfy-send";
  text = ''
    export NTFY_CURL_BIN=${if stdenv.hostPlatform.isDarwin then "/usr/bin/curl" else "curl"}
    ${builtins.readFile ./ntfy-send.sh}
  '';
  meta = {
    description = "Send push notification via ntfy.zt (Apple-signed curl on Darwin)";
    license = lib.licenses.mit;
    mainProgram = "ntfy-send";
  };
}

let
  # connect-timeout does not apply once a connection is established, so a
  # substituter that accepts connections and then stops responding holds the
  # cache-status phase open for the full stalled-download-timeout, multiplied by
  # the retry attempts. Nix 2.35 implements this setting as curl's
  # CURLOPT_LOW_SPEED_TIME with CURLOPT_LOW_SPEED_LIMIT of 1 byte/s
  # (src/libstore/filetransfer.cc), so it measures sustained absence of progress
  # rather than total transfer time, and a slow but progressing download is
  # unaffected.
  downloadTimeout =
    { lib, ... }:
    {
      nix.settings.stalled-download-timeout = lib.mkDefault 60;
    };
in
{
  flake.modules.nixos.base = downloadTimeout;
  flake.modules.darwin.base = downloadTimeout;
}

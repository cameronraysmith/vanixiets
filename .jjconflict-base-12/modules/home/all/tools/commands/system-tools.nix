{
  pkgs,
  lib,
  config,
  ...
}:
{
  # DNS cache reset for macOS
  dnsreset = {
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Flush DNS cache and restart mDNSResponder on macOS

      Usage: dnsreset

      Executes the following commands:
        1. sudo dscacheutil -flushcache
        2. sudo killall -HUP mDNSResponder

      This clears the DNS cache and restarts the DNS responder service,
      which can resolve DNS-related connectivity issues.
      HELP
          exit 0
          ;;
      esac

      echo "Flushing DNS cache..."
      sudo dscacheutil -flushcache

      echo "Restarting mDNSResponder..."
      sudo killall -HUP mDNSResponder

      echo "DNS cache flushed and mDNSResponder restarted successfully."
    '';
  };
}

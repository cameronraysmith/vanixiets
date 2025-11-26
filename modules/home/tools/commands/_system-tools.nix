{
  pkgs,
  lib,
  config,
  ...
}:
{
  # Restart nix-rosetta-builder VM
  rosetta-restart = {
    runtimeInputs = with pkgs; [
      openssh
      nix
    ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Restart nix-rosetta-builder VM (clears memory)

      Usage: rosetta-restart [--gc]

      Options:
        --gc    Run garbage collection on rosetta-builder before restart

      Restarts the rosetta-builderd launchd service, which kills the
      existing Lima VM and starts fresh on next build request.

      The rosetta-builder is a separate NixOS VM with its own nix store
      (does not share with host). Use --gc to free disk space on the VM.

      Examples:
        rosetta-restart         # Quick restart (clears memory)
        rosetta-restart --gc    # GC on VM, then restart
      HELP
          exit 0
          ;;
        --gc)
          echo "Running garbage collection on rosetta-builder..."
          if ssh rosetta-builder "sudo nix-collect-garbage -d"; then
            echo "Garbage collection complete."
          else
            echo "Warning: GC failed (VM may not be running). Continuing with restart..."
          fi
          ;;
      esac

      echo "Restarting rosetta-builderd..."
      sudo launchctl kickstart -k system/org.nixos.rosetta-builderd

      echo "Waiting for VM to boot..."
      sleep 10

      echo "Verifying nix store connection..."
      if nix store info --store ssh-ng://rosetta-builder; then
        echo "rosetta-builder is ready."
      else
        echo "Warning: Connection check failed. VM may still be booting."
        echo "Try again in a few seconds: nix store info --store ssh-ng://rosetta-builder"
      fi
    '';
  };

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

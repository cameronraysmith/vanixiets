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
      procps # for pgrep
    ];
    text = ''
      DO_GC=false
      NO_VERIFY=false
      DO_STOP=false
      DO_START=false

      for arg in "$@"; do
        case "$arg" in
          -h|--help)
            cat <<'HELP'
      Manage nix-rosetta-builder VM service

      Usage: rosetta-restart [--gc] [--idle] [--stop] [--start]

      Options:
        --gc     Run garbage collection on rosetta-builder before restart
        --idle   Don't verify connection (leaves VM in idle/stopped state)
        --stop   Disable the rosetta-builder service entirely (for remote builds)
        --start  Re-enable a stopped rosetta-builder service

      Service Control (--stop/--start):
        Use --stop to fully disable rosetta-builder when you want clan/nix
        to use remote builds instead of local cross-compilation. This makes
        --build-on auto fall back to remote since local can't build x86_64.

        Workflow for remote cloud VM deployment:
          rosetta-restart --stop       # Disable local x86_64 builds
          nix run .#terraform          # auto → remote (can't build locally)
          rosetta-restart --start      # Re-enable rosetta-builder

      Restart Mode (default):
        Restarts the rosetta-builderd launchd service, which kills the
        existing Lima VM and releases memory (~10-15 GB).

        By default, verifies the connection after restart, which triggers
        the VM to start fresh (~1.5 GB). Use --idle to skip verification
        and leave the VM stopped until the next build request.

      The rosetta-builder is a separate NixOS VM with its own nix store
      (does not share with host). Use --gc to free disk space on the VM.

      Examples:
        rosetta-restart             # Restart and verify (fresh VM ready)
        rosetta-restart --idle      # Restart only (VM stays stopped)
        rosetta-restart --gc        # GC on VM, then restart and verify
        rosetta-restart --stop      # Disable for remote builds
        rosetta-restart --start     # Re-enable after remote builds
      HELP
            exit 0
            ;;
          --gc)
            DO_GC=true
            ;;
          --idle)
            NO_VERIFY=true
            ;;
          --stop)
            DO_STOP=true
            ;;
          --start)
            DO_START=true
            ;;
        esac
      done

      # Find the launchd plist path
      PLIST_PATH="/Library/LaunchDaemons/org.nixos.rosetta-builderd.plist"

      # Handle --stop: disable the service entirely
      if $DO_STOP; then
        echo "Stopping rosetta-builder service..."
        OLD_PID=$(pgrep -f "com.apple.Virtualization.VirtualMachine" 2>/dev/null || echo "none")

        if sudo launchctl bootout system/org.nixos.rosetta-builderd 2>/dev/null; then
          sleep 2
          NEW_PID=$(pgrep -f "com.apple.Virtualization.VirtualMachine" 2>/dev/null || echo "none")
          echo "rosetta-builder service disabled."
          if [ "$OLD_PID" != "none" ] && [ "$NEW_PID" = "none" ]; then
            echo "VM process terminated (PID $OLD_PID → stopped)"
          fi
          echo ""
          echo "Local x86_64-linux builds are now unavailable."
          echo "clan/nix --build-on auto will fall back to remote builds."
          echo ""
          echo "To re-enable: rosetta-restart --start"
        else
          echo "Warning: Service may already be stopped or not found."
          echo "Check status: sudo launchctl list | grep rosetta"
        fi
        exit 0
      fi

      # Handle --start: re-enable a stopped service
      if $DO_START; then
        echo "Starting rosetta-builder service..."

        if [ ! -f "$PLIST_PATH" ]; then
          echo "Error: Plist not found at $PLIST_PATH"
          echo "The rosetta-builder may not be installed in this system."
          exit 1
        fi

        if sudo launchctl bootstrap system "$PLIST_PATH" 2>/dev/null; then
          echo "rosetta-builder service enabled."
        else
          # May already be loaded, try kickstart instead
          echo "Service may already be loaded, attempting kickstart..."
          sudo launchctl kickstart system/org.nixos.rosetta-builderd
        fi

        echo "Waiting for VM to boot..."
        sleep 8

        echo "Verifying nix store connection..."
        if nix store info --store ssh-ng://rosetta-builder; then
          FINAL_PID=$(pgrep -f "com.apple.Virtualization.VirtualMachine" 2>/dev/null || echo "none")
          echo "rosetta-builder is ready (PID: $FINAL_PID)."
          echo ""
          echo "Local x86_64-linux builds are now available."
        else
          echo "Warning: Connection check failed. VM may still be booting."
          echo "Try again in a few seconds: nix store info --store ssh-ng://rosetta-builder"
        fi
        exit 0
      fi

      # Default behavior: restart the service
      # Get old PID for comparison
      OLD_PID=$(pgrep -f "com.apple.Virtualization.VirtualMachine" 2>/dev/null || echo "none")
      echo "Current VM PID: $OLD_PID"

      if $DO_GC; then
        echo "Running garbage collection on rosetta-builder..."
        if ssh rosetta-builder "sudo nix-collect-garbage -d"; then
          echo "Garbage collection complete."
        else
          echo "Warning: GC failed (VM may not be running). Continuing with restart..."
        fi
      fi

      echo "Restarting rosetta-builderd..."
      sudo launchctl kickstart -k system/org.nixos.rosetta-builderd

      sleep 2
      NEW_PID=$(pgrep -f "com.apple.Virtualization.VirtualMachine" 2>/dev/null || echo "none")

      if [ "$OLD_PID" != "$NEW_PID" ]; then
        echo "VM process changed: $OLD_PID → $NEW_PID (memory released)"
      fi

      if $NO_VERIFY; then
        echo "Skipping verification (--idle). VM will start on next build request."
        echo "Current VM state: $([ "$NEW_PID" = "none" ] && echo "stopped" || echo "PID $NEW_PID")"
      else
        echo "Waiting for VM to boot..."
        sleep 8

        echo "Verifying nix store connection..."
        if nix store info --store ssh-ng://rosetta-builder; then
          FINAL_PID=$(pgrep -f "com.apple.Virtualization.VirtualMachine" 2>/dev/null || echo "none")
          echo "rosetta-builder is ready (PID: $FINAL_PID)."
        else
          echo "Warning: Connection check failed. VM may still be booting."
          echo "Try again in a few seconds: nix store info --store ssh-ng://rosetta-builder"
        fi
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

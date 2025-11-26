# Network utility commands
# Zerotier join and IPv6 calculation utilities
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, lib, ... }:
    let
      # Zerotier network ID from cinnabar controller
      networkId = "db4344343b14b903";

      zerotierJoin = pkgs.writeShellApplication {
        name = "zerotier-join";
        runtimeInputs = [ ];
        text = ''
          # Zerotier network join and IPv6 calculation utility
          # Network ID: ${networkId}

          # Check if zerotier-cli is available in PATH
          if ! command -v zerotier-cli &> /dev/null; then
            echo "zerotier-cli not found in PATH" >&2
            echo "Install via: brew install --cask zerotier-one" >&2
            exit 1
          fi

          # Check if zerotier service is running (requires root for authtoken.secret)
          if ! sudo zerotier-cli info &> /dev/null; then
            echo "zerotier-one service not running" >&2
            echo "Start via: sudo launchctl load /Library/LaunchDaemons/com.zerotier.one.plist" >&2
            exit 1
          fi

          # Check if already joined the network
          if sudo zerotier-cli listnetworks 2>/dev/null | grep -q "${networkId}"; then
            echo "Already joined zerotier network ${networkId}"

            # Display current status
            NETWORK_STATUS=$(sudo zerotier-cli listnetworks | grep "${networkId}" || true)
            if [ -n "''${NETWORK_STATUS}" ]; then
              echo "Status: ''${NETWORK_STATUS}"
            fi
          else
            echo "Joining zerotier network ${networkId}..."
            sudo zerotier-cli join ${networkId}

            # Wait for join to complete
            sleep 2
          fi

          # Always extract and display member info and calculated IPv6
          MEMBER_INFO=$(sudo zerotier-cli info 2>/dev/null || echo "info unavailable")
          echo "Member info: ''${MEMBER_INFO}"

          # Extract 10-character member ID from info output
          # Format: "200 info <member-id> <version> <status>"
          MEMBER_ID=$(echo "''${MEMBER_INFO}" | awk '{print $3}')

          if [ -n "''${MEMBER_ID}" ]; then
            # Calculate deterministic IPv6 address using ZeroTier RFC4193 addressing
            # Network db4344343b14b903 -> fddb:4344:343b:14b9
            # Member 0ee971d9e0 -> :399:930e:e971:d9e0
            # Format: fd<net[0:2]>:<net[2:6]>:<net[6:10]>:<net[10:14]>:399:93<member[0:2]>:<member[2:6]>:<member[6:10]>
            NETWORK_PREFIX="fddb:4344:343b:14b9"  # Derived from network ID ${networkId}
            MEMBER_SUFFIX="''${MEMBER_ID:0:2}:''${MEMBER_ID:2:4}:''${MEMBER_ID:6:4}"
            CALCULATED_IPV6="''${NETWORK_PREFIX}:399:93''${MEMBER_SUFFIX}"

            echo ""
            echo "Member ID: ''${MEMBER_ID}"
            echo "Calculated IPv6: ''${CALCULATED_IPV6}"

            # Check if ACCESS_DENIED (not yet authorized)
            if echo "''${NETWORK_STATUS:-}" | grep -q "ACCESS_DENIED"; then
              echo ""
              echo "=== Authorization Required ==="
              echo "To authorize this machine on cinnabar controller, run ONE of:"
              echo ""
              echo "Option 1 (Declarative - recommended):"
              echo "  Add to modules/clan/inventory/services/zerotier.nix:"
              echo "  roles.controller.machines.\"cinnabar\".settings.allowedIps = ["
              echo "    \"''${CALCULATED_IPV6}\""
              echo "  ];"
              echo "  Then: clan machines update cinnabar"
              echo ""
              echo "Option 2 (Imperative):"
              echo "  ssh root@cinnabar zerotier-members allow --member-ip ''${CALCULATED_IPV6}"
              echo ""
            fi
          fi
        '';
      };
    in
    {
      home.packages = [
        zerotierJoin
      ];
    };
}

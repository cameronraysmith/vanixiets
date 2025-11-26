# Zerotier network configuration for blackphos
# Automated network join via system activation script
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Zerotier network ID from cinnabar controller
  # Located at: vars/per-machine/cinnabar/zerotier/zerotier-network-id/value
  networkId = "db4344343b14b903";

  zerotierJoinScript = pkgs.writeShellApplication {
    name = "zerotier-join";
    # Note: zerotier-cli is provided by homebrew cask, not nixpkgs
    # Runtime check handles case where homebrew hasn't installed it yet
    runtimeInputs = [ ];
    text = ''
      # Wait for zerotier-cli to be available in PATH
      if ! command -v zerotier-cli &> /dev/null; then
        echo "zerotier-cli not found in PATH, skipping network join" >&2
        exit 0
      fi

      # Check if zerotier service is running (requires root for authtoken.secret)
      if ! sudo zerotier-cli info &> /dev/null; then
        echo "zerotier-one service not running, attempting to start..." >&2
        # Service should be managed by homebrew launchd
        # If not running, user may need to manually start via:
        # sudo launchctl load /Library/LaunchDaemons/com.zerotier.one.plist
        exit 0
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
  # Make zerotier-join available in system PATH for manual testing/debugging
  environment.systemPackages = [ zerotierJoinScript ];

  # System activation script to join zerotier network
  # Runs during darwin-rebuild switch activation phase
  system.activationScripts.zerotierJoin.text = ''
    echo "Running zerotier network join check..."
    ${zerotierJoinScript}/bin/zerotier-join
  '';
}

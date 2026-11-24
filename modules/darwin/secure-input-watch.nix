# macOS Secure Input blocks every global keyboard observer (Handy, Logi Options+,
# Raycast hotkeys) for as long as one process holds it, and the hold can outlive
# the process that took it; only logging out clears that state. This agent
# notifies when this user's holder has held it for `thresholdSeconds` while the
# screen is unlocked, and again if that holder then exits.
{ ... }:
{
  flake.modules.darwin.base =
    { pkgs, ... }:
    let
      thresholdSeconds = 600;
      secure-input-watch = pkgs.writeShellApplication {
        name = "secure-input-watch";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnugrep
        ];
        text = ''
          state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/secure-input-watch"
          state="$state_dir/holder"
          mkdir -p "$state_dir"

          console=$(/usr/sbin/ioreg -l -d 1 -w 0 | grep -o '{[^{}]*}' | grep "\"kCGSSessionUserIDKey\"=$(id -u)[,}]" || true)
          pid=$(grep -o '"kCGSSessionSecureInputPID"=[0-9]*' <<<"$console" | cut -d= -f2 || true)
          if [[ -z "$pid" ]] || grep -q '"CGSSessionScreenIsLocked"=Yes' <<<"$console"; then
            rm -f "$state"
            exit 0
          fi

          now=$(date +%s)
          held_pid="" since="$now" alerted=0
          if [[ -f "$state" ]]; then
            read -r held_pid since alerted <"$state"
          fi
          if [[ "$held_pid" != "$pid" ]]; then
            since="$now" alerted=0
          fi

          message="" level=0
          if ! name=$(/bin/ps -o comm= -p "$pid"); then
            message="Secure Input is stuck: its holder (PID $pid) has exited. Log out and back in to clear it."
            level=2
          elif ((now - since >= ${toString thresholdSeconds})); then
            message="$(basename "$name") (PID $pid) has held Secure Input for $(((now - since) / 60)) minutes."
            level=1
          fi

          if ((level > alerted)); then
            /usr/bin/osascript \
              -e 'on run argv' \
              -e 'display notification (item 1 of argv) with title "Secure Input"' \
              -e 'end run' \
              "$message"
            alerted=$level
          fi
          echo "$pid $since $alerted" >"$state"
        '';
      };
    in
    {
      launchd.user.agents.secure-input-watch = {
        command = "${secure-input-watch}/bin/secure-input-watch";
        serviceConfig = {
          RunAtLoad = true;
          StartInterval = 60;
          ProcessType = "Background";
        };
      };
    };
}

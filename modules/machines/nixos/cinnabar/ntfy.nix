{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { config, pkgs, ... }:
    {
      # ntfy's provisioning of the alerter user and its token (design D5,
      # D17). Depends on the shared ntfy-alerter token; the password is
      # random and discarded after hashing, so alerter authenticates by token
      # only. `ntfy user hash` reads the password and its confirmation from
      # stdin (ntfy 2.28.0 cmd/user.go:396-407,483-500). Removing a user from
      # this file deletes it and its token at ntfy's next start, so rollback
      # reverts magnetite's token-bearing posts first (design Migration Plan).
      # checks.x86_64-linux.ntfy-provisioning judges the rendered lines.
      clan.core.vars.generators.ntfy-alerter-env = {
        dependencies = [ "ntfy-alerter" ];
        files.ntfy-env = {
          mode = "0400";
          restartUnits = [ "ntfy-sh.service" ];
        };
        runtimeInputs = [
          pkgs.ntfy-sh
          pkgs.openssl
        ];
        script = ''
          token="$(cat "$in/ntfy-alerter/token")"
          password="$(openssl rand -hex 32)"
          hash="$(printf '%s\n%s\n' "$password" "$password" | ntfy user hash)"
          printf 'NTFY_AUTH_USERS=alerter:%s:user\nNTFY_AUTH_TOKENS=alerter:%s\n' "$hash" "$token" > "$out/ntfy-env"
        '';
      };

      services.ntfy-sh = {
        enable = true;
        environmentFile = config.clan.core.vars.generators.ntfy-alerter-env.files.ntfy-env.path;
        settings = {
          listen-http = "[::1]:2586";
          base-url = "https://ntfy.zt";

          # A week, so a phone off ZeroTier for days still receives fleet
          # alerts; nixpkgs' default cache-file already keeps them on disk
          # under the state directory across restarts.
          cache-duration = "168h";

          # Design D1: each mesh client is its own visitor. caddy's
          # reverse_proxy sets X-Forwarded-For to the client's address
          # (caddy v2.11.7 reverseproxy.go:929-994) and connects from ::1;
          # ntfy takes the right-most untrusted address of that header
          # (ntfy 2.28.0 server/util.go:86-141). ZeroTier members share one
          # /64, so visitors are keyed by the full address. No host is
          # exempt from rate limits.
          behind-proxy = true;
          proxy-trusted-hosts = "::1";
          visitor-prefix-bits-ipv6 = 128;

          # Only alerter publishes on fleet-*, anonymous clients (phones
          # included) may subscribe, and every other topic keeps the default
          # read-write (design D5 step 3; ADR-009 item 12). The named user's
          # row outranks `*` (user/manager.go:702-735 at ntfy v2.28.0), and an
          # anonymous write under `*:fleet-*:ro` is refused with 403, which
          # fleet-deadman's probe asserts every 5 min.
          auth-access = [
            "alerter:fleet-*:rw"
            "*:fleet-*:ro"
          ];
        };
      };
    };
}

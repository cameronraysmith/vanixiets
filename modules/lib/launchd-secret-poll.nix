# launchd orders no job after another, so a darwin daemon can start at boot
# before sops-install-secrets has written the files it reads. /bin/wait4path
# cannot wait for them: it re-checks only when the mount table changes
# (wait4path(1)), and sops-install-secrets writes its files after mounting
# its ramdisk, so a waiter that checked between the two sleeps until some
# later mount, possibly forever, while launchd reports the job running. It
# stays right for /nix/store, which is a mount.
#
# prefix { bound ? 60; } paths: shell text that polls once a second until
# every path exists or `bound` seconds have passed, followed by the daemon's
# exec. A file that never appears costs the bound; the daemon then starts,
# fails and is relaunched as it would without the poll, so the failure
# stays visible.
#
# namedIn config text: the machine's sops secret and template paths that
# occur in text, a daemon's wait list derived from its configuration.
#
# failures { label; start; named; outer ? [ ]; }: the regulator's problems.
# `named` is the secret paths the daemon's configuration names, found by the
# caller without namedIn; `start` is the shell text that ends in the exec;
# `outer` is text launchd runs first, nix-darwin's ProgramArguments.
{ lib, ... }:
let
  defaultBound = 60;
  flat = lib.replaceStrings [ "\n" ] [ " " ];
  captures =
    regex: text: map builtins.head (builtins.filter builtins.isList (builtins.split regex text));
in
{
  flake.lib.launchdSecretPoll = {
    prefix =
      {
        bound ? defaultBound,
      }:
      paths:
      lib.optionalString (paths != [ ]) (
        ''n=0; while [ "$n" -lt ${toString bound} ] && { ''
        + lib.concatMapStringsSep " || " (path: "[ ! -e ${lib.escapeShellArg path} ]") paths
        + "; }; do /bin/sleep 1; n=$((n + 1)); done; "
      );

    namedIn =
      config: text:
      builtins.filter (path: lib.hasInfix path text) (
        lib.unique (
          map (secret: secret.path) (
            lib.attrValues config.sops.secrets ++ lib.attrValues config.sops.templates
          )
        )
      );

    failures =
      {
        label,
        start,
        named,
        outer ? [ ],
      }:
      let
        text = flat start;
        beforeExec = builtins.head (builtins.split "(^| )exec " text);
        waited = captures "/bin/wait4path '?([^' ;&]+)" (
          lib.concatStringsSep " " (map flat outer ++ [ text ])
        );
        polled = captures "[[] ! -e '?([^' ]+)'? []]" beforeExec;
      in
      lib.optional (named == [ ]) "${label}: its configuration names no secret path to poll for"
      ++ map (path: "${label}: /bin/wait4path ${path} waits for a mount, not a file") (
        builtins.filter (path: path != "/nix/store") waited
      )
      ++ map (path: "${label}: ${path} is not polled for before the exec") (
        builtins.filter (path: !builtins.elem path polled) named
      )
      # A literal, not defaultBound, so a changed default fails here.
      ++ lib.optional (
        named != [ ] && !lib.hasInfix ''while [ "$n" -lt 60 ]'' beforeExec
      ) "${label}: the poll is not bounded to 60 seconds";
  };
}

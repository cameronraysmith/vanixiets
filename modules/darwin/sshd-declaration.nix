# Per-host declaration of whether the machine runs an SSH server.
#
# nix-darwin's services.openssh.enable is nullOr bool defaulting to null,
# meaning "leave Apple's Remote Login however the machine currently has it".
# That default is how a darwin host ends up serving SSH as manual state the
# repository neither records nor restores: argentum answers on port 22 today
# only because someone ticked Remote Login in System Settings. Contributing
# this option to the darwin base replaces that silence with a question every
# host must answer.
#
# declaredSshd.serving has no default, so a darwin host that fails to state its
# posture is an evaluation error rather than one that silently inherits a
# fleet-wide answer. Inheritance is the wrong shape here: whether a machine
# accepts inbound SSH is a per-machine security decision, and these are
# personal laptops belonging to different people, so a default would turn on a
# listener by accident rather than by decision.
#
# Enabling drives Apple's built-in sshd (com.openssh.sshd) through launchd,
# which listens on every interface including zerotier. Host keys come from the
# nix-darwin defaults; per-user authorization comes from each host's
# users.users.<name>.openssh.authorizedKeys.keys wiring (meta.sshKeys).
{ lib, ... }:
{
  flake.modules.darwin.base =
    { config, ... }:
    {
      options.declaredSshd.serving = lib.mkOption {
        type = lib.types.bool;
        example = false;
        description = ''
          Whether this machine runs Apple's Remote Login SSH server. `true`
          enables `com.openssh.sshd` and `false` disables it; there is no
          default, so every darwin host states its own posture.
        '';
      };

      config.services.openssh.enable = config.declaredSshd.serving;
    };
}

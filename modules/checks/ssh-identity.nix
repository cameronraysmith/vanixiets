# Host facts for the laptops' SSH identity (modules/home/core/ssh-identity.nix),
# asserted on the real configurations evaluated by nixos-pyrite and
# darwin-stibnite. The expected keys are written out here rather than read from
# flake.modules.homeManager.bitwarden-key-pins, so a changed or dropped pin fails.
{ config, lib, ... }:
let
  loginKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+";
  # The key https://github.com/cameronraysmith.keys lists for authentication.
  githubAuthKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDFGXo7HSSakYB5eEvp22xKmNrMwpI7OTlB3RqP+mGagbggljJP/YBmUCptstAMsZuKeMRXjm6UXUgNeUhECLZQHEDy2+Mrm42OM0svsMqlgZj1ZZdY1yYcquKQO4oyx7CjPOj7NXqSueZmpcwYRJFU7xQO421wb9rNewxCRs8jwRr5beTCUF0MuGLNEJGPMPk++d6Mkd3TYojE524AAoDWgx5z2WavZnewuYYd8PAGrFO4yWQn6LX50qYq2bPo53J/7CT9KwEo4ZaYl6TiSb9x3Oj+iUiTMNBmKBLSMYyj7eV8CU4iIXYqySvEf/mA7EytZnKT37cYo25CMAsobCHZ07htv6bbW+FPb1jehjT96Oo6i0zVGIs/gptw1k9xXSTS0GxfQ1P0XK7+9RZE7bWw/kxepF+OzLcvKKz3SdPEb/SOmqPoq4AFalljM0iwi8DXmH2dhp1Ughh4ImQQxVGrq+U2EwuSZEQHuSXlvfB/MKj2yvcF0BYhPaYfCLovq5LbXXu1QpnL/C9FiY21ehmVFZwHvo+L8y2NxwCaoXYuPGwGc5kH5fNjBh/S7RpypV+oHHGY90lGV6CoQpxXb65rI/ob7cTR2npWUC577fmidYTSmOqU3HhewcZDgxf2iZkVCm7F/Sb2tga3BClr3lV92EBFm9JsayzM9DLuAIz7rQ==";

  pinnedKey =
    home: host:
    let
      block = home.programs.ssh.settings.${host}.data or { };
      file = home.home.file.${lib.removePrefix "~/" (block.IdentityFile or "")} or { };
    in
    if (block.IdentitiesOnly or false) == true then lib.trim (file.text or "") else null;

  # Fleet hosts are reached under `.zt` until ZeroTier's retirement and under
  # the fleet domain; both patterns pin the login key.
  pinsHold =
    home:
    lib.all (pattern: pinnedKey home pattern == loginKey) [
      "*.zt"
      "*.${config.flake.lib.fleet.domain}"
    ]
    && pinnedKey home "github.com" == githubAuthKey;
in
{
  flake.modules.nixos."machines/nixos/pyrite" =
    { config, ... }:
    {
      assertions = [
        {
          message = "pyrite: fleet hosts pin the login key and GitHub its authentication key";
          assertion = pinsHold config.home-manager.users.cameron;
        }
      ];
    };

  flake.modules.darwin."machines/darwin/stibnite" =
    { config, ... }:
    let
      home = config.home-manager.users.crs58;
      openssh = lib.filter (package: (package.pname or "") == "openssh");
    in
    {
      assertions = [
        {
          message = "stibnite: fleet hosts pin the login key and GitHub its authentication key";
          assertion = pinsHold home;
        }
        {
          # Nix's OpenSSH uses BSD sockets, which cannot route to ZeroTier's
          # feth interfaces; Apple's uses Network.framework.
          message = "stibnite: ssh resolves to Apple's /usr/bin/ssh, not a Nix OpenSSH";
          # programs.ssh.package, when set, lands in home.packages.
          assertion = openssh home.home.packages == [ ] && openssh config.environment.systemPackages == [ ];
        }
      ];
    };
}

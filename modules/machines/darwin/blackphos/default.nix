{ config, ... }:
let
  flakeModules = config.flake.modules.darwin;
in
{
  flake.modules.darwin."machines/darwin/blackphos" = {
    imports = [ flakeModules.darwin-workstation ];

    networking.hostName = "blackphos";

    # Known gap: no environment.etc."nix/nix.conf".knownSha256Hashes.
    # stibnite, argentum and rosegold each carry the sha256 of the
    # /etc/nix/nix.conf that the nix installer left on that specific Mac.
    # The value is a property of the machine, not of this repository: it
    # cannot be computed here, and another host's hash is simply the wrong
    # file. blackphos is semi-permanently offline, so it cannot be read now,
    # and no placeholder is supplied because a wrong hash never matches and
    # would only look like the gap was closed.
    #
    # It matters only if /etc/nix/nix.conf there is still an unmanaged
    # regular file. nix-darwin's /etc check (modules/system/etc.nix) skips
    # any /etc entry already symlinked into /etc/static, so an already
    # activated blackphos needs nothing; otherwise activation aborts with
    # "Unexpected files in /etc" naming /etc/nix/nix.conf and refuses to
    # overwrite it.
    #
    # To close it when the machine next boots:
    #   readlink /etc/nix/nix.conf        # /etc/static/... means no hash needed
    #   shasum -a 256 /etc/nix/nix.conf   # otherwise add the digest here

    # Base casks from modules/darwin/homebrew.nix; machine-specific additions below
    custom.homebrew = {
      additionalCasks = [
        "dbeaver-community"
        "docker-desktop"
        "gitbutler"
        "gpg-suite"
        "inkscape"
        "keycastr"
        "meld"
        "postgres-app"
        "steipete/tap/codexbar"
        "zerotier-one"
      ];

      # Machine-specific Mac App Store apps
      additionalMasApps = {
        "save-to-raindrop-io" = 1549370672;
      };

      # Fonts managed via base homebrew module (manageFonts defaults to true)
    };

    # Encrypted DNS via DoH (DNS-over-HTTPS)
    # Routes all DNS through Quad9 DoH, bypassing enterprise DNS interception
    # DoH uses HTTPS (port 443)
    services.localDnscryptProxy = {
      enable = true;
      providers = [
        "quad9"
      ];
      userHome = "/private/var/lib/dnscrypt-proxy";
    };

    services.fleet-services-trust.enable = true;
  };
}

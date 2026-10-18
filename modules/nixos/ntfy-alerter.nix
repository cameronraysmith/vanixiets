# The alerter's ntfy access token, a shared clan vars generator (design D17).
#
# Shared, so it is generated once and every machine that imports this module
# deploys the same token (clan-core nixosModules/clanCore/vars/interface.nix:
# 90-100); one module is the single definition, because two copies of a
# shared script can drift. Every fleet-* publisher reads the token by path,
# config.clan.core.vars.generators.ntfy-alerter.files.token.path, through
# LoadCredential or NTFY_TOKEN_FILE, never on a command line.
#
# The ntfy server's provisioning file is a separate per-machine generator,
# ntfy-alerter-env in modules/machines/nixos/cinnabar/ntfy.nix, which depends
# on this one: pinned clan rejects a shared generator whose files' deploy
# differs between machines (clan_lib/vars/generator.py:270-297), and only
# cinnabar may hold that file. checks.x86_64-linux.ntfy-provisioning runs
# both scripts and judges their output.
{ ... }:
{
  flake.modules.nixos.ntfy-alerter =
    { pkgs, ... }:
    {
      # `ntfy token generate` prints tk_ plus 29 characters (ntfy 2.28.0
      # cmd/token.go:224-227); printf '%s' writes it without a newline.
      clan.core.vars.generators.ntfy-alerter = {
        share = true;
        files.token.mode = "0400";
        runtimeInputs = [ pkgs.ntfy-sh ];
        script = ''
          token="$(ntfy token generate)"
          printf '%s' "$token" > "$out/token"
        '';
      };
    };
}

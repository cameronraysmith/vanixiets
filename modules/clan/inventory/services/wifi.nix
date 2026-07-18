# Wifi association via clan-core's wifi clanService, discovered by import-tree.
# pyrite associates unattended at first boot with the dedicated fleet SSID. The
# network's SSID and PSK are shared clan vars under the wifi.fleet generator
# (share = true, one credential clan-wide), prompted by `clan vars generate
# pyrite` rather than committed as literals, because the NetworkManager profile
# is a world-readable store path. "fleet" names an internal identifier, not the
# SSID; it is the dedicated network this repository originates for the fleet,
# which is what makes committing its credential admissible. Targeting is
# machine-scoped because no `wireless` tag exists and pyrite is the sole taker.
# See design.md D14.
{
  clan.inventory.instances.wifi = {
    module = {
      name = "wifi";
      input = "clan-core";
    };
    roles.default.machines."pyrite" = {
      settings.networks.fleet = { };
    };
  };
}

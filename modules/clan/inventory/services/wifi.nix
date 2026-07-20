# Wifi association via clan-core's wifi clanService. A bare `networks.fleet = { }`
# associates unattended at first boot, because upstream defaults autoConnect true.
# The network's SSID and PSK are shared clan vars under the wifi.fleet generator
# (share = true, one credential clan-wide), prompted by `clan vars generate
# pyrite`. The SSID is a var alongside the PSK because the NetworkManager profile
# the service emits is a world-readable store path. Both are repository state
# rather than machine state because the install path is re-runnable and starts by
# blkdiscarding the disk, so anything kept on the machine is destroyed on every
# re-install and the machine must associate with nothing typed into it. "fleet"
# is this instance's identifier for the network, not the SSID; which network it
# denotes is decided in design.md D14. Targeting is machine-scoped because no
# `wireless` tag exists and pyrite is the sole taker.
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

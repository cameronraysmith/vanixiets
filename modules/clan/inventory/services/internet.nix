# Public IP assignments for VPS machines
{
  clan.inventory.instances.internet = {
    roles.default.machines.cinnabar.settings.host = "49.13.68.78";
    roles.default.machines.electrum.settings.host = "162.55.175.87";
    # GCP IPs are ephemeral - update after each enable/deploy cycle
    roles.default.machines.galena.settings.host = "35.206.81.165";
    roles.default.machines.scheelite.settings.host = "35.208.97.48";
  };
}

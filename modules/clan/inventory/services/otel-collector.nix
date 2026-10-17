# Collector roles. magnetite runs both in one collector process: its agent
# pipelines feed the ingress in-process (design D8). Other hosts join the
# agent role in S4, with the ZeroTier ingress listener.
{
  clan.inventory.instances.otel-collector = {
    module = {
      name = "otel-collector";
      input = "self";
    };

    roles.agent.machines.magnetite = { };
    roles.ingress.machines.magnetite = { };
  };
}

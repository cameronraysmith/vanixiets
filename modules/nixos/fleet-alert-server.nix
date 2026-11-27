# How this fleet runs the fleet alert evaluator (flake.modules.nixos.fleet-alert,
# which stays free of clan vars so the runtime tests can import it with their
# own credentials): its ntfy token and its store password come from the
# ntfy-alerter and greptimedb-users generators, read through
# config.clan.core.vars.generators without importing the aspects that define
# them, so a host that imports this one without them fails evaluation naming
# the missing generator.
{
  flake.modules.nixos.fleet-alert-server =
    { config, ... }:
    {
      # Fleet alert evaluator (ADR-009; design D3, D12): queries `fleet` as
      # the regulator account and posts to fleet-alerts with the shared
      # alerter token, which the failure notifier's template and resolve
      # hooks use too. The host holds only the token side of ntfy-alerter;
      # cinnabar holds the server's ntfy-alerter-env.
      services.fleet-alert.evaluator = {
        enable = true;
        tokenFile = config.clan.core.vars.generators.ntfy-alerter.files.token.path;
        regulatorPasswordFile =
          config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path;
      };
    };
}

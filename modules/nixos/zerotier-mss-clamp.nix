# Fixed MSS limits TCP segments on constrained ZeroTier paths, not UDP or every PMTU.
{ ... }:
{
  flake.modules.nixos.zerotier-mss-clamp =
    { config, lib, ... }:
    let
      tools = [ "iptables" ] ++ lib.optional config.networking.enableIPv6 "ip6tables";
      rules = [
        "INPUT -i zt+ -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300"
        "OUTPUT -o zt+ -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300"
      ];
      forRules = f: lib.concatMapStrings (tool: lib.concatMapStrings (rule: f tool rule) rules) tools;
      cleanup = forRules (
        tool: rule: ''
          mss_rules=$(${tool} -w 5 -t mangle -S) || exit $?
          while IFS= read -r mss_rule; do
            if [[ "$mss_rule" == ${lib.escapeShellArg "-A ${rule}"} ]]; then
              ${tool} -w 5 -t mangle -D ${rule} || exit $?
            fi
          done <<< "$mss_rules"
        ''
      );
    in
    {
      networking.firewall =
        lib.mkIf (config.networking.firewall.enable && config.networking.firewall.backend == "iptables")
          {
            extraCommands =
              cleanup
              + forRules (
                tool: rule: ''
                  ${tool} -w 5 -t mangle -A ${rule} || exit $?
                ''
              );
            extraStopCommands = cleanup;
          };
    };
}

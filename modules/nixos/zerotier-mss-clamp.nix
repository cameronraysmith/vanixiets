# Fixed MSS limits TCP segments on constrained ZeroTier paths, not UDP or every PMTU.
# On nftables hosts the clamp is a table of its own, which nftables.service replaces
# atomically on start and reload and deletes on stop, so it needs none of the iptables
# branch's duplicate cleanup.
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
      # TCPMSS --set-mss never raises a smaller MSS, but nftables' maxseg set writes
      # unconditionally, so the size guard is what keeps a 1200 offer at 1200. The
      # counter makes a live rewrite observable without tracing.
      nftClamp = "tcp flags & (syn | rst) == syn tcp option maxseg size > 1300 counter tcp option maxseg size set 1300";
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

      networking.nftables.tables.zerotier-mss-clamp = lib.mkIf config.networking.nftables.enable {
        family = if config.networking.enableIPv6 then "inet" else "ip";
        content = ''
          chain input {
            type filter hook input priority mangle; policy accept;
            iifname "zt*" ${nftClamp}
          }
          chain output {
            type filter hook output priority mangle; policy accept;
            oifname "zt*" ${nftClamp}
          }
        '';
      };
    };
}

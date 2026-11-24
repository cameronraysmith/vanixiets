{ self, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      # The tests' names depend on `system` alone, so reading the vmTests
      # names instantiates no nixpkgs (declare-test-size-classes design D5).
      linux = lib.elem system [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # Backend-independent: a veth named like a ZeroTier interface and a SYN
      # probe that reads the negotiated MSS on both ends, dual-stack.
      packetOracle = ''
        import shlex, textwrap
        machine.succeed("ip netns add peer")
        machine.succeed("ip link add zttest type veth peer name eth0 netns peer")
        machine.succeed("ip link set zttest mtu 2800 up")
        machine.succeed("ip netns exec peer ip link set eth0 mtu 2800 up")
        machine.succeed("ip netns exec peer ip link set lo up")
        machine.succeed("ip addr add 192.0.2.1/24 dev zttest")
        machine.succeed("ip -6 addr add fd00::1/64 dev zttest nodad")
        machine.succeed("ip netns exec peer ip addr add 192.0.2.2/24 dev eth0")
        machine.succeed("ip netns exec peer ip -6 addr add fd00::2/64 dev eth0 nodad")
        machine.succeed("ip netns exec peer sysctl -w net.ipv4.tcp_timestamps=0")
        probe = """
        import socket, sys
        mode, address, offered = sys.argv[1:]
        s = socket.socket(socket.AF_INET6 if ':' in address else socket.AF_INET)
        s.settimeout(10)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_MAXSEG, int(offered))
        if mode == 'server':
            s.bind((address, 8080))
            s.listen(1)
            open('/tmp/mss-ready', 'w').close()
            s, _ = s.accept()
        else:
            s.connect((address, 8080))
        print(s.getsockopt(socket.IPPROTO_TCP, socket.TCP_MAXSEG), flush=True)
        s.sendall(b'x')
        assert s.recv(1) == b'x'
        """
        machine.succeed("printf %s " + shlex.quote(textwrap.dedent(probe)) + " > /tmp/mss-probe.py")

        def packets(clamped):
            for address in ("192.0.2.1", "fd00::1"):
                for offered in (1460, 1200):
                    expected = min(offered, 1300) if clamped else offered
                    machine.succeed("rm -f /tmp/mss-ready /tmp/mss-server")
                    machine.succeed(f"python /tmp/mss-probe.py server {address} {offered} > /tmp/mss-server 2>&1 &")
                    machine.wait_until_succeeds("test -e /tmp/mss-ready", timeout=10)
                    result = machine.succeed(f"ip netns exec peer python /tmp/mss-probe.py client {address} {offered}")
                    assert int(result.strip()) == expected, (address, offered, result)
                    machine.wait_until_succeeds("test -s /tmp/mss-server", timeout=10)
                    result = machine.succeed("cat /tmp/mss-server")
                    assert int(result.strip()) == expected, (address, offered, result)
      '';
      node = {
        imports = [ self.modules.nixos.zerotier-mss-clamp ];
        networking.firewall.enable = true;
        networking.firewall.trustedInterfaces = [ "zttest" ];
        networking.firewall.checkReversePath = false;
        boot.kernel.sysctl."net.ipv4.tcp_timestamps" = 0;
        environment.systemPackages = [ pkgs.python3 ];
      };
    in
    {
      # Size classes: on x86_64-linux zerotier-mss-clamp-runtime's script
      # measured 35.53 s on pyrite on 2026-11-23
      # (logs/ws-pyrite-qemu-20261123T1709Z.log), and the nftables variant's
      # whole build, driver included, 62 s on 2026-11-16
      # (logs/clamp-vmtests-pyrite-20261116-110310.log). The fleet has no
      # aarch64-linux builder, so no run can measure that system's tests,
      # which are declared medium and unmeasured
      # (declare-test-size-classes design D4).
      testSizes.vmTests =
        lib.optionalAttrs (system == "x86_64-linux") {
          zerotier-mss-clamp-runtime.class = "small";
          zerotier-mss-clamp-runtime-nftables.class = "medium";
        }
        // lib.optionalAttrs (system == "aarch64-linux") {
          zerotier-mss-clamp-runtime = {
            class = "medium";
            measured = false;
          };
          zerotier-mss-clamp-runtime-nftables = {
            class = "medium";
            measured = false;
          };
        };
      vmTests = lib.optionalAttrs linux {
        zerotier-mss-clamp-runtime = pkgs.testers.runNixOSTest {
          name = "zerotier-mss-clamp-runtime";
          requiredFeatures = {
            kvm = true;
            nixos-test = true;
          };
          qemu.forceAccel = true;
          nodes.machine = { config, ... }: {
            imports = [ node ];
            environment.etc."mss-start".text = config.networking.firewall.extraCommands;
            environment.etc."mss-stop".text = config.networking.firewall.extraStopCommands;
          };
          testScript = ''
            import shlex

            start_all()
            machine.wait_for_unit("firewall.service")
            tools = ("iptables", "ip6tables")
            rules = {
                "INPUT": "-i zt+ -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300",
                "OUTPUT": "-o zt+ -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300",
            }

            def listing(tool):
                return machine.succeed(f"{tool} -w 5 -t mangle -S").splitlines()

            def unrelated(tool):
                owned = [f"-A {chain} {rule}" for chain, rule in rules.items()]
                return [line for line in listing(tool) if line not in owned]

            def check_rules(count, active=True):
                for tool in tools:
                    lines = listing(tool)
                    for chain, rule in rules.items():
                        expected = f"-A {chain} {rule}"
                        assert lines.count(expected) == count, (tool, expected, lines)
                    if active:
                        machine.succeed(f"{tool} -w 5 -C INPUT -j nixos-fw")

            with subtest("initial install"):
                check_rules(1)

            for tool in tools:
                machine.succeed(f"{tool} -t mangle -N mss-sentinel")
                machine.succeed(f"{tool} -t mangle -A mss-sentinel -j RETURN")
                machine.succeed(f"{tool} -t mangle -A OUTPUT -o lo -j mss-sentinel")
                for chain, rule in rules.items():
                    for near in (rule.replace("1300", "1299"), rule.replace("zt+", "other+"), rule + " -m comment --comment unrelated"):
                        machine.succeed(f"{tool} -t mangle -A {chain} {near}")
            sentinels = {tool: unrelated(tool) for tool in tools}

            def preserved():
                for tool in tools:
                    assert unrelated(tool) == sentinels[tool], (tool, unrelated(tool))

            with subtest("six exact legacy copies converge on reload"):
                for tool in tools:
                    for chain, rule in rules.items():
                        for _ in range(5):
                            machine.succeed(f"{tool} -t mangle -A {chain} {rule}")
                check_rules(6)
                machine.succeed("systemctl reload firewall.service")
                check_rules(1)
                preserved()

            with subtest("bounded reload and restart"):
                # Reload is the path a nixos-rebuild switch takes, since
                # firewall.service is reloadIfChanged and its reloadScript runs
                # extraStopCommands then startScript; restart additionally
                # covers ExecStop plus ExecStart. Repeating either adds nothing.
                for action in ("reload", "restart"):
                    machine.succeed(f"systemctl {action} firewall.service")
                    check_rules(1)
                    preserved()

            with subtest("stop preserves every sentinel and near-match"):
                machine.succeed("systemctl stop firewall.service")
                check_rules(0, active=False)
                preserved()
                machine.succeed("bash /etc/mss-stop")
                check_rules(0, active=False)
                preserved()
                machine.succeed("systemctl start firewall.service")
                check_rules(1)
                preserved()

            with subtest("startup alone converges exact legacy duplicates"):
                for tool in tools:
                    for chain, rule in rules.items():
                        for _ in range(5):
                            machine.succeed(f"{tool} -t mangle -A {chain} {rule}")
                check_rules(6)
                machine.succeed("bash /etc/mss-start")
                check_rules(1)
                preserved()

            with subtest("material listing deletion and insertion errors propagate"):
                # Each case resets through the module's own generated hook rather
                # than a systemd restart: the hook cleans before it adds, so it
                # converges from any partially-applied state, it re-asserts
                # idempotency for free, and six consecutive restarts would breach
                # systemd's StartLimitBurst on an accelerated VM.
                for tool in tools:
                    for hook, action, code in (("stop", "-S", 42), ("stop", "-D", 43), ("start", "-A", 44)):
                        script = f"""{tool}() {{
                          for arg in "$@"; do
                            if [[ "$arg" == {action} ]]; then return {code}; fi
                          done
                          command {tool} "$@"
                        }}
                        source /etc/mss-{hook}
                        """
                        status, output = machine.execute("bash -c " + shlex.quote(script))
                        assert status == code, (tool, hook, action, status, output)
                        machine.succeed("bash /etc/mss-start")
                        check_rules(1)
                        preserved()

            ${packetOracle}

            # Near-match clamps are retained, but must not affect the packet oracle.
            for tool in tools:
                for chain, rule in rules.items():
                    machine.succeed(f"{tool} -t mangle -D {chain} {rule.replace('1300', '1299')}")
                    machine.succeed(f"{tool} -t mangle -D {chain} {rule} -m comment --comment unrelated")
            sentinels = {tool: unrelated(tool) for tool in tools}
            with subtest("dual-stack SYN negotiation clamps both directions without raising smaller MSS"):
                packets(True)
            with subtest("stop and repeated absent cleanup preserve unrelated rules"):
                machine.succeed("systemctl stop firewall.service")
                check_rules(0, active=False)
                preserved()
                machine.succeed("bash /etc/mss-stop")
                check_rules(0, active=False)
                preserved()
                packets(False)
            with subtest("re-enable restores exactly one rule each"):
                machine.succeed("systemctl start firewall.service")
                check_rules(1)
                preserved()
                packets(True)
          '';
        };
        zerotier-mss-clamp-runtime-nftables = pkgs.testers.runNixOSTest {
          name = "zerotier-mss-clamp-runtime-nftables";
          requiredFeatures = {
            kvm = true;
            nixos-test = true;
          };
          qemu.forceAccel = true;
          nodes.machine = {
            imports = [ node ];
            networking.nftables.enable = true;
          };
          testScript = ''
            start_all()
            machine.wait_for_unit("nftables.service")
            clamp = "table inet zerotier-mss-clamp"

            def check_table(count):
                tables = machine.succeed("nft list tables").splitlines()
                assert tables.count(clamp) == count, tables
                if count:
                    ruleset = machine.succeed(f"nft list {clamp}")
                    for match in ('iifname "zt*"', 'oifname "zt*"'):
                        assert ruleset.count(match) == 1, (match, ruleset)
                    assert ruleset.count("maxseg size set 1300") == 2, ruleset
                    machine.succeed("nft list chain inet nixos-fw input")

            # Another owner's table, standing in for incus's and podman's, must
            # survive every lifecycle action on nftables.service.
            machine.succeed("nft add table inet mss-sentinel")
            machine.succeed("nft add chain inet mss-sentinel output '{ type filter hook output priority 0; }'")
            machine.succeed("nft add rule inet mss-sentinel output oifname lo accept")
            sentinel = machine.succeed("nft list table inet mss-sentinel")

            def preserved():
                assert machine.succeed("nft list table inet mss-sentinel") == sentinel

            with subtest("initial install"):
                check_table(1)

            with subtest("bounded reload and restart"):
                # Reload is the path a nixos-rebuild switch takes, since
                # nftables.service is reloadIfChanged; it re-runs the ruleset,
                # which deletes and recreates the clamp table in one transaction.
                for action in ("reload", "restart"):
                    machine.succeed(f"systemctl {action} nftables.service")
                    check_table(1)
                    preserved()

            ${packetOracle}
            with subtest("dual-stack SYN negotiation clamps both directions without raising smaller MSS"):
                packets(True)
            with subtest("stop removes the clamp and preserves unrelated tables"):
                machine.succeed("systemctl stop nftables.service")
                check_table(0)
                preserved()
                packets(False)
            with subtest("re-enable restores exactly one table"):
                machine.succeed("systemctl start nftables.service")
                check_table(1)
                preserved()
                packets(True)
          '';
        };
      };
    };
}

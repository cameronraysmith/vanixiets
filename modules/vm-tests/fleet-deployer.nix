# vmTests.x86_64-linux.fleet-deployer: the fleet deployer's request path end
# to end in two QEMU VMs (openspec change delegate-fleet-deploys).
#
# `deployer` imports flake.modules.nixos.fleet-deployer with its fleet
# defaults replaced: a local bare repository stands in for the forge, a
# file:// binary cache for niks3, a recording ntfy-send for ntfy, and three
# stubs for what needs the real flake and clan: resolveCommand reads the
# closure a test commit names, varsCheckCommand fails when a commit carries
# `vars-broken`, and deployCommand switches the target to that closure over
# SSH. `target` imports the deploy record and the rollback watcher; its
# specialisations are the configurations deployed: `next`, `broken` (a
# failing unit) and `isolated` (a firewall dropping the deployer's SSH).
#
# Requests arrive through sshd's forced command with nixpkgs' snake-oil key.
# Cases: a merged commit (0), an unmerged commit and a host outside the
# requester's reach refused before any connection to the target (3), an
# uncached closure and a failed vars check refused (3), a held host lock
# (4), a stopped sshd (5, within 15 s, no host lock taken), two concurrent
# requests serialised, a failed unit (7, kept), a deploy that cuts SSH
# rolled back by the target itself (8), one notice per request, high
# priority for 3, 7 and 8, and the key check failing on a widened key file.
#
# It establishes nothing about clan, the forge, niks3, ntfy or darwin, which
# the change's verification observes on the fleet.
{ self, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      nodePkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      };
      keys = import (pkgs.path + "/nixos/tests/ssh-keys.nix") pkgs;
      stub =
        name: text:
        lib.getExe (
          pkgs.writeShellApplication {
            inherit name text;
            runtimeInputs = [
              pkgs.coreutils
              pkgs.openssh
              pkgs.jq
            ];
          }
        );
      recordingNtfySend = pkgs.writeShellApplication {
        name = "ntfy-send";
        text = ''
          printf '%s\t%s\t%s\n' "$1" "''${2:-}" "''${*:3}" >>/var/lib/fleet-deploy-notify/posts
        '';
      };
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      vmTests.fleet-deployer = pkgs.testers.runNixOSTest (
        { nodes, ... }:
        let
          base = nodes.target.system.build.toplevel;
          # The resolved store path, which activation records as $systemConfig.
          spec = name: "${nodes.target.specialisation.${name}.configuration.system.build.toplevel}";
        in
        {
          name = "fleet-deployer";
          requiredFeatures = {
            kvm = true;
            nixos-test = true;
          };
          qemu.forceAccel = true;
          node.pkgs = lib.mkForce nodePkgs;
          nodes.deployer =
            { nodes, ... }:
            {
              imports = [ self.modules.nixos.fleet-deployer ];
              config = {
                services.openssh.enable = true;
                services.fleet-deployer = {
                  ntfySend = recordingNtfySend;
                  notifyTokenFile = "/dev/null";
                  requesterLines = [
                    ''restrict,command="/run/current-system/sw/bin/fleet-deploy-request op" ${keys.snakeOilPublicKey}''
                  ];
                  requestConfig = {
                    targets = {
                      target = {
                        class = "nixos";
                        deployUser = "root";
                      };
                      other = {
                        class = "nixos";
                        deployUser = "root";
                      };
                    };
                    machines = [ "target" ];
                    requesters.op = [ "target" ];
                    cacheStore = "file:///var/lib/test-cache";
                    forge = "/srv/forge.git";
                    stateDir = "/var/lib/fleet-deployer";
                    runDir = "/run/fleet-deployer";
                    lockWait = 20;
                    slots = 2;
                    probeTimeout = 5;
                    settle = 3;
                    confirmWindow = 20;
                    activationWait = 120;
                    resolveCommand = stub "resolve" ''
                      jq -n --arg c "$(cat "$1/closure")" '{closure: $c, targetHost: "root@target"}'
                    '';
                    varsCheckCommand = stub "vars-check" ''test ! -e "$1/vars-broken"'';
                    cacheCheckCommand = stub "cache-check" ''test -e "/var/lib/test-cache/$(basename "$1")"'';
                    deployCommand = stub "deploy" ''
                      log=/var/lib/fleet-deployer/deploy.log
                      echo "start $(date +%s.%N) $4" >>"$log"
                      unit="test-switch-$RANDOM"
                      ssh "$3" systemd-run --collect "--unit=$unit" "$4/bin/switch-to-configuration" switch
                      sleep 4
                      echo "end $(date +%s.%N) $4" >>"$log"
                    '';
                  };
                };
                programs.ssh.extraConfig = "StrictHostKeyChecking no";
                # The test forge is owned by root and fetched by fleet-deployer.
                programs.git = {
                  enable = true;
                  config.safe.directory = "*";
                };
                environment.systemPackages = [
                  pkgs.git
                  pkgs.nix
                ];
                virtualisation.additionalPaths = [ nodes.target.system.build.toplevel ];
                nix.settings.experimental-features = [ "nix-command" ];
              };
            };

          nodes.target =
            { nodes, pkgs, ... }:
            {
              imports = [ self.modules.nixos.deploy-record ];
              services.openssh.enable = true;
              environment.systemPackages = [ pkgs.fleet-deploy-watch ];
              nix.settings.experimental-features = [ "nix-command" ];
              specialisation = {
                next.configuration.environment.etc."deployed".text = "next";
                broken.configuration.systemd.services.broken = {
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig.Type = "oneshot";
                  script = "exit 1";
                };
                isolated.configuration.networking.firewall.extraCommands = ''
                  iptables -I INPUT -s ${nodes.deployer.networking.primaryIPAddress} -p tcp --dport 22 -j DROP
                  ip6tables -I INPUT -s ${nodes.deployer.networking.primaryIPv6Address} -p tcp --dport 22 -j DROP
                '';
              };
            };

          testScript = ''
            import json, shlex, time

            start_all()
            target.wait_for_unit("sshd.service")
            deployer.wait_for_unit("multi-user.target")
            deployer.wait_for_unit("fleet-deployer-keys.service")
            deployer.succeed("systemctl start fleet-deployer-keycheck.service")

            pub = deployer.succeed("cat /var/lib/fleet-deployer/keys/id_ed25519.pub").strip()
            deployer_ip = "${nodes.deployer.networking.primaryIPAddress},${nodes.deployer.networking.primaryIPv6Address}"
            target.succeed("mkdir -p /root/.ssh && chmod 700 /root/.ssh")
            line = 'from="%s",restrict %s' % (deployer_ip, pub)
            target.succeed(f"echo {shlex.quote(line)} >> /root/.ssh/authorized_keys")

            deployer.succeed("install -m 600 ${keys.snakeOilPrivateKey} /root/requester")
            deployer.succeed("mkdir -p /var/lib/test-cache")

            # The forge: main carries `next`; a branch carries `broken` unmerged.
            def commit(name, files, branch="main"):
                script = f"cd /srv/work && git checkout -q -B {branch} && rm -f closure vars-broken"
                for path, text in files.items():
                    script += f" && printf %s {shlex.quote(text)} > {path}"
                script += f" && git add -A && git commit -q -m {name} && git push -q -f origin {branch}"
                deployer.succeed(script)
                return deployer.succeed("git -C /srv/work rev-parse HEAD").strip()

            deployer.succeed(
                "git init -q --bare /srv/forge.git"
                " && git init -q /srv/work && cd /srv/work && git config user.email t@t && git config user.name t"
                " && git remote add origin /srv/forge.git"
            )
            # The stand-in cache holds a marker per built closure.
            for closure in ("${spec "next"}", "${spec "broken"}", "${spec "isolated"}"):
                deployer.succeed(f"touch /var/lib/test-cache/$(basename {closure})")

            def request(command, expect):
                status, out = deployer.execute(
                    f"ssh -i /root/requester -o StrictHostKeyChecking=no fleet-deployer@localhost {shlex.quote(command)}"
                )
                print(out)
                assert status == expect, (command, status, expect)
                return out

            def records():
                text = deployer.succeed("cat /var/lib/fleet-deployer/requests.jsonl")
                return [json.loads(line) for line in text.splitlines()]

            def current():
                return target.succeed("readlink -f /run/current-system").strip()

            def accepted():
                return int(target.succeed("journalctl -u sshd --no-pager | grep -c 'Accepted publickey' || true").strip())

            with subtest("a merged commit is deployed and confirmed"):
                c1 = commit("next", {"closure": "${spec "next"}"})
                request("deploy target", 0)
                assert current() == "${spec "next"}"
                last = json.loads(target.succeed("tail -n1 /var/log/deploy-record.jsonl"))
                assert last["closure"] == "${spec "next"}", last
                assert records()[-1]["outcome"] == "deployed" and records()[-1]["commit"] == c1

            with subtest("an unmerged commit and an unreachable host are refused without contacting the target"):
                before = accepted()
                c_feature = commit("feature", {"closure": "${spec "broken"}"}, branch="feature")
                deployer.succeed("cd /srv/work && git checkout -q main")
                request(f"deploy target {c_feature}", 3)
                request("deploy other", 3)
                request("deploy stibnite", 3)
                request("shell", 3)
                assert accepted() == before, "the target was contacted"

            with subtest("an uncached closure and a failed vars check are refused"):
                commit("base", {"closure": "${base}"})
                request("deploy target", 3)
                assert "not in" in records()[-1]["reason"]
                commit("vars", {"closure": "${spec "next"}", "vars-broken": "x"})
                request("deploy target", 3)
                assert "vars check" in records()[-1]["reason"]

            with subtest("a held host lock ends the request as busy"):
                commit("next-again", {"closure": "${spec "next"}"})
                deployer.succeed("su -s /bin/sh fleet-deployer -c 'flock /run/fleet-deployer/lock/target sleep 40' >/dev/null 2>&1 &")
                time.sleep(2)
                request("deploy target", 4)
                deployer.wait_until_succeeds("flock -n /run/fleet-deployer/lock/target true", timeout=60)

            with subtest("two concurrent requests are serialised"):
                deployer.succeed("rm -f /var/lib/fleet-deployer/deploy.log")
                deployer.succeed(
                    "for i in 1 2; do (ssh -i /root/requester -o StrictHostKeyChecking=no fleet-deployer@localhost 'deploy target' > /tmp/req$i 2>&1; echo $? > /tmp/req$i.status) & sleep 1; done; wait"
                )
                deployer.wait_until_succeeds("test -e /tmp/req1.status && test -e /tmp/req2.status", timeout=120)
                assert deployer.succeed("cat /tmp/req1.status /tmp/req2.status").split() == ["0", "0"]
                steps = [entry.split() for entry in deployer.succeed("cat /var/lib/fleet-deployer/deploy.log").splitlines()]
                assert [step[0] for step in steps] == ["start", "end", "start", "end"], steps
                assert float(steps[2][1]) >= float(steps[1][1]), steps

            with subtest("a stopped sshd ends the request as unreachable within 15 s"):
                target.succeed("systemctl stop sshd.service sshd.socket || systemctl stop sshd.service")
                deployer.succeed("rm -f /run/fleet-deployer/lock/target")
                started = time.monotonic()
                request("deploy target", 5)
                assert time.monotonic() - started < 15
                deployer.fail("test -e /run/fleet-deployer/lock/target")
                target.succeed("systemctl start sshd.service")
                target.wait_for_unit("sshd.service")

            with subtest("a failed unit is reported and kept"):
                commit("broken", {"closure": "${spec "broken"}"})
                out = request("deploy target", 7)
                assert "failed unit broken.service" in out
                time.sleep(30)
                assert current() == "${spec "broken"}", "an unhealthy deploy was rolled back"

            with subtest("a deploy that cuts SSH is rolled back by the target"):
                commit("isolated", {"closure": "${spec "isolated"}"})
                request("deploy target", 8)
                target.wait_until_succeeds("test \"$(readlink -f /run/current-system)\" = ${spec "broken"}", timeout=60)
                last = json.loads(target.succeed("tail -n1 /var/log/deploy-record.jsonl"))
                assert last["closure"] == "${spec "broken"}" and last["previous_closure"] == "${spec "isolated"}", last

            with subtest("every request is announced once, refusals and failures at high priority"):
                n = len(records())
                deployer.wait_until_succeeds(f"test $(wc -l < /var/lib/fleet-deploy-notify/posts) -eq {n}", timeout=30)
                posts = deployer.succeed("cat /var/lib/fleet-deploy-notify/posts").splitlines()
                for record, post in zip(records(), posts):
                    message, topic, extra = post.split("\t")
                    assert topic == "fleet-deploy", post
                    assert message.startswith(record["outcome"] + ":"), (record, post)
                    assert ("Priority: high" in extra) == (record["outcome"] in ("refused", "unhealthy", "rolled-back")), (record, post)
                deployer.succeed("test $(stat -c %a /var/lib/fleet-deployer/requests.jsonl) = 600")

            with subtest("the key check fails on a widened key file"):
                deployer.succeed("chmod 0440 /var/lib/fleet-deployer/keys/age.key")
                deployer.fail("systemctl start fleet-deployer-keycheck.service")
                deployer.succeed("chmod 0400 /var/lib/fleet-deployer/keys/age.key")
                deployer.succeed("systemctl start fleet-deployer-keycheck.service")
          '';
        }
      );
    };
}

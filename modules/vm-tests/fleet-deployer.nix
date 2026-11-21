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
# rolled back by the target itself and read back on its previous closure
# (8), one notice per request, high
# priority for 3, 7 and 8, the key check failing on a widened key file, and a
# deploy of the deployer itself, reached over loopback (F82), whose switch
# restarts sshd and replaces the request command while the request runs.
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
      # Every stand-in needs what clan and nix need from their environment: a
      # writable HOME and XDG_RUNTIME_DIR (clan's cache) and TMPDIR, and
      # records what it got, so the test sees the environment the request
      # command gives them.
      stub =
        name: text:
        lib.getExe (
          pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = [
              pkgs.coreutils
              pkgs.openssh
              pkgs.jq
            ];
            text = ''
              [ -n "''${HOME:-}" ] && [ -w "$HOME" ] || { echo "${name}: HOME unusable" >&2; exit 90; }
              mkdir -p "''${XDG_RUNTIME_DIR:?}/clan-cache" || { echo "${name}: XDG_RUNTIME_DIR unusable" >&2; exit 91; }
              [ -w "''${TMPDIR:-/tmp}" ] || { echo "${name}: TMPDIR unusable" >&2; exit 92; }
              printf 'HOME=%s\nXDG_RUNTIME_DIR=%s\nTMPDIR=%s\n' "$HOME" "$XDG_RUNTIME_DIR" "''${TMPDIR:-}" >/var/lib/fleet-deployer/stub-env
              ${text}
            '';
          }
        );
      recordingNtfySend = pkgs.writeShellApplication {
        name = "ntfy-send";
        text = ''
          printf '%s\t%s\t%s\n' "$1" "''${2:-}" "''${*:3}" >>/var/lib/fleet-deploy-notify/posts
        '';
      };
      # $1 must be `git+file://<worktree>?rev=<commit>`; sets $tree.
      worktreeOf = ''
        case "$1" in
          git+file://*\?rev=*) ;;
          *) echo "not a git flake reference pinned to a commit: $1" >&2; exit 93 ;;
        esac
        tree=''${1#git+file://}
        tree=''${tree%%\?*}
      '';
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      vmTests.fleet-deployer = pkgs.testers.runNixOSTest (
        { nodes, ... }:
        let
          base = nodes.target.system.build.toplevel;
          # The resolved store path, which activation records as $systemConfig.
          spec = name: "${nodes.target.specialisation.${name}.configuration.system.build.toplevel}";
          switched = "${nodes.deployer.specialisation.switched.configuration.system.build.toplevel}";
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
              imports = [
                self.modules.nixos.fleet-deployer
                self.modules.nixos.deploy-record
              ];
              config = {
                services.openssh.enable = true;
                # Deploying the deployer itself (F82): a generation whose request
                # command (its config) and sshd differ, switched to while the
                # request that deploys it runs.
                specialisation.switched.configuration = {
                  services.fleet-deployer.requestConfig.generation = "switched";
                  services.openssh.settings.LoginGraceTime = 119;
                };
                services.fleet-deployer = {
                  ntfySend = recordingNtfySend;
                  notifyTokenFile = "/dev/null";
                  # The VM generates its own keys, which are not the committed ones.
                  keys = null;
                  requesterLines = [
                    ''restrict,command="/run/current-system/sw/bin/fleet-deploy-request op" ${keys.snakeOilPublicKey}''
                  ];
                  requestConfig = {
                    targets = {
                      target = {
                        class = "nixos";
                        deployUser = "root";
                        targetHost = "root@target";
                      };
                      other = {
                        class = "nixos";
                        deployUser = "root";
                        targetHost = "root@other";
                      };
                      deployer = {
                        class = "nixos";
                        deployUser = "root";
                        targetHost = "root@deployer";
                      };
                    };
                    machines = [
                      "target"
                      "deployer"
                    ];
                    requesters.op = [
                      "target"
                      "deployer"
                    ];
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
                    rollbackGrace = 60;
                    # The stand-ins receive the flake reference the real steps use;
                    # each refuses anything but a git reference pinned to a commit
                    # and reads the commit's files from the worktree it names.
                    resolveCommand = stub "resolve" ''
                      ${worktreeOf}
                      host=root@target
                      if [ -e "$tree/host" ]; then host=$(cat "$tree/host"); fi
                      jq -n --arg c "$(cat "$tree/closure")" --arg h "$host" '{closure: $c, targetHost: $h}'
                    '';
                    varsCheckCommand = stub "vars-check" ''
                      ${worktreeOf}
                      test ! -e "$tree/vars-broken"
                    '';
                    cacheCheckCommand = stub "cache-check" ''test -e "/var/lib/test-cache/$(basename "$1")"'';
                    deployCommand = stub "deploy" ''
                      ${worktreeOf}
                      log=/var/lib/fleet-deployer/deploy.log
                      echo "start $(date +%s.%N) $4" >>"$log"
                      if [ -e "$tree/no-switch" ]; then
                        # An activation that writes its deploy record and exits 0
                        # without relinking /run/current-system (F72's half switch).
                        # shellcheck disable=SC2029
                        ssh "$3" half-activate "$4"
                      else
                        unit="test-switch-$RANDOM"
                        ssh "$3" systemd-run --collect "--unit=$unit" "$4/bin/switch-to-configuration" switch
                      fi
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
                  nodePkgs.fleet-deploy-watch
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
              environment.systemPackages = [
                pkgs.fleet-deploy-watch
                # Writes the deploy record an activation would and leaves
                # /run/current-system where it is.
                (pkgs.writeShellScriptBin "half-activate" ''
                  printf '{"host":"target","closure":"%s","previous_closure":"%s","ts":"x"}\n' \
                    "$1" "$(readlink -f /run/current-system)" >>/var/log/deploy-record.jsonl
                '')
              ];
              nix.settings.experimental-features = [ "nix-command" ];
              specialisation = {
                next.configuration.environment.etc."deployed".text = "next";
                broken.configuration.systemd.services.broken = {
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig.Type = "oneshot";
                  script = "exit 1";
                };
                # In nixos-fw, which every firewall reload flushes, so the
                # rollback to `broken` restores SSH and the deployer can read
                # the target back on its previous closure (F84).
                isolated.configuration.networking.firewall.extraCommands = ''
                  iptables -I nixos-fw -s ${nodes.deployer.networking.primaryIPAddress} -p tcp --dport 22 -j DROP
                  ip6tables -I nixos-fw -s ${nodes.deployer.networking.primaryIPv6Address} -p tcp --dport 22 -j DROP
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
                script = f"cd /srv/work && git checkout -q -B {branch} && rm -f closure host vars-broken no-switch"
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
            for closure in ("${spec "next"}", "${spec "broken"}", "${spec "isolated"}", "${switched}"):
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

            with subtest("a deploy of the running closure ends its watcher once confirmed"):
                # F90: the link never changes, so only the confirmation ends the
                # watcher; it must not wait out activationWait.
                commit("again", {"closure": "${spec "next"}", "again": "1"})
                request("deploy target", 0)
                target.wait_until_succeeds(
                    "! systemctl list-units --no-legend --state=active,activating 'fleet-deploy-watch-*' | grep -q .",
                    timeout=10,
                )
                target.succeed("journalctl --no-pager -t fleet-deploy-watch | grep -q 'confirmed; the system did not change'")
                assert current() == "${spec "next"}"

            with subtest("a request in a hostile inherited environment still deploys"):
                # sshd or runuser may hand the account root's runtime directory, no HOME
                # and an unwritable TMPDIR; the request command must not use them.
                deployer.succeed("mkdir -p /run/user/0 /root/tmp && chmod 0700 /run/user/0 /root/tmp")
                status, out = deployer.execute(
                    "SSH_ORIGINAL_COMMAND='deploy target' XDG_RUNTIME_DIR=/run/user/0 TMPDIR=/root/tmp"
                    " runuser -m -u fleet-deployer -- env -u HOME /run/current-system/sw/bin/fleet-deploy-request op"
                )
                print(out)
                assert status == 0, (status, out)
                got = dict(entry.split("=", 1) for entry in deployer.succeed("cat /var/lib/fleet-deployer/stub-env").splitlines())
                assert got["HOME"] == "/var/lib/fleet-deployer", got
                assert got["XDG_RUNTIME_DIR"].startswith("/var/lib/fleet-deployer/"), got
                assert got["TMPDIR"].startswith("/var/lib/fleet-deployer/"), got
                deployer.succeed("test $(stat -c %a \"$(sed -n 's/^XDG_RUNTIME_DIR=//p' /var/lib/fleet-deployer/stub-env)\") = 700")

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

            with subtest("an activation that leaves the running system unchanged is unhealthy"):
                running = current()
                commit("half-switch", {"closure": "${spec "broken"}", "no-switch": "x"})
                out = request("deploy target", 7)
                assert f"the running system is {running}, not the deployed ${spec "broken"}" in out, out
                last = json.loads(target.succeed("tail -n1 /var/log/deploy-record.jsonl"))
                assert last["closure"] == "${spec "broken"}", last
                assert current() == running
                assert records()[-1]["outcome"] == "unhealthy", records()[-1]

            with subtest("a failed unit is reported and kept"):
                commit("broken", {"closure": "${spec "broken"}"})
                out = request("deploy target", 7)
                assert "failed unit broken.service" in out
                time.sleep(30)
                assert current() == "${spec "broken"}", "an unhealthy deploy was rolled back"

            with subtest("a deploy that cuts SSH is rolled back by the target"):
                commit("isolated", {"closure": "${spec "isolated"}"})
                out = request("deploy target", 8)
                assert "returned to ${spec "broken"}" in out, out
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
                    assert ("Priority: high" in extra) == (record["outcome"] in ("refused", "unhealthy", "rolled-back", "unconfirmed")), (record, post)
                deployer.succeed("test $(stat -c %a /var/lib/fleet-deployer/requests.jsonl) = 600")

            with subtest("the key check fails on a widened key file"):
                deployer.succeed("chmod 0440 /var/lib/fleet-deployer/keys/age.key")
                deployer.fail("systemctl start fleet-deployer-keycheck.service")
                deployer.succeed("chmod 0400 /var/lib/fleet-deployer/keys/age.key")
                deployer.succeed("systemctl start fleet-deployer-keycheck.service")

            with subtest("a request that switches the deployer's own system survives the switch"):
                # The deployer reaches its own host by name over loopback (F82).
                own = 'from="127.0.0.1,::1,%s",restrict %s' % (deployer_ip, pub)
                deployer.succeed(f"mkdir -p /root/.ssh && chmod 700 /root/.ssh && echo {shlex.quote(own)} >> /root/.ssh/authorized_keys")
                sshd_before = deployer.succeed("systemctl show -p MainPID --value sshd.service").strip()
                request_before = deployer.succeed("readlink -f /run/current-system/sw/bin/fleet-deploy-request").strip()
                commit("switched", {"closure": "${switched}", "host": "root@deployer"})
                out = request("deploy deployer", 0)
                assert "deployed: deployer runs ${switched}" in out, out
                assert deployer.succeed("readlink -f /run/current-system").strip() == "${switched}"
                assert deployer.succeed("systemctl show -p MainPID --value sshd.service").strip() != sshd_before, "sshd was not restarted"
                assert deployer.succeed("readlink -f /run/current-system/sw/bin/fleet-deploy-request").strip() != request_before, "the request command did not change"
                last = json.loads(deployer.succeed("tail -n1 /var/log/deploy-record.jsonl"))
                assert last["closure"] == "${switched}", last
                assert records()[-1]["outcome"] == "deployed" and records()[-1]["machine"] == "deployer", records()[-1]
          '';
        }
      );
    };
}

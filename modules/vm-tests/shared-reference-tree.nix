# Runtime behaviour of the shared ghq reference tree (openspec change
# share-ghq-reference-tree, design D8), on a KVM-capable x86_64-linux builder.
#
# Establishes, for a human reader and a worker reader on one node: delegated
# acquisition through the socket-activated writer, read-only git use, refusal of
# every reader write and of malformed requests, safe.directory scoped to the
# shared root, and that an outsider can neither list the tree nor reach the
# writer. A writer-planted core.fsmonitor is shown to run as the reader, so the
# assertions that readers cannot plant one are not vacuous; the writer's own
# write is the control that the write probe can observe success.
#
# The `mutations` attributes rerun the same script after breaking the permission
# model or the control; each must fail.
{ self, inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      nodePkgs = import inputs.nixpkgs {
        inherit (pkgs.stdenv.hostPlatform) system;
        config.allowUnfree = true;
        overlays = [ self.overlays.default ];
      };
      readers = [
        "cameron"
        "omnigent-cameron"
      ];
      mkTest =
        {
          name ? "shared-reference-tree",
          prelude ? "",
          control ? "touch",
        }:
        pkgs.testers.runNixOSTest {
          inherit name;
          requiredFeatures = {
            kvm = true;
            nixos-test = true;
          };
          qemu.forceAccel = true;
          node.pkgs = lib.mkForce nodePkgs;
          nodes.machine = {
            imports = [
              inputs.home-manager.nixosModules.home-manager
              self.modules.nixos.shared-reference-tree
            ];
            system.stateVersion = lib.trivial.release;
            networking.hostName = "shared-reference-tree";
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs.flake = self // {
                inherit inputs;
              };
              users = lib.genAttrs readers (_: {
                imports = [ self.modules.homeManager.repository-acquisition ];
                programs.git.enable = true;
                home.stateVersion = "25.11";
              });
            };
            users.users = {
              cameron.isNormalUser = true;
              omnigent-cameron = {
                isNormalUser = true;
                group = "omnigent-cameron";
                homeMode = "0700";
              };
              outsider.isNormalUser = true;
            };
            users.groups.omnigent-cameron = { };
            services.shared-reference-tree = {
              enable = true;
              participants = readers;
              allowedProtocols = [
                "https"
                "git"
              ];
            };
            services.gitDaemon = {
              enable = true;
              basePath = "/srv/git";
              exportAll = true;
            };
            systemd.tmpfiles.rules = [ "d /srv/git 0755 git git -" ];
            environment.systemPackages = [ nodePkgs.git ];
          };
          testScript = ''
            import shlex

            R = "/var/lib/ghq"
            P = f"{R}/localhost/fixture/hello"
            URL = "git://localhost/fixture/hello"
            readers = ${builtins.toJSON readers}
            client = "${nodePkgs.ghq-shared}/libexec/ghq-shared/ghq-writer-client"

            def as_user(user, command):
                return f"su - {user} -c {shlex.quote(command)}"

            def as_writer(command):
                return f"su -s /bin/sh ghq -c {shlex.quote(command)}"

            start_all()
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("git-daemon.service")
            machine.wait_for_unit("ghq-writer.socket")
            for user in readers:
                # Home Manager names the unit after the systemd-escaped account name.
                escaped = machine.succeed(f"systemd-escape {user}").strip()
                machine.wait_for_unit(f"home-manager-{escaped}.service")

            machine.succeed(
                "mkdir -p /srv/git/fixture /tmp/src"
                " && git init -q --bare -b main /srv/git/fixture/hello.git"
                " && git -C /srv/git/fixture/hello.git config uploadpack.allowFilter true"
                " && git init -q -b main /tmp/src"
                " && for i in 1 2 3; do git -C /tmp/src -c user.name=t -c user.email=t@t"
                " commit -q --allow-empty -m c$i; done"
                " && git -C /tmp/src push -q /srv/git/fixture/hello.git main"
                " && chown -R git:git /srv/git"
            )

            ${prelude}

            with subtest("each reader resolves the shared root"):
                for user in readers:
                    assert machine.succeed(as_user(user, "ghq root")).strip() == R
                    assert machine.succeed(as_user(user, "readlink -f ~/ghq")).strip() == R
                    dirs = machine.succeed(as_user(user, "git config --get-all safe.directory")).split()
                    assert dirs == [f"{R}/*"], dirs

            with subtest("a reader acquires a repository through the writer"):
                machine.succeed(as_user("cameron", f"ghq-sync {URL}"))
                assert machine.succeed(f"stat -c %U {P}").strip() == "ghq"
                assert machine.succeed(f"stat -c %U {P}/.git/config").strip() == "ghq"
                assert machine.succeed(as_writer(f"git -C {P} rev-parse --is-shallow-repository")).strip() == "true"
                machine.succeed(as_user("cameron", "ghq-sync --seed-zoxide hello"))
                assert machine.succeed(as_user("cameron", "zoxide query hello")).strip() == P

            with subtest("every reader reads it with git"):
                for user in readers:
                    assert machine.succeed(as_user(user, "ghq list -p fixture/hello")).strip() == P
                    machine.succeed(as_user(user, f"git -C {P} log -1 --oneline"))
                    machine.succeed(as_user(user, f"git -C {P} status"))

            with subtest("deepen, promote and update go through the writer"):
                machine.succeed(as_user("omnigent-cameron", f"ghq-sync --deepen 1 {P} | grep -Fx 'deepened: {P}'"))
                assert machine.succeed(as_writer(f"git -C {P} rev-list --count HEAD")).strip() == "2"
                machine.succeed(as_user("omnigent-cameron", f"ghq-sync --full {P} | grep -Fx 'promoted to full: {P}'"))
                assert machine.succeed(as_writer(f"git -C {P} rev-parse --is-shallow-repository")).strip() == "false"
                machine.succeed(as_user("omnigent-cameron", f"ghq get -u {URL}"))
                assert machine.succeed(f"find {R} ! -user ghq | wc -l").strip() == "0"

            with subtest("the writer's own write succeeds (control)"):
                machine.succeed(as_writer(f"${control} {P}/.control && rm -f {P}/.control"))

            with subtest("readers cannot write the tree"):
                for user in readers:
                    machine.fail(as_user(user, f"touch {P}/probe"))
                    machine.fail(as_user(user, f"mkdir {R}/probe"))
                    machine.fail(as_user(user, f"git -C {P} config core.fsmonitor /bin/false"))
                    machine.fail(as_user(user, f"git -C {P} fetch"))
                    machine.fail(as_user(user, f"git -C {P} gc"))
                    assert machine.succeed(as_writer(f"git -C {P} config --get core.fsmonitor || true")).strip() == ""

            with subtest("the writer refuses malformed requests"):
                for user in readers:
                    for target in ["-- -x", shlex.quote("ext::sh -c id"), "file:///etc", "github.com/../../etc"]:
                        machine.fail(as_user(user, f"ghq get {target}"))
                    machine.fail(as_user(user, "ghq create x"))
                machine.succeed("test ! -e /var/lib/ghq/etc")

            with subtest("safe.directory admits only the shared root"):
                machine.fail(as_user("cameron", "git -C /srv/git/fixture/hello.git log -1"))

            with subtest("an outsider can neither read the tree nor reach the writer"):
                machine.fail(as_user("outsider", f"ls {R}"))
                out = machine.fail(as_user("outsider", f"{client} get github.com/a/b 2>&1"))
                assert "cannot reach" in out, out

            with subtest("a writer-planted fsmonitor runs as the reader (the threat)"):
                machine.succeed(as_writer(f"git -C {P} config core.fsmonitor 'touch /tmp/fsmonitor-ran'"))
                machine.succeed(as_user("cameron", f"git -C {P} status"))
                assert machine.succeed("stat -c %U /tmp/fsmonitor-ran").strip() == "cameron"
                machine.succeed(as_writer(f"git -C {P} config --unset core.fsmonitor"))

            migrate = "${nodePkgs.ghq-shared}/bin/ghq-shared-migrate"
            M = f"{R}/localhost/fixture/mig"
            H = f"{R}/localhost/fixture/hello"

            with subtest("migration moves trees in, sanitises them, and rolls back"):
                # The primary account's tree is renamed whole only into an empty root.
                machine.succeed(as_writer(f"rm -rf {R}/localhost"))
                machine.succeed(
                    "git init -q --bare -b main /srv/git/fixture/mig.git"
                    " && git -C /srv/git/fixture/mig.git config uploadpack.allowFilter true"
                    " && git init -q -b main /tmp/mig && echo one > /tmp/mig/f"
                    " && git -C /tmp/mig add f && git -C /tmp/mig -c user.name=t -c user.email=t@t commit -q -m one"
                    " && echo two >> /tmp/mig/f && git -C /tmp/mig -c user.name=t -c user.email=t@t commit -q -am two"
                    " && git -C /tmp/mig push -q /srv/git/fixture/mig.git main"
                    " && chown -R git:git /srv/git"
                )
                # cameron: a full clone carrying planted configuration, a hook,
                # an uncommitted change and a local-only commit.
                machine.succeed(as_user("cameron",
                    "rm ~/ghq && git clone -q git://localhost/fixture/mig ~/ghq/localhost/fixture/mig"
                    " && cd ~/ghq/localhost/fixture/mig"
                    " && git config core.fsmonitor 'touch /tmp/planted-fsmonitor'"
                    " && git config core.hooksPath .git/hooks"
                    " && printf '#!/bin/sh\\ntouch /tmp/planted-hook\\n' > .git/hooks/post-checkout"
                    " && chmod +x .git/hooks/post-checkout"
                    " && git -c user.name=c -c user.email=c@c commit -q --allow-empty -m local-only"
                    " && echo dirty >> f"))
                # omnigent-cameron: its home on another filesystem, a shallow copy of
                # the same repository (the shallower loses) and one of its own.
                uid = machine.succeed("id -u omnigent-cameron").strip()
                # The tmpfs hides the account's Home Manager files; its git configuration,
                # which carries safe.directory, is linked back in.
                gitconfig = machine.succeed("readlink /home/omnigent-cameron/.config/git/config").strip()
                machine.succeed(f"mount -t tmpfs -o mode=0700,uid={uid},gid={uid} tmpfs /home/omnigent-cameron")
                machine.succeed(as_user("omnigent-cameron", f"mkdir -p ~/.config/git && ln -s {gitconfig} ~/.config/git/config"))
                machine.succeed(as_user("omnigent-cameron",
                    "git clone -q --depth 1 git://localhost/fixture/mig ~/ghq/localhost/fixture/mig"
                    " && git clone -q --depth 1 git://localhost/fixture/hello ~/ghq/localhost/fixture/hello"))
                before = machine.succeed("find /home/cameron/ghq /home/omnigent-cameron/ghq \\( -type f -printf '%p %u %m %s\\n' \\) -o -printf '%p %u %m\\n' | sort")

                plan = machine.succeed(f"{migrate} cameron omnigent-cameron")
                for expected in ["rename whole tree", "copy per repository", "uncommitted changes",
                                 "commits on no remote", "kept aside; cameron holds the deeper clone", "dry run"]:
                    assert expected in plan, (expected, plan)
                after = machine.succeed("find /home/cameron/ghq /home/omnigent-cameron/ghq \\( -type f -printf '%p %u %m %s\\n' \\) -o -printf '%p %u %m\\n' | sort")
                assert before == after, "the dry run changed a tree"

                machine.succeed(f"{migrate} --apply cameron omnigent-cameron")
                # Inspection runs git as each account itself, so a planted program may
                # run as its own account; it must never run as root or as the writer.
                assert machine.succeed("stat -c %U /tmp/planted-fsmonitor 2>/dev/null || echo cameron").strip() == "cameron"
                machine.succeed("rm -f /tmp/planted-fsmonitor")
                assert machine.succeed(f"stat -c '%U %a' {R}").strip() == "ghq 750"
                assert machine.succeed(f"find {R} ! -user ghq | wc -l").strip() == "0"
                assert machine.succeed(f"find {R} -perm -g+w ! -type l | wc -l").strip() == "0"
                machine.fail(as_writer(f"git -C {M} config --get core.fsmonitor"))
                machine.fail(as_writer(f"git -C {M} config --get core.hooksPath"))
                machine.succeed(f"test ! -e {M}/.git/hooks/post-checkout")
                kept = "/var/lib/ghq-migration/cameron/repos/localhost/fixture/mig/git"
                machine.succeed(f"grep -q planted-fsmonitor {kept}/config && test -x {kept}/hooks/post-checkout")
                assert machine.succeed("stat -c '%U %a' /var/lib/ghq-migration").strip() == "root 700"
                assert "f" in machine.succeed(as_writer(f"git --no-optional-locks -C {M} status --porcelain"))
                assert machine.succeed(as_writer(f"git -C {M} log -1 --format=%s")).strip() == "local-only"
                assert machine.succeed(as_writer(f"git -C {H} rev-parse --is-shallow-repository")).strip() == "true"
                machine.succeed("test -d /home/omnigent-cameron/ghq.pre-shared-*/localhost/fixture/mig")
                machine.succeed("test -d /home/omnigent-cameron/ghq.pre-shared-*/localhost/fixture/hello")
                for user in readers:
                    assert machine.succeed(as_user(user, "readlink ~/ghq")).strip() == R
                    machine.succeed(as_user(user, f"git -C {M} log -1 && git --no-optional-locks -C {M} status"))
                    machine.fail(as_user(user, f"touch {M}/probe"))
                machine.succeed("test ! -e /tmp/planted-fsmonitor && test ! -e /tmp/planted-hook")

                machine.fail(f"{migrate} --rollback cameron")
                machine.succeed(f"{migrate} --rollback cameron omnigent-cameron")
                restored = machine.succeed("find /home/cameron/ghq /home/omnigent-cameron/ghq \\( -type f -printf '%p %u %m %s\\n' \\) -o -printf '%p %u %m\\n' | sort")
                assert restored == before, "rollback did not restore the trees exactly"
                assert machine.succeed(f"stat -c '%U %a' {R}").strip() == "ghq 750"
                assert machine.succeed(f"ls -A {R} | wc -l").strip() == "0"

                machine.succeed("umount /home/omnigent-cameron")
                machine.succeed(as_user("cameron", f"rm -rf ~/ghq && ln -s {R} ~/ghq"))
                machine.succeed("rm -f /tmp/planted-fsmonitor /tmp/planted-hook")
          '';
        };
    in
    {
      vmTests = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        shared-reference-tree = mkTest { } // {
          mutations = {
            group-writable = mkTest {
              name = "shared-reference-tree-group-writable";
              prelude = ''
                machine.succeed(
                    "mkdir -p /run/systemd/system/ghq-writer@.service.d"
                    " && printf '[Service]\\nUMask=0007\\n' > /run/systemd/system/ghq-writer@.service.d/umask.conf"
                    " && systemctl daemon-reload && chmod 2770 /var/lib/ghq"
                )
              '';
            };
            broken-control = mkTest {
              name = "shared-reference-tree-broken-control";
              control = "false";
            };
          };
        };
      };
    };
}

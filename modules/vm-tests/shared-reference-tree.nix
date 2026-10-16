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

# Runtime behaviour of the shared ghq reference tree (openspec change
# share-ghq-reference-tree, design D8), on a KVM-capable x86_64-linux builder.
#
# Establishes, for a human reader and a worker reader on one node: delegated
# acquisition through the socket-activated writer, read-only git use, refusal of
# every reader write and of malformed requests, safe.directory scoped to the
# shared root, and that an outsider can neither list the tree nor reach the
# writer. A writer-planted core.fsmonitor is shown to run as the reader, so the
# assertions that readers cannot plant one are not vacuous; the writer's own
# write is the control that the write probe can observe success. Migration moves
# an administrator's tree in place unless an entry carries an ACL (setuid
# dropped, rollback exact, including
# records in the earlier tool's format and a rollback resumed after a failure),
# refuses a non-administrator's, and sets that one aside for reacquisition
# through the writer.
#
# The `mutations` attributes rerun the same script after breaking the permission
# model or the control; each must fail.
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
              cameron = {
                isNormalUser = true;
                extraGroups = [ "wheel" ];
              };
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
            environment.systemPackages = [
              nodePkgs.git
              nodePkgs.acl
              nodePkgs.e2fsprogs
            ];
          };
          testScript = ''
            import json
            import re
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
                    assert machine.succeed(as_user(user, "git config --get safe.bareRepository")).strip() == "explicit"

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

            with subtest("tags: full clones on update, shallow clones only with --tags, depth kept"):
                machine.succeed(
                    "git init -q --bare -b main /srv/git/fixture/tagged.git"
                    " && git -C /srv/git/fixture/tagged.git config uploadpack.allowFilter true"
                    " && git init -q -b main /tmp/tagged"
                    " && for i in 1 2 3 4 5 6 7 8; do git -C /tmp/tagged -c user.name=t -c user.email=t@t commit -q --allow-empty -m m$i; done"
                    " && git -C /tmp/tagged tag v-in HEAD~1"
                    " && git -C /tmp/tagged checkout -q -b side HEAD~5"
                    " && git -C /tmp/tagged -c user.name=t -c user.email=t@t commit -q --allow-empty -m s1"
                    " && git -C /tmp/tagged -c user.name=t -c user.email=t@t tag -a -m annotated a-side"
                    " && git -C /tmp/tagged push -q /srv/git/fixture/tagged.git main side --tags"
                    " && chown -R git:git /srv/git"
                )
                T = f"{R}/localhost/fixture/tagged"
                TURL = "git://localhost/fixture/tagged"
                machine.succeed(as_user("cameron", f"ghq-sync {TURL} && ghq-sync --deepen 3 {T}"))
                depth = machine.succeed(as_writer(f"git -C {T} rev-list --count HEAD")).strip()
                assert depth == "4", depth
                machine.succeed(as_user("omnigent-cameron", f"ghq get -u {TURL}"))
                assert "a-side" not in machine.succeed(as_writer(f"git -C {T} tag")).split()
                machine.succeed(as_user("omnigent-cameron", f"ghq-sync -u --tags {TURL}"))
                assert {"v-in", "a-side"} <= set(machine.succeed(as_writer(f"git -C {T} tag")).split())
                assert machine.succeed(as_writer(f"git -C {T} rev-list --count HEAD")).strip() == depth
                assert machine.succeed(as_writer(f"GIT_NO_LAZY_FETCH=1 git -C {T} rev-list --count a-side")).strip() == "1"
                # The promoted full clone of hello gains a new off-branch tag on plain update.
                machine.succeed(
                    "git -C /tmp/src checkout -q -b side HEAD~1"
                    " && git -C /tmp/src -c user.name=t -c user.email=t@t commit -q --allow-empty -m side"
                    " && git -C /tmp/src tag t-side"
                    " && chown -R root:root /srv/git/fixture/hello.git"
                    " && git -C /tmp/src push -q /srv/git/fixture/hello.git t-side"
                    " && chown -R git:git /srv/git"
                )
                machine.succeed(as_user("cameron", f"ghq get -u {URL}"))
                assert "t-side" in machine.succeed(as_writer(f"git -C {P} tag")).split()

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
                    # The wrapper stops some of these itself; the client sends each
                    # straight to the writer, which must refuse it.
                    for target in ["-x", shlex.quote("ext::sh -c id"), "file:///etc", "github.com/../../etc"]:
                        out = machine.fail(as_user(user, f"{client} get {target} 2>&1"))
                        assert "refused" in out, (target, out)
                    out = machine.fail(as_user(user, "ghq create x 2>&1"))
                    assert "unavailable" in out, out
                machine.succeed("test ! -e /var/lib/ghq/etc")

            with subtest("safe.directory admits only the shared root"):
                # A root-owned working tree outside the root: discovery refuses it for
                # ownership alone, not for being bare.
                out = machine.fail(as_user("cameron", "git -C /tmp/src log -1 2>&1"))
                assert "dubious ownership" in out, out

            with subtest("readers' git does not discover a bare repository in the tree"):
                machine.succeed(as_writer(f"git init -q --bare {R}/localhost/fixture/embedded.git"))
                for user in readers:
                    out = machine.fail(as_user(user, f"git -C {R}/localhost/fixture/embedded.git rev-parse --git-dir 2>&1"))
                    assert "bare repository" in out, out
                    machine.succeed(as_user(user, f"git --git-dir={R}/localhost/fixture/embedded.git rev-parse --git-dir"))
                machine.succeed(as_writer(f"rm -rf {R}/localhost/fixture/embedded.git"))

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
            S = "/var/lib/ghq-migration"
            M = f"{R}/localhost/fixture/mig"
            H = f"{R}/localhost/fixture/hello"
            # Each migration case is checked and reported on its own, so one run
            # shows every case that fails rather than only the first.
            problems = []

            def expect(ok, what):
                if not ok:
                    problems.append(what)

            with subtest("migration moves only an administrator's tree in place, sets other trees aside, and rolls back"):
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
                listing = ("find /home/cameron/ghq /home/omnigent-cameron/ghq"
                           " \\( -type f -printf '%p %u %m %s\\n' \\) -o -printf '%p %u %m\\n' | sort")
                date = machine.succeed("date +%Y%m%d").strip()

                # cameron, an administrator (wheel): a full clone with a hook, an
                # uncommitted change, a local-only commit and a setuid file.
                machine.succeed(as_user("cameron",
                    "rm ~/ghq && git clone -q git://localhost/fixture/mig ~/ghq/localhost/fixture/mig"
                    " && cd ~/ghq/localhost/fixture/mig"
                    " && printf '#!/bin/sh\\nexit 0\\n' > .git/hooks/post-checkout && chmod +x .git/hooks/post-checkout"
                    " && git -c user.name=c -c user.email=c@c commit -q --allow-empty -m local-only"
                    " && touch setuid && chmod 4755 setuid"
                    " && echo dirty >> f"))
                # omnigent-cameron, not an administrator, its home on another
                # filesystem: shallow clones of mig and hello.
                uid = machine.succeed("id -u omnigent-cameron").strip()
                # The tmpfs hides the account's Home Manager files; its git configuration,
                # which carries safe.directory, is linked back in.
                gitconfig = machine.succeed("readlink /home/omnigent-cameron/.config/git/config").strip()
                machine.succeed(f"mount -t tmpfs -o mode=0700,uid={uid},gid={uid} tmpfs /home/omnigent-cameron")
                machine.succeed(as_user("omnigent-cameron", f"mkdir -p ~/.config/git && ln -s {gitconfig} ~/.config/git/config"))
                machine.succeed(as_user("omnigent-cameron",
                    "git clone -q --depth 1 git://localhost/fixture/mig ~/ghq/localhost/fixture/mig"
                    " && git clone -q --depth 1 git://localhost/fixture/hello ~/ghq/localhost/fixture/hello"
                    " && git -C ~/ghq/localhost/fixture/hello remote set-url origin git://user:secret@localhost/fixture/hello"))
                before = machine.succeed(listing)

                plan = machine.succeed(f"{migrate} cameron omnigent-cameron 2>&1")
                for expected in ["plan cameron: inspected 1/1 repositories", "rename whole tree", "uncommitted changes",
                                 "commits on no remote",
                                 "omnigent-cameron: refused: not an administrator (wheel) of this host",
                                 "ghq-sync git://localhost/fixture/mig", "ghq-sync git://localhost/fixture/hello",
                                 "dry run"]:
                    expect(expected in plan, ("the plan does not report", expected, plan))
                expect(machine.succeed(listing) == before, "the dry run changed a tree")

                # A non-administrator's tree is never moved in place, and nothing else moves either.
                status, out = machine.execute(f"{migrate} --apply cameron omnigent-cameron 2>&1")
                expect(status != 0 and "omnigent-cameron not an administrator (wheel)" in out and "nothing changed" in out,
                       ("apply moved a non-administrator's tree in place", out))
                expect(machine.succeed(listing) == before and machine.succeed(f"ls -A {R} | wc -l").strip() == "0"
                       and machine.execute(f"test -e {S}/cameron")[0] != 0,
                       "a refused apply changed a tree, the root or the state directory")
                if status == 0:
                    machine.execute(f"{migrate} --rollback cameron omnigent-cameron")

                # A manifest from an apply not rolled back: a second one would share its sidecar.
                machine.succeed(f"mkdir -p {S}/cameron && chmod 0700 {S} {S}/cameron && echo '{{}}' > {S}/cameron/manifest.jsonl")
                status, out = machine.execute(f"{migrate} --apply cameron 2>&1")
                expect(status != 0 and "already migrated and not rolled back" in out,
                       ("apply ran beside a manifest not rolled back", out))
                expect(machine.succeed(listing) == before, "apply refused for a standing manifest changed a tree")
                machine.succeed(f"rm -rf {S}/cameron")

                # An ACL in an administrator's tree granting another account write would
                # let that account write the shared tree; the plan lists it and apply refuses.
                machine.succeed(as_user("cameron", "setfacl -m u:omnigent-cameron:rwx ~/ghq/localhost/fixture/mig/.git"))
                with_acl = machine.succeed(listing)
                plan = machine.succeed(f"{migrate} cameron 2>&1")
                expect("refused: /home/cameron/ghq/localhost/fixture/mig/.git: carries an ACL" in plan,
                       ("the plan does not list an entry carrying an ACL", plan))
                status, out = machine.execute(f"{migrate} --apply cameron 2>&1")
                expect(status != 0 and "could have written" in out and "nothing changed" in out,
                       ("apply moved a tree carrying an ACL", out))
                expect(machine.succeed(listing) == with_acl and machine.succeed(f"ls -A {R} | wc -l").strip() == "0"
                       and machine.execute(f"test -e {S}/cameron")[0] != 0,
                       "apply refused for an ACL changed a tree, the root or the state directory")
                if status == 0:
                    machine.execute(f"{migrate} --rollback cameron omnigent-cameron")
                machine.succeed(as_user("cameron", "setfacl -b ~/ghq/localhost/fixture/mig/.git"))

                # Other ways another account could have written the tree: an entry every
                # account can write, an entry another account owns, and a hard link to a
                # file outside the tree.
                machine.succeed(as_user("cameron",
                    "cd ~/ghq/localhost/fixture/mig && touch world-writable && chmod 0666 world-writable"
                    " && echo outside > ~/outside && ln ~/outside linked-out"))
                machine.succeed("install -o omnigent-cameron -m 0644 /dev/null /home/cameron/ghq/localhost/fixture/mig/foreign")
                exposed = machine.succeed(listing)
                plan = machine.succeed(f"{migrate} cameron 2>&1")
                W = "/home/cameron/ghq/localhost/fixture/mig"
                for expected in [f"refused: {W}/world-writable: writable by every account",
                                 f"refused: {W}/foreign: owned by uid {uid}",
                                 f"refused: {W}/linked-out: hard link with 1 link(s) outside the tree"]:
                    expect(expected in plan, ("the plan does not list", expected, plan))
                status, out = machine.execute(f"{migrate} --apply cameron 2>&1")
                expect(status != 0 and "could have written" in out and "nothing changed" in out,
                       ("apply moved a tree another account could have written", out))
                expect(machine.succeed(listing) == exposed and machine.succeed(f"ls -A {R} | wc -l").strip() == "0"
                       and machine.execute(f"test -e {S}/cameron")[0] != 0,
                       "apply refused for an exposed tree changed a tree, the root or the state directory")
                if status == 0:
                    machine.execute(f"{migrate} --rollback cameron omnigent-cameron")
                machine.succeed(f"rm -f {W}/world-writable {W}/linked-out {W}/foreign /home/cameron/outside")
                expect(machine.succeed(listing) == before, "removing the exposed entries did not restore the tree")

                # While the tree moves, the writer is stopped and the root reachable by no
                # account but root; a hook run at that point records both.
                machine.succeed(
                    "printf '#!/bin/sh\\n"
                    "systemctl is-active ghq-writer.socket >> /tmp/hook-probe\\n"
                    "stat -c \\\"%%a\\\" /var/lib/ghq >> /tmp/hook-probe\\n"
                    "su -s /bin/sh nobody -c \\\"ls /var/lib/ghq\\\" >/dev/null 2>&1 && echo nobody-read >> /tmp/hook-probe\\n"
                    "true\\n' > /tmp/hook && chmod 0755 /tmp/hook && rm -f /tmp/hook-probe")

                applied = machine.succeed(f"GHQ_SHARED_MIGRATE_HOOK=/tmp/hook {migrate} --apply cameron 2>&1")
                probe = machine.execute("cat /tmp/hook-probe")[1].split()
                expect(probe == ["inactive", "700"], ("during apply the writer ran or the root was reachable", probe))
                expect(machine.succeed("systemctl is-active ghq-writer.socket").strip() == "active",
                       "the writer did not come back after apply")
                for expected in ["rename cameron: done in", "ownership cameron: done in", "link cameron: done in",
                                 "cameron: moved 1 repositories"]:
                    expect(expected in applied, ("apply did not report", expected, applied))
                expect(machine.succeed(f"find {R} -perm /7000 | wc -l").strip() == "0", "a setuid, setgid or sticky bit survived migration")
                expect(machine.succeed(f"stat -c '%U %a' {R}").strip() == "ghq 750", "the root is not ghq 750")
                expect(machine.succeed(f"find {R} ! -user ghq | wc -l").strip() == "0", "an entry is not owned by the writer")
                expect(machine.succeed(f"find {R} -perm -g+w ! -type l | wc -l").strip() == "0", "an entry is group-writable")
                expect(machine.succeed(f"find {R} -perm /o=rwx ! -type l | wc -l").strip() == "0", "an entry grants others access")
                expect(machine.succeed(f"stat -c '%U %a' {S}").strip() == "root 700", "the state directory is not root 700")
                expect(machine.execute(f"test -x {M}/.git/hooks/post-checkout")[0] == 0, "an administrator's tree was changed beyond ownership and modes")
                assert "f" in machine.succeed(as_writer(f"git --no-optional-locks -C {M} status --porcelain"))
                assert machine.succeed(as_writer(f"git -C {M} log -1 --format=%s")).strip() == "local-only"

                # The non-administrator's tree is set aside, still its own, and its
                # repositories are recloned through the writer by the printed commands.
                status, out = machine.execute(f"{migrate} --set-aside omnigent-cameron 2>&1")
                assert status == 0, problems + [("set-aside failed", out)]
                aside = f"/home/omnigent-cameron/ghq.pre-shared-{date}"
                commands = re.findall(r"^  (ghq-sync .*)$", out, re.M)
                expect(sorted(commands) == ["ghq-sync git://localhost/fixture/hello", "ghq-sync git://localhost/fixture/mig"],
                       ("set-aside did not list each repository's reclone command", out))
                expect("secret" not in out, ("set-aside printed a credential from an upstream URL", out))
                expect(machine.succeed(f"stat -c %U {aside}/localhost/fixture/mig/.git/HEAD").strip() == "omnigent-cameron",
                       "the set-aside tree is not the account's own")
                expect(machine.succeed(as_user("omnigent-cameron", "readlink ~/ghq")).strip() == R, "set-aside did not link ~/ghq")
                for command in commands:
                    status, out = machine.execute(as_user("omnigent-cameron", command) + " 2>&1")
                    expect(status == 0, ("a printed reclone command failed", command, out))
                expect(machine.execute(f"stat -c %U {H}/.git/HEAD")[1].strip() == "ghq", "the writer did not reclone hello")
                for user in readers:
                    assert machine.succeed(as_user(user, "readlink ~/ghq")).strip() == R
                    machine.succeed(as_user(user, f"git -C {M} log -1 && git --no-optional-locks -C {M} status"))
                    machine.fail(as_user(user, f"touch {M}/probe"))

                # The writer clones into the primary account's renamed tree; rollback
                # must hand that clone to the account along with the tree.
                machine.succeed(as_user("omnigent-cameron", "ghq get -u git://localhost/fixture/tagged"))
                assert machine.succeed(f"stat -c %U {R}/localhost/fixture/tagged/.git/HEAD").strip() == "ghq"

                # Records of the earlier tool keep rolling back: they also held each
                # rewritten configuration and removed hook as a "sanitise" step.
                K = f"{S}/cameron/repos/localhost/fixture/mig/git"
                legacy = [{"op": "sanitise", "path": f"{M}/.git/config", "kept": f"{K}/./config"},
                          {"op": "sanitise", "path": f"{M}/.git/hooks/post-checkout", "kept": f"{K}/hooks/post-checkout"}]
                machine.succeed(f"mkdir -p {K}/hooks && cp -p {M}/.git/config {K}/config"
                                f" && cp -p {M}/.git/hooks/post-checkout {K}/hooks/post-checkout"
                                f" && git config --file {M}/.git/config core.legacyprobe true && rm {M}/.git/hooks/post-checkout")
                for step in legacy:
                    machine.succeed(f"sed -i {shlex.quote('/\"op\": \"symlink\"/i ' + json.dumps(step))} {S}/cameron/manifest.jsonl")

                expect(machine.execute(f"{migrate} --rollback cameron")[0] != 0, "cameron rolled back before omnigent-cameron")
                # A rollback that fails part way can be run again: an immutable file
                # stops the ownership restore after omnigent-cameron's set-aside is undone.
                machine.succeed(f"chattr +i {M}/f")
                status, out = machine.execute(f"{migrate} --rollback cameron omnigent-cameron 2>&1")
                machine.succeed(f"chattr -i {M}/f")
                expect(status != 0, ("rollback did not fail on the immutable file, so resumption is untested", out))
                status, rolled = machine.execute(f"{migrate} --rollback cameron 2>&1")
                assert status == 0, problems + [("resuming the rollback failed", rolled)]
                expect("cameron: rolled back" in rolled, ("the resumed rollback did not finish", rolled))
                restored = machine.succeed(listing).splitlines()
                recorded = {line.split(" ")[0] for line in before.splitlines()}
                kept_lines = [line for line in restored if line.split(" ")[0] in recorded]
                expect(kept_lines == before.splitlines(), ("rollback did not restore the trees exactly",
                                                           sorted(set(kept_lines) ^ set(before.splitlines()))))
                expect(machine.execute("git config --file /home/cameron/ghq/localhost/fixture/mig/.git/config --get core.legacyprobe")[0] == 1,
                       "rollback did not restore configuration kept by a legacy sanitise step")
                expect(machine.execute("test -x /home/cameron/ghq/localhost/fixture/mig/.git/hooks/post-checkout")[0] == 0,
                       "rollback did not restore a hook kept by a legacy sanitise step")
                expect(machine.succeed("find /home/cameron/ghq /home/omnigent-cameron/ghq -user ghq | wc -l").strip() == "0",
                       "rollback left writer-owned entries in a restored tree")
                expect(machine.succeed("stat -c %U /home/cameron/ghq/localhost/fixture/tagged/.git/HEAD").strip() == "cameron",
                       "rollback did not give the writer's clone to the account")
                expect(machine.execute("test -d /home/omnigent-cameron/ghq && test ! -L /home/omnigent-cameron/ghq")[0] == 0,
                       "rollback did not put back the set-aside tree")
                assert machine.succeed(f"stat -c '%U %a' {R}").strip() == "ghq 750"

                machine.succeed("umount /home/omnigent-cameron")
                machine.succeed("rm -rf /home/cameron/ghq")
                machine.succeed(as_user("cameron", f"ln -s {R} ~/ghq"))

            with subtest("every migration case held"):
                assert not problems, "\n".join(map(repr, problems))
          '';
        };
    in
    {
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
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

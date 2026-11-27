# Runtime behaviour of the shared ghq reference tree (openspec change
# share-ghq-reference-tree, design D8), on a KVM-capable x86_64-linux builder.
# One node definition, two tests, each booting its own VM, so that each test's
# script stays well under its class limit.
#
# shared-reference-tree establishes, for a human reader and a worker reader:
# delegated acquisition through the socket-activated writer and its lock per
# repository, read-only git use, LFS pointer files and an update following a
# renamed default branch, refusal of every reader write and of malformed
# requests, safe.directory scoped to the shared root, and that an outsider can
# neither list the tree nor reach the writer. A writer-planted core.fsmonitor is
# shown to run as the reader, so the assertions that readers cannot plant one
# are not vacuous; the writer's own write is the control that the write probe
# can observe success.
#
# shared-reference-tree-migration establishes the tag fetches of updates, whose
# fixture its migration case reuses, and migration: an administrator's tree
# moves in place unless an entry carries an ACL (setuid dropped, rollback exact,
# including records in the earlier tool's format and a rollback resumed after a
# failure), a non-administrator's is refused and set aside for reacquisition
# through the writer.
#
# The `mutations` attributes of shared-reference-tree rerun its script after
# breaking the permission model or the control; each must fail.
{ self, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      fleetPkgs,
      ...
    }:
    let
      nodePkgs = fleetPkgs;
      readers = [
        "cameron"
        "omnigent-cameron"
      ];
      mkTest =
        {
          name,
          cases,
          prelude ? "",
          passthru ? { },
        }:
        pkgs.testers.runNixOSTest {
          inherit name passthru;
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

            ${cases}
          '';
        };
      accessCases =
        {
          control ? "touch",
        }:
        ''
          import hashlib

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

          with subtest("a request takes its repository's lock in the writer's lock directory, and a second one waits"):
              assert machine.succeed("stat -c '%U %G %a' /var/lib/ghq-writer").strip() == "ghq ghq 700"
              lock = "/var/lib/ghq-writer/" + hashlib.sha256(b"localhost/fixture/hello").hexdigest() + ".lock"
              assert machine.succeed(f"stat -c '%U %a' {lock}").strip() == "ghq 600"
              # Root holds the lock in place of a first, slow request: taken before the
              # request starts, released once its handler has logged that it waits (or
              # after 10 s, failing the assertion), so the wait is certain and no longer
              # than it takes.
              out = machine.succeed(
                  f"(flock -x {lock} -c 'touch /tmp/lock-held; for i in $(seq 100); do"
                  " journalctl -b -o cat | grep -q \"waiting held-by\" && break; sleep 0.1; done'"
                  " >/dev/null 2>&1 &) && until [ -e /tmp/lock-held ]; do sleep 0.05; done && "
                  + as_user("cameron", f"ghq get -u {URL} 2>&1")
              )
              assert "ghq-writer: waiting up to 3600 s for localhost/fixture/hello," in out, out

          with subtest("every reader reads it with git"):
              for user in readers:
                  assert machine.succeed(as_user(user, "ghq list -p fixture/hello")).strip() == P
                  machine.succeed(as_user(user, f"git -C {P} log -1 --oneline"))
                  machine.succeed(as_user(user, f"git -C {P} status"))
                  # Under the root the reader's git runs no LFS filter, as the writer's does.
                  assert machine.succeed(as_user(user, f"git -C {P} config --get filter.lfs.required")).strip() == "false"

          with subtest("deepen, promote and update go through the writer"):
              machine.succeed(as_user("omnigent-cameron", f"ghq-sync --deepen 1 {P} | grep -Fx 'deepened: {P}'"))
              assert machine.succeed(as_writer(f"git -C {P} rev-list --count HEAD")).strip() == "2"
              machine.succeed(as_user("omnigent-cameron", f"ghq-sync --full {P} | grep -Fx 'promoted to full: {P}'"))
              assert machine.succeed(as_writer(f"git -C {P} rev-parse --is-shallow-repository")).strip() == "false"
              machine.succeed(as_user("omnigent-cameron", f"ghq get -u {URL}"))
              assert machine.succeed(f"find {R} ! -user ghq | wc -l").strip() == "0"

          with subtest("hydrate makes a revision's blobs present for readers"):
              # A tag on a branch never merged, fetched at depth 1 by --tags: no update or
              # deepen brings in its history, so its blob stays absent until hydrated.
              machine.succeed(
                  "git init -q --bare -b main /srv/git/fixture/blobs.git"
                  " && git -C /srv/git/fixture/blobs.git config uploadpack.allowFilter true"
                  " && git init -q -b main /tmp/blobs"
                  " && for i in 1 2 3; do echo v$i > /tmp/blobs/f && git -C /tmp/blobs add f"
                  " && git -C /tmp/blobs -c user.name=t -c user.email=t@t commit -q -m v$i; done"
                  " && git -C /tmp/blobs checkout -q -b unmerged HEAD~2 && echo unmerged > /tmp/blobs/f"
                  " && git -C /tmp/blobs -c user.name=t -c user.email=t@t commit -q -am unmerged"
                  " && git -C /tmp/blobs tag t-unmerged"
                  " && git -C /tmp/blobs push -q /srv/git/fixture/blobs.git main t-unmerged"
                  " && chown -R git:git /srv/git"
              )
              B = f"{R}/localhost/fixture/blobs"
              machine.succeed(as_user("cameron", "ghq-sync git://localhost/fixture/blobs && ghq-sync -u --tags git://localhost/fixture/blobs"))
              machine.succeed(as_user("omnigent-cameron", f"GIT_NO_LAZY_FETCH=1 git -C {B} rev-parse -q --verify 't-unmerged^{{commit}}'"))
              machine.fail(as_user("omnigent-cameron", f"GIT_NO_LAZY_FETCH=1 git -C {B} show t-unmerged:f"))
              out = machine.succeed(as_user("omnigent-cameron", f"ghq-sync --hydrate t-unmerged {B}"))
              assert out.startswith(f"hydrated: {B} "), out
              assert machine.succeed(as_user("omnigent-cameron", f"GIT_NO_LAZY_FETCH=1 git -C {B} show t-unmerged:f")).strip() == "unmerged"
              out = machine.fail(as_user("omnigent-cameron", f"{client} hydrate HEAD..main {B} 2>&1"))
              assert "refused" in out, out
              assert machine.succeed(f"find {R} ! -user ghq | wc -l").strip() == "0"

          with subtest("LFS paths hold pointer files, updates pass, and readers' git-lfs never runs in the tree"):
              machine.succeed(
                  "git init -q --bare -b main /srv/git/fixture/lfs.git"
                  " && git -C /srv/git/fixture/lfs.git config uploadpack.allowFilter true"
                  " && git init -q -b main /tmp/lfs"
                  " && printf '*.bin filter=lfs diff=lfs merge=lfs -text\\n' > /tmp/lfs/.gitattributes"
                  " && for v in one two; do printf 'version https://git-lfs.github.com/spec/v1\\noid sha256:%s\\nsize 4\\n'"
                  " $(echo $v | sha256sum | cut -d ' ' -f 1) > /tmp/lfs-pointer-$v; done"
                  " && cp /tmp/lfs-pointer-one /tmp/lfs/a.bin"
                  " && git -C /tmp/lfs add .gitattributes a.bin && git -C /tmp/lfs -c user.name=t -c user.email=t@t commit -q -m one"
                  " && git -C /tmp/lfs push -q /srv/git/fixture/lfs.git main"
                  " && chown -R git:git /srv/git"
                  # Configuration that runs git-lfs, as the readers' own git configuration does on the fleet's hosts;
                  # readers' commands below read it at system scope, beneath their global include.
                  " && printf '[filter \"lfs\"]\\n\\tprocess = ${nodePkgs.git-lfs}/bin/git-lfs filter-process\\n\\trequired = true\\n'"
                  " > /etc/gitconfig-lfs"
              )
              L = f"{R}/localhost/fixture/lfs"
              lfs = "GIT_CONFIG_SYSTEM=/etc/gitconfig-lfs"
              machine.succeed(as_user("cameron", "ghq-sync git://localhost/fixture/lfs"))
              machine.succeed(f"cmp {L}/a.bin /tmp/lfs-pointer-one")
              # An LFS cache the readers cannot write, as git-lfs leaves one in a tree it
              # used; a new mtime at the same size makes git read the file again, through an
              # LFS filter if one runs.
              machine.succeed(as_writer(f"mkdir -p {L}/.git/lfs/tmp && touch {L}/a.bin"))
              for user in readers:
                  out = machine.succeed(as_user(user, f"{lfs} git -C {L} status --porcelain 2>&1"))
                  assert out.strip() == "", (user, out)
              # Control: with git-lfs re-enabled above the include, as a required filter as the
              # fleet's git configuration sets it, the same read fails writing the LFS cache.
              out = machine.fail(as_user("cameron",
                  f"{lfs} git -c 'filter.lfs.process=${nodePkgs.git-lfs}/bin/git-lfs filter-process' -c filter.lfs.required=true"
                  f" -C {L} status --porcelain 2>&1"))
              assert "permission denied" in out.lower(), out
              assert machine.succeed(f"find {L}/.git/lfs -mindepth 2 | wc -l").strip() == "0", "a reader wrote into the LFS cache"
              machine.succeed(as_writer(f"rm -rf {L}/.git/lfs"))
              # The clone's own configuration requires git-lfs, which the writer does not have; an
              # update that changes the LFS path still fast-forwards to the new pointer file.
              machine.succeed(as_writer(f"git -C {L} config filter.lfs.process 'git-lfs filter-process'"
                                        f" && git -C {L} config filter.lfs.required true"))
              machine.succeed(
                  "cp /tmp/lfs-pointer-two /tmp/lfs/a.bin"
                  " && git -C /tmp/lfs -c user.name=t -c user.email=t@t commit -q -am two"
                  " && chown -R root:root /srv/git/fixture/lfs.git"
                  " && git -C /tmp/lfs push -q /srv/git/fixture/lfs.git main"
                  " && chown -R git:git /srv/git"
              )
              machine.succeed(as_user("omnigent-cameron", "ghq-sync -u git://localhost/fixture/lfs"))
              machine.succeed(f"cmp {L}/a.bin /tmp/lfs-pointer-two")
              machine.succeed(as_writer(f"git -C {L} config --unset filter.lfs.process && git -C {L} config --unset filter.lfs.required"))
              assert machine.succeed(as_writer(f"git -C {L} status --porcelain")).strip() == ""
              assert machine.succeed(f"find {R} ! -user ghq | wc -l").strip() == "0"

          with subtest("an update follows a default branch renamed upstream"):
              machine.succeed(
                  "git init -q --bare -b master /srv/git/fixture/renamed.git"
                  " && git -C /srv/git/fixture/renamed.git config uploadpack.allowFilter true"
                  " && git init -q -b master /tmp/renamed && echo one > /tmp/renamed/f"
                  " && git -C /tmp/renamed add f && git -C /tmp/renamed -c user.name=t -c user.email=t@t commit -q -m one"
                  " && git -C /tmp/renamed push -q /srv/git/fixture/renamed.git master"
                  " && chown -R git:git /srv/git"
              )
              N = f"{R}/localhost/fixture/renamed"
              machine.succeed(as_user("cameron", "ghq-sync git://localhost/fixture/renamed"))
              # Upstream renames master to main, so the clone's only branch is gone.
              machine.succeed(
                  "chown -R root:root /srv/git/fixture/renamed.git"
                  " && git -C /srv/git/fixture/renamed.git branch -m master main"
                  " && echo two > /tmp/renamed/f && git -C /tmp/renamed -c user.name=t -c user.email=t@t commit -q -am two"
                  " && git -C /tmp/renamed push -q /srv/git/fixture/renamed.git master:main"
                  " && chown -R git:git /srv/git"
              )
              out = machine.succeed(as_user("omnigent-cameron", "ghq-sync -u git://localhost/fixture/renamed 2>&1"))
              assert "default branch: master -> main; checked out main" in out, out
              assert machine.succeed(as_writer(f"git -C {N} symbolic-ref --short HEAD")).strip() == "main"
              assert machine.succeed(as_writer(f"git -C {N} rev-parse --is-shallow-repository")).strip() == "true"
              machine.succeed(f"cmp {N}/f /tmp/renamed/f")
              assert machine.succeed(f"find {R} ! -user ghq | wc -l").strip() == "0"

          with subtest("the writer's own write succeeds (control)"):
              machine.succeed(as_writer(f"${control} {P}/.control && rm -f {P}/.control"))

          with subtest("readers cannot write the tree"):
              for user in readers:
                  machine.fail(as_user(user, f"touch {P}/probe"))
                  machine.fail(as_user(user, f"mkdir {R}/probe"))
                  machine.fail(as_user(user, f"git -C {P} config core.fsmonitor /bin/false"))
                  # A reader's fetch opens FETCH_HEAD before it connects, so the operating
                  # system refuses it first; one that writes no FETCH_HEAD reaches the
                  # transport, which the reader's git refuses beneath the root.
                  out = machine.fail(as_user(user, f"git -C {P} fetch 2>&1"))
                  assert "permission denied" in out.lower(), out
                  out = machine.fail(as_user(user, f"git -C {P} fetch --no-write-fetch-head 2>&1"))
                  assert "not allowed" in out, out
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
        '';
      migrationCases = ''
        import json
        import re

        # The tags case updates hello as a full clone, which shared-reference-tree
        # reaches by deepening and promoting it.
        machine.succeed(as_user("cameron", f"ghq-sync {URL} && ghq-sync --full {P}"))

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

        with subtest("an update makes the commits it brought in readable, and a read the writer did not prepare fails at once"):
            import time
            machine.succeed(
                "git init -q --bare -b main /srv/git/fixture/history.git"
                " && git -C /srv/git/fixture/history.git config uploadpack.allowFilter true"
                " && git init -q -b main /tmp/history"
                " && for i in 1 2 3; do echo v$i > /tmp/history/f && echo g$i > /tmp/history/g"
                " && git -C /tmp/history add f g && git -C /tmp/history -c user.name=t -c user.email=t@t commit -q -m v$i; done"
                " && git -C /tmp/history push -q /srv/git/fixture/history.git main"
                " && chown -R git:git /srv/git"
            )
            Y = f"{R}/localhost/fixture/history"
            YURL = "git://localhost/fixture/history"
            machine.succeed(as_user("cameron", f"ghq-sync {YURL}"))
            old = machine.succeed(as_writer(f"git -C {Y} rev-parse HEAD")).strip()
            # Upstream gains a commit, a side branch merged with a resolved conflict, and
            # a tag on a branch never merged whose f differs from every branch commit's.
            machine.succeed(
                "cd /tmp/history && G='git -c user.name=t -c user.email=t@t'"
                " && echo v4 > f && $G commit -q -am v4"
                " && $G checkout -q -b side && echo side > g && $G commit -q -am side"
                " && $G checkout -q main && echo main > g && echo v5 > f && $G commit -q -am v5"
                " && { $G merge -q --no-ff -m merge side || true; } && echo resolved > g && $G commit -q -am merge"
                " && $G checkout -q -b unmerged HEAD~3 && echo unmerged > f && $G commit -q -am unmerged"
                " && $G tag t-unmerged && $G checkout -q main"
                " && chown -R root:root /srv/git/fixture/history.git"
                " && $G push -q /srv/git/fixture/history.git main t-unmerged"
                " && chown -R git:git /srv/git"
            )
            out = machine.succeed(as_user("omnigent-cameron", f"ghq get -u {YURL} 2>&1"))
            assert f"hydrated history: {Y} (" in out, out
            commits = machine.succeed(as_writer(f"git -C {Y} rev-list {old}..HEAD")).split()
            assert len(commits) == 4, commits
            for commit in commits:
                machine.succeed(as_user("cameron", f"git -C {Y} --no-lazy-fetch show --stat -p {commit} >/dev/null"))
            # The tag arrives at depth 1, and no hydrate fetches its blob.
            machine.succeed(as_user("omnigent-cameron", f"ghq-sync -u --tags {YURL}"))
            started = time.monotonic()
            status, out = machine.execute(as_user("cameron", f"git -C {Y} show t-unmerged 2>&1"))
            took = time.monotonic() - started
            assert status != 0 and "not allowed" in out and "could not fetch" in out, (status, out)
            assert "permission denied" not in out.lower() and took < 5, (took, out)
            # The same refusal stops every network read inside a copy.
            for command in ["ls-remote origin", "remote show origin"]:
                out = machine.fail(as_user("cameron", f"git -C {Y} {command} 2>&1"))
                assert "not allowed" in out, (command, out)
            # The writer's git reads none of the readers' configuration: its hydrate
            # through the socket still fetches, and the read then succeeds.
            out = machine.succeed(as_user("cameron", f"ghq-sync --hydrate t-unmerged {Y}"))
            assert out.startswith(f"hydrated: {Y} "), out
            machine.succeed(as_user("cameron", f"git -C {Y} show t-unmerged >/dev/null"))
            assert machine.succeed(f"find {R} ! -user ghq | wc -l").strip() == "0"

        with subtest("lazygit's start-up fetch is off beneath the shared root"):
            assert machine.succeed(f"stat -c '%U %G %a %F' {R}/.lazygit.yml").strip() == "ghq ghq 640 regular file"
            for user in readers:
                assert machine.succeed(as_user(user, f"cat {R}/.lazygit.yml")) == "git:\n  autoFetch: false\n"

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
                # An LFS-tracked path, committed as its pointer file.
                " && printf '*.bin filter=lfs diff=lfs merge=lfs -text\\n' > /tmp/mig/.gitattributes"
                " && echo real-lfs-content > /tmp/lfs-real"
                " && printf 'version https://git-lfs.github.com/spec/v1\\noid sha256:%s\\nsize %s\\n'"
                " $(sha256sum /tmp/lfs-real | cut -d ' ' -f 1) $(stat -c %s /tmp/lfs-real) > /tmp/mig/a.bin"
                " && git -C /tmp/mig add f .gitattributes a.bin && git -C /tmp/mig -c user.name=t -c user.email=t@t commit -q -m one"
                " && echo two >> /tmp/mig/f && git -C /tmp/mig -c user.name=t -c user.email=t@t commit -q -am two"
                " && git -C /tmp/mig push -q /srv/git/fixture/mig.git main"
                " && chown -R git:git /srv/git"
            )
            listing = ("find /home/cameron/ghq /home/omnigent-cameron/ghq"
                       " \\( -type f -printf '%p %u %m %s\\n' \\) -o -printf '%p %u %m\\n' | sort")
            date = machine.succeed("date +%Y%m%d").strip()
            # The root holds the provisioned .lazygit.yml, which migration keeps in place.
            outside_lazygit = f"ls -A {R} | grep -cvxF .lazygit.yml || true"
            lazygit_file = f"stat -c '%U %G %a' {R}/.lazygit.yml && cat {R}/.lazygit.yml"
            lazygit_kept = "ghq ghq 640\ngit:\n  autoFetch: false\n"

            # cameron, an administrator (wheel): a full clone with a hook, an
            # uncommitted change, a local-only commit, a setuid file, and an LFS
            # path holding the content its pointer names, as git-lfs leaves it.
            machine.succeed(as_user("cameron",
                "rm ~/ghq && git -c 'filter.lfs.smudge=cat >/dev/null; cat /tmp/lfs-real'"
                " clone -q git://localhost/fixture/mig ~/ghq/localhost/fixture/mig"
                " && cmp ~/ghq/localhost/fixture/mig/a.bin /tmp/lfs-real"
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
            expect(machine.succeed(listing) == before and machine.succeed(outside_lazygit).strip() == "0"
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
            expect(machine.succeed(listing) == with_acl and machine.succeed(outside_lazygit).strip() == "0"
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
            expect(machine.succeed(listing) == exposed and machine.succeed(outside_lazygit).strip() == "0"
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
                             "cameron: moved 1 repositories", "cameron: set 1 LFS paths back to their pointer files"]:
                expect(expected in applied, ("apply did not report", expected, applied))
            expect(machine.execute(f"cmp {M}/a.bin /tmp/mig/a.bin")[0] == 0,
                   "migration did not set the smudged LFS path back to its pointer file")
            expect(machine.succeed(f"find {R} -perm /7000 | wc -l").strip() == "0", "a setuid, setgid or sticky bit survived migration")
            expect(machine.succeed(f"stat -c '%U %a' {R}").strip() == "ghq 750", "the root is not ghq 750")
            expect(machine.succeed(f"find {R} ! -user ghq | wc -l").strip() == "0", "an entry is not owned by the writer")
            expect(machine.succeed(f"find {R} -perm -g+w ! -type l | wc -l").strip() == "0", "an entry is group-writable")
            expect(machine.succeed(f"find {R} -perm /o=rwx ! -type l | wc -l").strip() == "0", "an entry grants others access")
            expect(machine.succeed(f"stat -c '%U %a' {S}").strip() == "root 700", "the state directory is not root 700")
            expect(machine.succeed(lazygit_file) == lazygit_kept, "migration did not keep .lazygit.yml with its owner, mode and content")
            expect(machine.execute(f"test -x {M}/.git/hooks/post-checkout")[0] == 0, "an administrator's tree was changed beyond ownership and modes")
            migrated_status = machine.succeed(as_writer(f"git --no-optional-locks -C {M} status --porcelain"))
            assert "f" in migrated_status
            expect("a.bin" not in migrated_status, ("the writer sees the LFS path as changed after migration", migrated_status))
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
            expect(machine.succeed(lazygit_file) == lazygit_kept, "rollback did not keep .lazygit.yml with its owner, mode and content")

            machine.succeed("umount /home/omnigent-cameron")
            machine.succeed("rm -rf /home/cameron/ghq")
            machine.succeed(as_user("cameron", f"ln -s {R} ~/ghq"))

        with subtest("every migration case held"):
            assert not problems, "\n".join(map(repr, problems))
      '';
    in
    {
      # Size classes: before the split the one test's script measured 26 to
      # 51.76 s, 50.04 s on pyrite on 2026-11-26
      # (logs/ghq-writer-lock-vmtest-pyrite-20261126-171209.log), about 22 s of
      # it boot. After it, on pyrite on 2026-11-26, shared-reference-tree
      # measured 35.79, 37.36 and 36.58 s and shared-reference-tree-migration
      # 33.14, 35.10 and 32.86 s, 18 to 21 s of each boot
      # (logs/srt-split-<name>-pyrite-20261126-17*-run<n>.log).
      testSizes.vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        shared-reference-tree.class = "small";
        shared-reference-tree-migration.class = "small";
      };
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        shared-reference-tree = mkTest {
          name = "shared-reference-tree";
          cases = accessCases { };
          passthru.mutations = {
            group-writable = mkTest {
              name = "shared-reference-tree-group-writable";
              cases = accessCases { };
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
              cases = accessCases { control = "false"; };
            };
          };
        };
        shared-reference-tree-migration = mkTest {
          name = "shared-reference-tree-migration";
          cases = migrationCases;
        };
      };
    };
}

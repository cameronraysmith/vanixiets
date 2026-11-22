# Behavioural check for the secret-file-modes activation program
# (modules/home/core/secret-file-modes.sh) against fixture homes.
#
# One home holds the hand-placed files as they were found on the fleet: a 0644
# age key and 0644 ssh private keys in 0755 directories, beside public keys,
# known_hosts, authorized_keys, a file named like a key that is not one, and
# symlinks into a stand-in store. A second home lacks every path, and a third
# reaches ~/.config/sops through a symlink.
#
# The mutant detects private keys by filename, the plausible shortcut the
# program must not take; it runs only the fixture key whose name gives nothing
# away, which it must leave readable.
#
# x86_64-linux only: the program runs nixpkgs' bash, coreutils and findutils on
# every platform, so its behaviour does not depend on the system.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      program = self.lib.secretFileModesProgram pkgs;
      source = builtins.readFile ../home/core/secret-file-modes.sh;
      contentDetection = ''[[ $line =~ ^-----BEGIN\ ([A-Z0-9]+\ )*PRIVATE\ KEY-----$ ]]'';
      mutantSource =
        builtins.replaceStrings
          [ contentDetection ]
          [
            ''[[ $(basename "$1") == id_* && $1 != *.pub ]]''
          ]
          source;
      mutantProgram =
        assert lib.assertMsg (
          mutantSource != source
        ) "secret-file-modes: the filename mutant no longer applies";
        pkgs.writeShellApplication {
          name = "secret-file-modes-filename-mutant";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.findutils
          ];
          text = mutantSource;
        };
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        secret-file-modes-rehearsal =
          pkgs.runCommand "secret-file-modes-rehearsal"
            {
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.findutils
                pkgs.diffutils
              ];
              meta.description = "behavioural check: secret-file-modes activation program";
            }
            ''
              fail() { echo "FAIL: $*" >&2; exit 1; }
              hasMode() {
                [ "$(stat -c %a "$1")" = "$2" ] || fail "$1: mode $(stat -c %a "$1"), expected $2"
              }

              store=$TMPDIR/store
              mkdir -p "$store/sops/age"
              printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----\n' > "$store/linked-key" # gitleaks:allow
              printf 'Host *\n' > "$store/ssh-config"
              printf 'AGE-SECRET-KEY-1STORE\n' > "$store/sops/age/keys.txt"
              chmod 644 "$store/linked-key" "$store/ssh-config" "$store/sops/age/keys.txt"
              chmod 755 "$store/sops" "$store/sops/age"

              fixture() {
                local h=$1
                mkdir -p "$h/.config/sops/age" "$h/.ssh"
                printf 'AGE-SECRET-KEY-1FIXTURE\n' > "$h/.config/sops/age/keys.txt"
                printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----\n' > "$h/.ssh/deploy-github"
                printf -- '-----BEGIN RSA PRIVATE KEY-----\r\nAAAA\r\n-----END RSA PRIVATE KEY-----\r\n' > "$h/.ssh/legacy.pem"
                printf 'ssh-ed25519 AAAA fixture\n' > "$h/.ssh/deploy-github.pub"
                printf 'not a key, only named like one\n' > "$h/.ssh/id_ed25519"
                printf 'host ssh-ed25519 AAAA\n' > "$h/.ssh/known_hosts"
                printf 'ssh-ed25519 AAAA fixture\n' > "$h/.ssh/authorized_keys"
                ln -s "$store/linked-key" "$h/.ssh/linked-key"
                ln -s "$store/ssh-config" "$h/.ssh/config"
                find "$h" -type f -exec chmod 644 {} +
                find "$h" -type d -exec chmod 755 {} +
              }

              echo "--- hand-placed files are tightened and logged"
              h=$TMPDIR/placed
              fixture "$h"
              ${lib.getExe program} "$h" > log
              cat log
              hasMode "$h/.config/sops" 700
              hasMode "$h/.config/sops/age" 700
              hasMode "$h/.config/sops/age/keys.txt" 600
              hasMode "$h/.ssh" 700
              hasMode "$h/.ssh/deploy-github" 600
              hasMode "$h/.ssh/legacy.pem" 600
              for f in deploy-github.pub id_ed25519 known_hosts authorized_keys; do
                hasMode "$h/.ssh/$f" 644
              done
              [ -L "$h/.ssh/linked-key" ] && [ -L "$h/.ssh/config" ] || fail "a symlink was replaced"
              hasMode "$store/linked-key" 644
              hasMode "$store/ssh-config" 644
              sort log > actual
              sort > expected <<EOF
              secret-file-modes: $h/.config/sops: 755 -> 700
              secret-file-modes: $h/.config/sops/age: 755 -> 700
              secret-file-modes: $h/.config/sops/age/keys.txt: 644 -> 600
              secret-file-modes: $h/.ssh: 755 -> 700
              secret-file-modes: $h/.ssh/deploy-github: 644 -> 600
              secret-file-modes: $h/.ssh/legacy.pem: 644 -> 600
              EOF
              diff expected actual || fail "log differs"

              echo "--- a second activation changes and logs nothing"
              ${lib.getExe program} "$h" > log
              [ ! -s log ] || fail "second run logged: $(cat log)"

              echo "--- missing paths are not created"
              h=$TMPDIR/empty
              mkdir "$h"
              ${lib.getExe program} "$h" > log
              [ -z "$(find "$h" -mindepth 1)" ] || fail "created: $(find "$h" -mindepth 1)"
              [ ! -s log ] || fail "logged: $(cat log)"

              echo "--- a symlinked ~/.config/sops is not followed"
              h=$TMPDIR/linked
              mkdir -p "$h/.config"
              ln -s "$store/sops" "$h/.config/sops"
              ${lib.getExe program} "$h" > log
              hasMode "$store/sops" 755
              hasMode "$store/sops/age" 755
              hasMode "$store/sops/age/keys.txt" 644
              [ ! -s log ] || fail "logged: $(cat log)"

              echo "--- mutant: detection by filename leaves deploy-github readable"
              h=$TMPDIR/mutant
              fixture "$h"
              ${lib.getExe mutantProgram} "$h" > /dev/null
              [ "$(stat -c %a "$h/.ssh/deploy-github")" != 600 ] \
                || fail "the filename mutant tightened deploy-github; the rehearsal cannot tell detection by name from detection by content"

              touch $out
            '';
      };
    };
}

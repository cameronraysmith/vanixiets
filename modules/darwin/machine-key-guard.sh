# machine-key-guard: compare a darwin host's installed clan machine key with the
# public key the repository records for it.
#
# Usage: machine-key-guard <host> <expected-public-key> [--dry]
# Exit 0 when the installed key's public key equals the expected one, 1 otherwise
# (with a message naming `clan vars upload <host>`). Prints public keys only.
# MACHINE_KEY_FILE overrides the key path (default /var/lib/sops-nix/key.txt).
#
# clan's upload creates /var/lib/sops-nix root-only (0700), so an unprivileged
# user cannot even tell whether the key file exists. When the file is not
# readable, existence and the public key are both decided as root through sudo.
# A dry run uses `sudo -n` so it never blocks on a password prompt; a real
# activation uses plain sudo, which may prompt (nh prompts in the same run).
# If sudo cannot run, the check fails closed and says so.

host=$1
expected=$2
dry=0
[ "${3:-}" = "--dry" ] && dry=1
key_file="${MACHINE_KEY_FILE:-/var/lib/sops-nix/key.txt}"
age_keygen=$(command -v age-keygen)

actual=""
if [ -r "$key_file" ]; then
  actual=$("$age_keygen" -y "$key_file" 2>/dev/null || true)
  found="${actual:-present but unreadable (age-keygen -y failed)}"
else
  if [ "$dry" -eq 1 ]; then
    sudo_cmd=(sudo -n)
  else
    sudo_cmd=(sudo)
  fi
  if "${sudo_cmd[@]}" true 2>/dev/null; then
    if "${sudo_cmd[@]}" test -e "$key_file"; then
      actual=$("${sudo_cmd[@]}" "$age_keygen" -y "$key_file" 2>/dev/null || true)
      found="${actual:-present but unreadable (age-keygen -y as root failed)}"
    else
      found="missing"
    fi
  else
    found="not checked: '${sudo_cmd[*]}' failed, so the root-only key file could not be inspected"
  fi
fi

if [ -n "$actual" ] && [ "$actual" = "$expected" ]; then
  exit 0
fi

cat >&2 <<EOF
Machine key check failed for $host ($key_file):
  expected: $expected (sops/machines/$host/key.json)
  found:    $found
sops-nix cannot install this host's secrets without it.
Install it with: clan vars upload $host
EOF
exit 1

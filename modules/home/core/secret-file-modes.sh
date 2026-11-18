# secret-file-modes HOME
#
# Makes the secret files a person places by hand in HOME private to them:
# ~/.config/sops and ~/.config/sops/age become 0700 and
# ~/.config/sops/age/keys.txt 0600; ~/.ssh becomes 0700 and every regular file
# directly in it whose first line is a PEM private-key header 0600. A path is
# changed only when its group or other bits are set, and each change is
# printed. Missing paths are not created, symlinks are neither changed nor
# followed, and paths owned by another account are reported and left alone.

if [ "$#" -ne 1 ]; then
  echo "usage: secret-file-modes HOME" >&2
  exit 2
fi
home=$1

# tighten KIND RELPATH MODE: sets HOME/RELPATH to MODE when it is a KIND (dir
# or file) that grants any group or other permission, and neither it nor any
# directory between HOME and it is a symlink.
tighten() {
  local kind=$1 relpath=$2 mode=$3 path=$home current part
  local -a parts
  IFS=/ read -r -a parts <<<"$relpath"
  for part in "${parts[@]}"; do
    path=$path/$part
    if [ -L "$path" ]; then
      return 0
    fi
  done
  case $kind in
    dir) [ -d "$path" ] || return 0 ;;
    file) [ -f "$path" ] || return 0 ;;
  esac
  if ! [ -O "$path" ]; then
    echo "secret-file-modes: $path: owned by another account, left unchanged" >&2
    return 0
  fi
  current=$(stat -c %a "$path")
  if ((8#$current & 8#077)); then
    chmod "$mode" "$path"
    echo "secret-file-modes: $path: $current -> $mode"
  fi
}

# Private keys are recognised by their content, never by their name.
is_private_key() {
  local line=
  IFS= read -r line <"$1" || [ -n "$line" ] || return 1
  line=${line%$'\r'}
  [[ $line =~ ^-----BEGIN\ ([A-Z0-9]+\ )*PRIVATE\ KEY-----$ ]]
}

tighten dir .config/sops 700
tighten dir .config/sops/age 700
tighten file .config/sops/age/keys.txt 600

tighten dir .ssh 700
if [ -d "$home/.ssh" ] && ! [ -L "$home/.ssh" ]; then
  while IFS= read -r -d '' name; do
    if is_private_key "$home/.ssh/$name"; then
      tighten file ".ssh/$name" 600
    fi
  done < <(find "$home/.ssh" -mindepth 1 -maxdepth 1 -type f -printf '%f\0')
fi

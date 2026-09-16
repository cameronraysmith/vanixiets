if [[ $# != 3 ]]; then
  echo "Usage: omnigent-worker-login HOST OWNER TOOL" >&2
  echo "Hosts: magnetite, pyrite, stibnite; owners: cameron, janettesmith" >&2
  echo "Tools: claude, codex, atomic, omp, pi, verify" >&2
  exit 2
fi
host=$1 owner=$2 tool=$3
case "$host/$owner" in
  magnetite/cameron|magnetite/janettesmith|pyrite/cameron|pyrite/janettesmith) ;;
  stibnite/cameron) ;;
  *) echo "No approved worker for $host/$owner" >&2; exit 2 ;;
esac
user="omnigent-$owner"
if [[ "$host" == stibnite ]]; then
  home="/Users/$user"
  profile="/etc/omnigent/workers/$owner/home-path"
else
  home="/home/$user"
  profile="/etc/profiles/per-user/$user"
fi
case "$tool" in
  claude) arguments=(claude auth login --claudeai) ;;
  codex) arguments=(codex login --device-auth) ;;
  atomic|omp|pi)
    arguments=("$tool")
    printf 'In %s, enter /login and select the intended subscription provider. Exit when login completes.\n' "$tool"
    ;;
  verify) arguments=(omnigent-worker-verify) ;;
  *) echo "Unsupported tool: $tool" >&2; exit 2 ;;
esac
printf 'Target: %s / %s; authentication stays in %s\n' "$host" "$user" "$home"
command=(sudo -n -H -u "$user" env -i
  "HOME=$home" "USER=$user" "LOGNAME=$user"
  "XDG_CONFIG_HOME=$home/.config" "XDG_CACHE_HOME=$home/.cache"
  "XDG_STATE_HOME=$home/.local/state" "XDG_DATA_HOME=$home/.local/share"
  "PATH=$profile/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  "TERM=${TERM:-xterm-256color}")
if [[ "$tool" == atomic ]]; then
  command+=("PI_CODING_AGENT_DIR=$home/.atomic/agent")
fi
# shellcheck disable=SC2016
command+=(/bin/sh -c 'cd "$HOME" && exec "$@"' worker-login "${arguments[@]}")
cd /
if [[ "$host" == stibnite && "$(/bin/hostname -s)" == stibnite ]]; then
  exec "${command[@]}"
fi
printf -v remote '%q ' "${command[@]}"
if [[ "$host" == stibnite ]]; then
  endpoint=crs58@stibnite.zt
else
  endpoint="root@$host.zt"
fi
exec ssh -t -o ForwardAgent=no -o StrictHostKeyChecking=yes "$endpoint" "cd / && $remote"

# Point every hardware network service at the local dnscrypt-proxy.
#
# macOS keeps DNS servers per network service and resolves through the active
# service's servers, so encrypted DNS holds only if every service that can
# become active is pointed at the local listener. A service is created the
# first time an adapter is attached (a Thunderbolt or USB Ethernet adapter, an
# iPhone), so the set cannot be listed ahead of time; this script discovers it.
#
#   dnscrypt-pin-dns          set 127.0.0.1 ::1 on every unpinned service
#   dnscrypt-pin-dns --check  report unpinned services, exit 1 if any
#
# Writes happen only where the value differs, so running it from a launchd
# WatchPaths trigger on the SystemConfiguration preferences does not
# retrigger itself. EXCLUDED_SERVICES holds service names to leave alone, one
# per line.

want="127.0.0.1 ::1"
mode="${1:-apply}"
case "$mode" in
  apply | --check) ;;
  *)
    echo "usage: dnscrypt-pin-dns [--check]" >&2
    exit 2
    ;;
esac

excluded() {
  [ -n "${EXCLUDED_SERVICES:-}" ] && printf '%s\n' "$EXCLUDED_SERVICES" | grep -Fxq -- "$1"
}

unpinned=0
service=""
# networksetup -listnetworkserviceorder prints each service as a name line,
# "(1) Wi-Fi" or "(*) Wi-Fi" when disabled, followed by its hardware line,
# "(Hardware Port: Wi-Fi, Device: en0)". Services without a hardware device
# (VPNs and other software services) have an empty Device and are skipped, so
# their own DNS settings are never overwritten.
while IFS= read -r line; do
  case "$line" in
    "(Hardware Port: "*", Device: "*")")
      device="${line##*, Device: }"
      device="${device%)}"
      case "$device" in
        en[0-9]* | bridge[0-9]*) ;;
        *) continue ;;
      esac
      [ -n "$service" ] || continue
      excluded "$service" && continue
      current="$(/usr/sbin/networksetup -getdnsservers "$service" | paste -sd ' ' -)"
      [ "$current" = "$want" ] && continue
      if [ "$mode" = --check ]; then
        echo "not pinned: $service ($device): $current" >&2
        unpinned=1
      else
        # shellcheck disable=SC2086 # $want is two addresses by design
        /usr/sbin/networksetup -setdnsservers "$service" $want
        echo "pinned DNS for $service ($device) to $want"
      fi
      ;;
    "("[0-9]*") "* | "(*) "*)
      service="${line#*) }"
      ;;
  esac
done < <(/usr/sbin/networksetup -listnetworkserviceorder)

exit "$unpinned"

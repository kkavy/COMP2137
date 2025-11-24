#!/usr/bin/env bash
# Create script configure-host.sh

set -o errexit
set -o nounset
set -o pipefail

# ignore TERM, HUP, INT
trap '' TERM HUP INT

VERBOSE=0
NAME=""
IPADDR=""
HOSTENTRY_NAME=""
HOSTENTRY_IP=""
NETMASK="24"
NETPLAN_FILE="/etc/netplan/99-config-lab3.yaml"
BACKUP_TS="$(date +%s)"
BACKUP_SUFFIX=".bak.$BACKUP_TS"

logv() { [ "$VERBOSE" -eq 1 ] && echo "$@"; }
logerr() { echo "ERROR: $@" >&2; }
die() { logerr "$@"; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [-verbose] [-name desiredName] [-ip desiredIP] [-hostentry name ip]
EOF
  exit 2
}

# parse args
while [ "$#" -gt 0 ]; do
  case "$1" in
    -verbose) VERBOSE=1; shift ;;
    -name) NAME="$2"; shift 2 ;;
    -ip) IPADDR="$2"; shift 2 ;;
    -hostentry) HOSTENTRY_NAME="$2"; HOSTENTRY_IP="$3"; shift 3 ;;
    -h|--help) usage ;;
    *) logerr "Unknown arg: $1"; usage ;;
  esac
done

# helpers
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    logv "Script not run as root. Some operations may fail; re-run with sudo or as root."
  fi
}

detect_iface() {
  # prefer interfaces with a global IPv4 address (common in lab networks)
  iface=$(ip -4 -o addr show scope global | awk '{print $2; exit}' || true)
  if [ -n "$iface" ]; then
    echo "$iface"
    return 0
  fi
  # fallback to first non-loopback device
  iface=$(ip link show | awk -F: '$0 !~ "lo|vir|wl|docker|^[[:space:]]$" {gsub(/^[[:space:]]/,"",$2); print $2; exit}' ORS='' || true)
  if [ -n "$iface" ]; then
    echo "$iface"
    return 0
  fi
  echo "eth0"
  return 0
}

backup_file() {
  local f="$1"
  if [ -f "$f" ]; then
    cp -p "$f" "${f}${BACKUP_SUFFIX}"
    logv "Backed up $f to ${f}${BACKUP_SUFFIX}"
  fi
}

# ensure hostname
ensure_hostname() {
  local newname="$1"
  [ -z "$newname" ] && return 0

  current="$(hostnamectl --static 2>/dev/null || cat /etc/hostname 2>/dev/null || hostname)"
  current="$(echo "$current" | tr -d '[:space:]')"

  if [ "$current" = "$newname" ]; then
    logv "Hostname already set to $newname"
    return 0
  fi

  backup_file /etc/hostname
  echo "$newname" > /etc/hostname
# update 127.0.1.1 mapping (Debian/Ubuntu convention)
  backup_file /etc/hosts
  if grep -q '^127\.0\.1\.1' /etc/hosts 2>/dev/null; then
    sed -i -E "s/^(127\.0\.1\.1[[:space:]]+).*/\1${newname}/" /etc/hosts
  else
    printf "127.0.1.1\t%s\n" "$newname" >> /etc/hosts
  fi

  if command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "$newname"
  else
    hostname "$newname"
  fi

  logger "configure-host: hostname changed from ${current:-unknown} to ${newname}"
  logv "Hostname changed from ${current:-unknown} to ${newname}"
}

# ensure hosts entry (specific ip -> name)
ensure_hosts_entry() {
  local name="$1"; local ip="$2"
  [ -z "$name" ] || [ -z "$ip" ] || true

  # check if exact mapping exists
  if grep -E "^[[:space:]]*${ip}[[:space:]]+${name}([[:space:]]+|$)" /etc/hosts >/dev/null 2>&1; then
    logv "/etc/hosts already contains ${ip} ${name}"
    return 0
  fi

  backup_file /etc/hosts
  # remove any other mapping for this name
  sed -i -E "/[[:space:]]+${name}([[:space:]]+|$)/d" /etc/hosts || true
  printf "%s\t%s\n" "$ip" "$name" >> /etc/hosts
  logger "configure-host: added hosts entry ${name} ${ip}"
  logv "Added hosts entry: ${ip} ${name}"
}

# ensure IP via netplan
ensure_ip_netplan() {
  local ip="$1"
  [ -z "$ip" ] && return 0

  local iface
  iface="$(detect_iface)"
  [ -z "$iface" ] && die "Failed to detect network interface."

  # if interface already has this IP, skip
  if ip -4 -o addr show "$iface" | awk '{print $4}' | grep -q "^${ip}/"; then
    logv "$iface already has IP ${ip}"
    return 0
  fi

  # backup existing netplan file if present
  backup_file "$NETPLAN_FILE"

  gw="$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}' || true)"

  # write minimal netplan config
  {
    echo "network:"
    echo "  version: 2"
    echo "  renderer: networkd"
    echo "  ethernets:"
    echo "    ${iface}:"
    echo "      dhcp4: no"
    echo "      addresses: [ ${ip}/${NETMASK} ]"
    if [ -n "$gw" ]; then
      echo "      gateway4: ${gw}"
    fi
  } > "$NETPLAN_FILE"

  logv "Wrote netplan config to $NETPLAN_FILE for iface $iface -> ${ip}/${NETMASK}"

  if command -v netplan >/dev/null 2>&1; then
    if netplan apply; then
      logger "configure-host: IP ${ip} configured on ${iface}"
      logv "netplan apply succeeded"
    else
      logerr "netplan apply failed"
      return 1
    fi
  else
    logerr "netplan not present; wrote file but did not apply"
    return 1
  fi
}

# main
require_root

if [ -n "$NAME" ]; then
  ensure_hostname "$NAME" || die "Failed to set hostname"
fi

if [ -n "$IPADDR" ]; then
  ensure_ip_netplan "$IPADDR" || die "Failed to set IP $IPADDR"
  # if NAME provided, ensure hosts maps IP -> NAME
  if [ -n "$NAME" ]; then
    ensure_hosts_entry "$NAME" "$IPADDR"
  fi
fi

if [ -n "$HOSTENTRY_NAME" ] && [ -n "$HOSTENTRY_IP" ]; then
  ensure_hosts_entry "$HOSTENTRY_NAME" "$HOSTENTRY_IP" || die "Failed to add hostentry ${HOSTENTRY_NAME}"
fi

logv "configure-host.sh completed."
exit 0

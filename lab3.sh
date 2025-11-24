#!/usr/bin/env bash
# lab3.sh - deploy configure-host.sh to server1 and server2, run remote configuration, and update local /etc/hosts

set -o errexit
set -o nounset
set -o pipefail

VERBOSE=0
usage() { echo "Usage: $0 [-verbose]"; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    -verbose) VERBOSE=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg $1"; usage ;;
  esac
done

v() { [ "$VERBOSE" -eq 1 ] && echo "$@"; }

# Config — modify if your lab uses different names or user
REMOTE_USER="remoteadmin"
SERVER1="server1-mgmt"
SERVER2="server2-mgmt"
REMOTE_PATH="/root/configure-host.sh"
LOCAL_SCRIPT="./configure-host.sh"

# check local script exists
if [ ! -f "$LOCAL_SCRIPT" ]; then
  echo "Local $LOCAL_SCRIPT not found. Place configure-host.sh here and rerun." >&2
  exit 1
fi

scp_copy() {
  local host="$1"
  v "Copying $LOCAL_SCRIPT to ${REMOTE_USER}@${host}:${REMOTE_PATH} ..."
  if scp "$LOCAL_SCRIPT" "${REMOTE_USER}@${host}:${REMOTE_PATH}"; then
    v "scp to ${host} succeeded."
  else
    echo "scp to ${host} failed." >&2
    return 1
  fi
  v "Setting executable permission on remote script..."
  if ssh "${REMOTE_USER}@${host}" -- "chmod +x ${REMOTE_PATH}"; then
    v "chmod remote succeeded"
  else
    echo "chmod on ${host} failed" >&2
    return 1
  fi
  return 0
}

run_remote() {
  local host="$1"
  shift
  # build remote args; ensure -verbose forwarded if requested
  remote_flags=()
  [ "$VERBOSE" -eq 1 ] && remote_flags+=("-verbose")
  for a in "$@"; do remote_flags+=("$a"); done

  v "Running on ${host}: sudo ${REMOTE_PATH} ${remote_flags[*]}"
  if ssh "${REMOTE_USER}@${host}" -- "sudo ${REMOTE_PATH} ${remote_flags[*]}"; then
    v "Remote configuration on ${host} succeeded"
  else
    echo "Remote configuration on ${host} failed" >&2
    return 1
  fi
  return 0
}

# 1) copy to both servers
scp_copy "$SERVER1" || { echo "Failed to copy to $SERVER1"; exit 1; }
scp_copy "$SERVER2" || { echo "Failed to copy to $SERVER2"; exit 1; }

# 2) run configurations (example addresses based on lab diagram)
# server1 -> loghost 192.168.16.3, hostentry webhost 192.168.16.4
run_remote "$SERVER1" -name loghost -ip 192.168.16.3 -hostentry webhost 192.168.16.4 || { echo "Config for $SERVER1 failed"; exit 1; }
sleep 2
# server2 -> webhost 192.168.16.4, hostentry loghost 192.168.16.3
run_remote "$SERVER2" -name webhost -ip 192.168.16.4 -hostentry loghost 192.168.16.3 || { echo "Config for $SERVER2 failed"; exit 1; }

# 3) update local /etc/hosts entries for both hosts using local configure-host.sh
v "Updating local /etc/hosts entries ..."
sudo "$LOCAL_SCRIPT" $([ "$VERBOSE" -eq 1 ] && echo -verbose) -hostentry loghost 192

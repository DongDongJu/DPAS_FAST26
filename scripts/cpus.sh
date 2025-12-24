#!/bin/bash
#
# Control CPU hotplug state for a given CPU id.
#
# Usage:
#   sudo ./cpus.sh 1 <cpu_id>   # online
#   sudo ./cpus.sh 0 <cpu_id>   # offline
#
# This script is used by scripts/cpuonoff.sh.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 [0/1] <cpu_id>" >&2
  exit 2
fi

action="$1"
cpu_id="$2"

if [[ "${action}" != "0" && "${action}" != "1" ]]; then
  echo "[ERROR] action must be 0 or 1 (got: ${action})" >&2
  exit 2
fi

if ! [[ "${cpu_id}" =~ ^[0-9]+$ ]]; then
  echo "[ERROR] cpu_id must be an integer (got: ${cpu_id})" >&2
  exit 2
fi

online_path="/sys/devices/system/cpu/cpu${cpu_id}/online"

# cpu0 often lacks 'online' control; treat it as always online.
if [[ ! -e "${online_path}" ]]; then
  exit 0
fi

echo "${action}" > "${online_path}"

#!/bin/bash
echo $1 > /sys/devices/system/cpu/cpu$2/online

#!/bin/bash
#
# Track a process' CPU usage periodically while it is running.
# This script is used by scripts/bgio_noaffinity.sh (FIG21 flow).

set -euo pipefail

PNAME="${1:-}"
LOG_FILE="${2:-}"
TIME_LOG_FOLDER="$(pwd)/time_log"

if [[ -z "${PNAME}" || -z "${LOG_FILE}" ]]; then
  echo "Usage: $0 <process_name> <log_file>" >&2
  exit 2
fi

# When run as root (e.g. via run_all.sh), avoid depending on sudo config.
if [[ "${EUID}" -eq 0 ]]; then
  sudo() { "$@"; }
  export -f sudo
fi

mkdir -p "${TIME_LOG_FOLDER}"

# Best-effort tmpfs mount (skip if not allowed / already mounted).
if command -v mountpoint >/dev/null 2>&1; then
  if ! mountpoint -q "${TIME_LOG_FOLDER}" 2>/dev/null; then
    sudo mount -o size=1G -t tmpfs none "${TIME_LOG_FOLDER}" 2>/dev/null || true
  fi
else
  sudo mount -o size=1G -t tmpfs none "${TIME_LOG_FOLDER}" 2>/dev/null || true
fi

[[ -f "${LOG_FILE}" ]] && rm -f "${LOG_FILE}"

while true; do
  if [[ -n "$(pidof -s "${PNAME}" 2>/dev/null || true)" ]]; then
    pids="$(pidof -s "${PNAME}")"
    echo "$(date) :: ${PNAME}[$(pidof "${PNAME}")] $(ps -p "${pids}" -o %cpu | tail -n1 )%" >> "${TIME_LOG_FOLDER}/${LOG_FILE}"
  else
    break
  fi
  sleep 0.5
done

mv "${TIME_LOG_FOLDER}/${LOG_FILE}" "${LOG_FILE}"

# Cleanup tmpfs (best-effort).
if command -v mountpoint >/dev/null 2>&1; then
  if mountpoint -q "${TIME_LOG_FOLDER}" 2>/dev/null; then
    sudo umount "${TIME_LOG_FOLDER}" 2>/dev/null || true
  fi
fi

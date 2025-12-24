#!/bin/bash
#
# Cleanup generated outputs and build artifacts for this repository.
#
# This script is safe to run multiple times. It is intended to be run as root
# (because previous runs may have created root-owned files).
#
# Usage:
#   sudo ./scripts/cleanup_artifact_tree.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] must be run as root (sudo)." >&2
  exit 1
fi

echo "[CLEAN] removing generated experiment outputs"
rm -rf \
  "${ROOT_DIR}/scripts/micro_128krr/fio_data" \
  "${ROOT_DIR}/scripts/micro_128krr/parsed_data" \
  "${ROOT_DIR}/scripts/micro_128krr/result_data" \
  "${ROOT_DIR}/scripts/micro_128krr/test_"* \
  "${ROOT_DIR}/scripts/micro_4krr/fio_data" \
  "${ROOT_DIR}/scripts/micro_4krr/parsed_data" \
  "${ROOT_DIR}/scripts/micro_4krr/result_data" \
  "${ROOT_DIR}/scripts/micro_4krr/test_"* \
  "${ROOT_DIR}/scripts/ycsb_"*_results \
  "${ROOT_DIR}/scripts/results" \
  "${ROOT_DIR}/scripts/out" \
  "${ROOT_DIR}/scripts/time_log" \
  "${ROOT_DIR}/scripts/result_collection/"*.txt \
  "${ROOT_DIR}/scripts/test" \
  "${ROOT_DIR}/scripts/rocksdb.properties.runtime" \
  "${ROOT_DIR}/scripts/"*.runtime \
  "${ROOT_DIR}/scripts/"*.properties.runtime \
  "${ROOT_DIR}/utils/__pycache__" \
  "${ROOT_DIR}/scripts/"__pycache__ \
  "${ROOT_DIR}/scripts/micro_128krr/__pycache__" \
  "${ROOT_DIR}/scripts/micro_4krr/__pycache__" \
  2>/dev/null || true

echo "[CLEAN] removing built binaries (rebuild via scripts/build_fig21_deps.sh)"
rm -f \
  "${ROOT_DIR}/scripts/io-generator" \
  "${ROOT_DIR}/scripts/io-generator1" \
  "${ROOT_DIR}/scripts/io-generator2" \
  "${ROOT_DIR}/scripts/io-generator3" \
  "${ROOT_DIR}/scripts/io-generator4" \
  2>/dev/null || true

echo "[OK] cleanup done."


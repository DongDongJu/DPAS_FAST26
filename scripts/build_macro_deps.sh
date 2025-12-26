#!/bin/bash
#
# Build dependencies for macro benchmark (BGIO + YCSB) flow.
#
# This builds:
# - scripts/io-generator (from scripts/io_gen.c) + symlinks io-generator1..4
# - apps/rocksdb_modi (static_lib)
# - apps/YCSB-cpp-modi (ycsb)
#
# Usage:
#   ./scripts/build_macro_deps.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="${ROOT_DIR}/scripts"
APPS_DIR="${ROOT_DIR}/apps"

echo "[BUILD] io-generator from scripts/io_gen.c"
if ! command -v gcc >/dev/null 2>&1; then
  echo "[ERROR] gcc not found. Install build-essential / gcc." >&2
  exit 1
fi

gcc -O2 -D_GNU_SOURCE -pthread -o "${SCRIPTS_DIR}/io-generator" "${SCRIPTS_DIR}/io_gen.c" || {
  echo "[ERROR] failed to build io-generator. You may need -lrt on older systems." >&2
  exit 1
}

for i in 1 2 3 4; do
  ln -sf "io-generator" "${SCRIPTS_DIR}/io-generator${i}"
done

echo "[BUILD] rocksdb_modi (apps/rocksdb_modi) static_lib"
make -C "${APPS_DIR}/rocksdb_modi" static_lib

echo "[BUILD] YCSB-cpp-modi (apps/YCSB-cpp-modi)"
make -C "${APPS_DIR}/YCSB-cpp-modi" || {
  echo "[ERROR] failed to build YCSB-cpp-modi." >&2
  echo "        If you see undefined references like io_uring_* or BZ2_*," >&2
  echo "        install runtime/dev libs and retry:" >&2
  echo "          - Ubuntu/Debian: sudo apt install -y liburing-dev libbz2-dev zlib1g-dev libsnappy-dev liblz4-dev libzstd-dev" >&2
  echo "        (YCSB links against RocksDB and must link these transitive libs.)" >&2
  exit 1
}

echo "[OK] macro benchmark dependencies built."


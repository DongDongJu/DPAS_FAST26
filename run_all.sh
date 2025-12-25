#!/bin/sh

set -eu

# Force a stable, English locale for all subprocess outputs (e.g., `date`).
# This avoids Korean day/month names depending on the host locale.
export LC_ALL=C
export LANG=C

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SCRIPTS_DIR="${ROOT_DIR}/scripts"
UTILS_DIR="${ROOT_DIR}/utils"
APPS_DIR="${ROOT_DIR}/apps"

usage() {
  cat <<'EOF'
Usage:
  sudo ./run_all.sh [--draft] [--clean] [--raw] [--bgio-iops N] [BGIO_IOPS]

Options:
  --draft       Quick smoke-test mode (shorter runtimes and smaller sweeps).
  --clean       Remove ./parsed_data and ./result_data before each micro experiment.
  --raw         Print raw parsed output instead of pretty tables.
  --bgio-iops N Enable FIG21 (BGIO+YCSB) and set BGIO target IOPS.
               (You can also pass BGIO_IOPS as a positional argument.)

Notes:
  - FIG21 (BGIO+YCSB) runs only when BGIO_IOPS is provided.
    (If BGIO_IOPS is omitted, only microbenchmarks will run.)
  - You can also set BGIO_IOPS via BGIO_IOPS or DPAS_BGIO_IOPS environment variables.
EOF
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

require_root() {
  [ "${EUID:-$(id -u)}" -eq 0 ] || die "this script must be run as root (sudo)."
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_file() {
  [ -e "$1" ] || die "required file not found: $1"
}

require_executable() {
  [ -x "$1" ] || die "required executable not found or not executable: $1"
}

ensure_all_cpus_online() {
  cpu_tool="${UTILS_DIR}/cpu"
  if [ -x "${cpu_tool}" ]; then
    echo "[INFO] bringing all CPUs online via utils/cpu"
    "${cpu_tool}" on || true
    return 0
  fi

  echo "[WARN] ${cpu_tool} not found/executable; falling back to sysfs CPU online" >&2
  for d in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -d "${d}" ] || continue
    if [ -f "${d}/online" ]; then
      echo 1 > "${d}/online" 2>/dev/null || true
    fi
  done
}

ensure_fig21_deps_built() {
  build_script="${SCRIPTS_DIR}/build_fig21_deps.sh"
  require_executable "${build_script}"

  need_build=0
  [ -x "${SCRIPTS_DIR}/io-generator1" ] || need_build=1
  [ -x "${APPS_DIR}/YCSB-cpp-modi/ycsb" ] || need_build=1

  if [ "${need_build}" -eq 1 ]; then
    echo "[INFO] FIG21 dependencies missing; building now..."
    bash "${build_script}"
  fi
}

chown_outputs_to_invoker() {
  owner="${SUDO_USER:-}"
  if [ -z "${owner}" ] || [ "${owner}" = "root" ]; then
    return 0
  fi

  for p in "$@"; do
    [ -e "${p}" ] || continue
    chown -R "${owner}:${owner}" "${p}" 2>/dev/null || true
  done
}

cat_parsed_data_raw() {
  found=0
  for f in ./parsed_data/*; do
    if [ -f "${f}" ]; then
      cat "${f}"
      found=1
    fi
  done
  if [ "${found}" -eq 1 ]; then
    return 0
  fi

  found=0
  for f in /parsed_data/*; do
    if [ -f "${f}" ]; then
      cat "${f}"
      found=1
    fi
  done
  if [ "${found}" -eq 1 ]; then
    return 0
  fi

  echo "[WARN] no parsed_data found in ./parsed_data or /parsed_data" >&2
}

pretty_print_parsed_data() {
  tool="${UTILS_DIR}/pretty_print.py"
  if [ -f "${tool}" ]; then
    python3 "${tool}" "./parsed_data" || cat_parsed_data_raw
  else
    cat_parsed_data_raw
  fi
}

run_experiment() {
  exp_dir="$1"
  repeats="$2"
  clean="$3"
  raw="$4"

  exp_name="$(basename "${exp_dir}")"
  echo
  echo "============================================================"
  echo "[RUN] ${exp_name}"
  echo "============================================================"

  [ -d "${exp_dir}" ] || die "experiment directory not found: ${exp_dir}"

  oldpwd="$(pwd)"
  cd "${exp_dir}" || exit 1

  if [ "${clean}" -eq 1 ]; then
    rm -rf ./parsed_data ./result_data || true
  fi

  bash ./run.sh
  python3 ./parse.py "${repeats}"

  echo
  echo "[OUTPUT] ${exp_name} parsed_data"
  if [ "${raw}" -eq 1 ]; then
    cat_parsed_data_raw
  else
    pretty_print_parsed_data
  fi

  chown_outputs_to_invoker ./fio_data ./parsed_data ./result_data ./test_*

  cd "${oldpwd}" || exit 1
}

run_fig21_bg_ycsb() {
  bgio_iops="$1"
  draft="$2"

  sleep_time=5
  epoch_ms=320
  bgruntime=3600
  if [ "${draft}" -eq 1 ]; then
    sleep_time=1
    bgruntime=60
  fi

  echo
  echo "============================================================"
  echo "[RUN] FIG21 (BGIO + YCSB)  (BGIO_IOPS=${bgio_iops})"
  echo "============================================================"

  oldpwd="$(pwd)"
  cd "${SCRIPTS_DIR}" || exit 1

  # Ensure we don't leave CPUs offlined on failures.
  trap "bash ./cpuonoff.sh 1 19 >/dev/null 2>&1 || true; cd \"${oldpwd}\" >/dev/null 2>&1 || true" 0 1 2 3 15

  ensure_fig21_deps_built

  require_executable "./cpuonoff.sh"
  require_executable "./cpus.sh"
  require_executable "./bgio_noaffinity.sh"
  require_executable "./cp_res.sh"
  require_file "./um.sh"
  require_executable "./result_collection/parse.sh"

  require_executable "./io-generator1"
  require_executable "./io-generator2"
  require_executable "./io-generator3"
  require_executable "./io-generator4"
  require_executable "${APPS_DIR}/YCSB-cpp-modi/ycsb"
  require_file "${APPS_DIR}/YCSB-cpp-modi/workloads"
  require_file "${APPS_DIR}/YCSB-cpp-modi/rocksdb/rocksdb.properties"
  require_file "${UTILS_DIR}/track_cpu.sh"
  require_file "${UTILS_DIR}/postprocessing.py"

  bash ./cpuonoff.sh 0 19
  bash ./cpuonoff.sh 1 3

  run_one_fig21() {
    dev="$1"
    threshold="$2"
    name="$3"

    echo
    echo "[FIG21] ${name}  device=${dev}  threshold=${threshold}"
    sh ./um.sh || true
    bash ./bgio_noaffinity.sh 4 4 "${dev}" "${sleep_time}" "${bgio_iops}" "${epoch_ms}" "${bgruntime}" "${threshold}" CP HP EHP DPAS DPAS2 INT A B C D E F
    bash ./cp_res.sh "${name}" a b c d e f
  }

  run_one_fig21 "nvme0n1" 10 "FIG21_P41"
  run_one_fig21 "nvme2n1" 10 "FIG21_ZSSD"
  run_one_fig21 "nvme1n1" 30 "FIG21_Optane"

  bash ./cpuonoff.sh 1 19

  chown_outputs_to_invoker ./ycsb_*_results ./result_collection ./results ./out ./time_log

  trap - 0 1 2 3 15
  cd "${oldpwd}" || exit 1
}

main() {
  draft=0
  clean=0
  raw=0
  bgio_iops="${BGIO_IOPS:-${DPAS_BGIO_IOPS:-}}"

  while [ $# -gt 0 ]; do
    case "$1" in
      --draft)
        draft=1
        shift
        ;;
      --clean)
        clean=1
        shift
        ;;
      --raw)
        raw=1
        shift
        ;;
      --bgio-iops)
        bgio_iops="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "unknown option: $1"
        ;;
      *)
        if [ -z "${bgio_iops}" ]; then
          bgio_iops="$1"
          shift
        else
          die "unexpected extra argument: $1"
        fi
        ;;
    esac
  done

  require_root

  require_cmd bash
  require_cmd fio
  require_cmd python3
  require_cmd mkfs.xfs
  require_cmd mount
  require_cmd umount
  require_cmd modprobe
  require_cmd pgrep
  require_cmd sed
  require_cmd tee
  require_cmd findmnt
  require_cmd chown

  ensure_all_cpus_online

  # Auto-detect default NVMe devices if DPAS_DEVICE_LIST is not set.
  if [ -z "${DPAS_DEVICE_LIST:-}" ]; then
    DPAS_DEVICE_LIST=""
    for d in nvme0n1 nvme1n1 nvme2n1; do
      if [ -b "/dev/${d}" ]; then
        if [ -z "${DPAS_DEVICE_LIST}" ]; then
          DPAS_DEVICE_LIST="${d}"
        else
          DPAS_DEVICE_LIST="${DPAS_DEVICE_LIST},${d}"
        fi
      fi
    done
    [ -n "${DPAS_DEVICE_LIST}" ] || die "no NVMe block devices found among /dev/nvme0n1,/dev/nvme1n1,/dev/nvme2n1 (set DPAS_DEVICE_LIST explicitly)"
    export DPAS_DEVICE_LIST
  fi

  if [ "${draft}" -eq 1 ]; then
    export DPAS_DRAFT=1
    export DPAS_RUNTIME=5
    export DPAS_PRERUN_RUNTIME=5
    export DPAS_SLEEP_DROP=1
    export DPAS_SLEEP_AFTER_RUN=1
    export DPAS_SLEEP_AFTER_MODPROBE=1
    export DPAS_SLEEP_AFTER_UMOUNT=1
    export DPAS_IO_MODE="INT"
    export DPAS_BS_LIST="128"
    export DPAS_JOB_LIST="1"
    clean=1
  fi

  run_experiment "${SCRIPTS_DIR}/micro_128krr" 1 "${clean}" "${raw}"
  run_experiment "${SCRIPTS_DIR}/micro_4krr" 1 "${clean}" "${raw}"

  if [ -n "${bgio_iops}" ]; then
    case "${bgio_iops}" in
      *[!0-9]*)
        die "BGIO_IOPS must be an integer (got: ${bgio_iops})"
        ;;
    esac
    run_fig21_bg_ycsb "${bgio_iops}" "${draft}"
  else
    echo
    echo "[SKIP] FIG21 (BGIO + YCSB): BGIO_IOPS not provided."
    echo "       Run with e.g.: sudo ./run_all.sh --bgio-iops 5000"
  fi
}

main "$@"


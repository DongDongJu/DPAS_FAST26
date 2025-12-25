# DPAS_FAST26

This repository contains the artifact for the DPAS FAST'26 paper. The goal is **one-touch execution after cloning**, i.e., run everything with a single command: `sudo ./run_all.sh` (with automatic build steps when needed).

## Quick start (artifact evaluation: one-touch)

**Important**: The scripts **format NVMe devices (mkfs.xfs -f)** and mount/unmount them. Existing data on the target devices will be destroyed.

- **Run everything (microbenchmarks + Dynamic mode switching of DPAS (Fig. 20))** (BGIO IOPS is fixed to 1000):

```bash
sudo ./run_all.sh
```

- **Run microbenchmarks only**:

```bash
sudo ./run_all.sh --micro-only
```

- **Run macro only: Dynamic mode switching of DPAS (Fig. 20)** (BGIO IOPS is fixed to 1000):

```bash
sudo ./run_all.sh --macro-only
```

- **Quick smoke test (draft) + macro**:

```bash
sudo ./run_all.sh --draft
```

## What does it run?

- **Step 1 (`scripts/micro_4krr`)**: `./run.sh` → `python3 parse.py 1` → pretty summary output
- **Step 2 (`scripts/micro_128krr`)**: `./run.sh` → `python3 parse.py 1` → pretty summary output
- **Step 3 (`Dynamic mode switching of DPAS (Fig. 20)`, BGIO + YCSB, `scripts/`)**: runs by default with fixed BGIO IOPS=1000 (disable with `--no-fig21`)
  - CPU hotplug: `scripts/cpuonoff.sh`
  - BG I/O + YCSB: `scripts/bgio_noaffinity.sh`
  - Result collection: `scripts/cp_res.sh`

## Critical notes

- **Root is required**: the scripts use `mount/umount`, `modprobe`, `/proc/sys/vm/drop_caches`, `/sys/block/*`, and CPU hotplug.
- **CPU online (reproducibility)**: `utils/cpu on` is called at the beginning to online as many CPUs as possible (some environments may restrict hotplug).
- **Device naming**:
  - Microbenchmarks default to `nvme0n1,nvme1n1,nvme2n1` (can be overridden by env vars).
  - Macro scripts are written assuming `nvme0n1/nvme1n1/nvme2n1`.

## Dependencies (summary)

- **fio**
  - The microbenchmarks use `--ioengine=pvsync2`.
  - Verify `pvsync2` exists:

```bash
fio --version
fio --enghelp | grep -n pvsync2
```

- **Python 3 + numpy**: required for `scripts/*/parse.py` and `scripts/*/mean_std.py`
- **xfsprogs**: provides `mkfs.xfs`
- **Other utilities**: `mount`, `umount`, `modprobe`, `findmnt`, `pgrep`, `tee`, `sed`

## Installing fio 3.35 (from fio GitHub)

### Ubuntu/Debian example: build dependencies

```bash
sudo apt update
sudo apt install -y git build-essential pkg-config libaio-dev zlib1g-dev libnuma-dev liburing-dev
```

### Build/install fio 3.35

```bash
git clone https://github.com/axboe/fio.git
cd fio
git checkout fio-3.35
make -j"$(nproc)"
sudo make install
fio --version
```

### Verify `pvsync2` (required)

```bash
fio --enghelp | grep -n pvsync2
```

## Building dependencies for Dynamic mode switching of DPAS (Fig. 20) (BGIO+YCSB)

This macro experiment requires additional binaries: `io-generator`, RocksDB, and YCSB.

### Ubuntu/Debian packages (recommended)

```bash
sudo apt update
sudo apt install -y build-essential g++ make pkg-config \
  liburing-dev libbz2-dev zlib1g-dev libsnappy-dev liblz4-dev libzstd-dev
```

### One-shot build (recommended)

```bash
./scripts/build_fig21_deps.sh
```

### Manual build

- **1) io-generator (`scripts/io_gen.c`)**
  - `io-generator1..4` are symlinks to the same binary (used for process naming/pgrep).

```bash
gcc -O2 -D_GNU_SOURCE -pthread -o scripts/io-generator scripts/io_gen.c
ln -sf io-generator scripts/io-generator1
ln -sf io-generator scripts/io-generator2
ln -sf io-generator scripts/io-generator3
ln -sf io-generator scripts/io-generator4
```

If you see a `clock_gettime` link error on older systems:

```bash
gcc -O2 -D_GNU_SOURCE -pthread -lrt -o scripts/io-generator scripts/io_gen.c
```

- **2) RocksDB (modified)**

```bash
make -C apps/rocksdb_modi static_lib
```

- **3) YCSB (modified)**

```bash
make -C apps/YCSB-cpp-modi
```

### Ubuntu/Debian example: packages for macro build

```bash
sudo apt update
sudo apt install -y build-essential zlib1g-dev libsnappy-dev liblz4-dev libzstd-dev
```

## `run_all.sh` options

- `--draft`: quick smoke test (smaller sweep + shorter runtimes)
- `--clean`: delete `./parsed_data` and `./result_data` before each micro experiment
- `--raw`: print raw parsed output instead of pretty tables
- `--micro-only`: run only microbenchmarks (Step 1 & 2)
- `--macro-only`: run only `Dynamic mode switching of DPAS (Fig. 20)` (macro)
- `--no-fig21`: alias of `--micro-only`

## Outputs

- Microbenchmarks:
  - `scripts/micro_128krr/parsed_data/*`, `scripts/micro_128krr/result_data/*`
  - `scripts/micro_4krr/parsed_data/*`, `scripts/micro_4krr/result_data/*`
- Macro (Dynamic mode switching of DPAS (Fig. 20)):
  - `scripts/ycsb_*_results/`
  - `scripts/result_collection/*`

## Estimated runtime (reference)

- `micro_128krr`: ~35–45 min
- `micro_4krr`: ~20–30 min
- Total: ~55–75 min (varies by device/system/module load time)

## Troubleshooting

- **`fio: fio_setaffinity failed`**
  - Cause: affinity mismatch due to CPU count / cpuset/cgroup restrictions.
  - The scripts use `/proc/self/status` `Cpus_allowed_list` to reduce this issue.
- **Macro prompts for sudo / fails**
  - `run_all.sh` is designed to be executed as root; macro scripts treat `sudo` as a no-op when running as root.
- **`./run_all.sh: syntax error near unexpected token '('`**
  - If you are using an older revision of this artifact: this was typically caused by running bash-specific code via `sh`.
  - Current `run_all.sh` is POSIX `sh` compatible, so this error should not occur.

## Cleanup

If previous runs left root-owned output directories inside the repo, clean them up with:

```bash
sudo ./scripts/cleanup_artifact_tree.sh
```

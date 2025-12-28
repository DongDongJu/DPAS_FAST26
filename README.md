# DPAS FAST'26 Artifact

This repository contains the artifact accompanying our FAST'26 paper on DPAS.
It provides:

- **Microbenchmarks** (fio-based) under `scripts/micro_*`
- A **macro benchmark** (BGIO + YCSB + RocksDB) under `scripts/`
- One-touch runner: `sudo ./run_all.sh`

---

## Getting Started Instructions (≤ 30 minutes)

The goal of this section is a **kick-the-tires** check so reviewers can quickly verify that the artifact is functional.

### Safety / prerequisites (read first)

- **Data-destructive**: the scripts run `mkfs.xfs -f` on the target NVMe devices and mount/unmount them. **All existing data on the target devices will be destroyed.**
- **Root required**: the workflow uses `mount/umount`, `modprobe`, `/proc/sys/vm/drop_caches`, `/sys/block/*`, and CPU hotplug.
The kick-the-tires steps below use **microbench Step 1 only**, and do not require DPAS-specific sysfs knobs (macro-specific kernel requirements are covered in Detailed Instructions).

### Install dependencies for kick-the-tires (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install -y xfsprogs python3 python3-numpy
```

For microbenchmarks you also need **fio with `pvsync2`**. Verify:

```bash
fio --enghelp | grep -n pvsync2
```

### Kick-the-tires smoke test (Step 1 only: `micro_4krr`)

This runs a **small microbench** (4K random read) with **INT mode only** and a short runtime, then prints a readable table.
It is intended to finish quickly and catch obvious issues (dependencies, permissions, fio engine availability).

```bash
export DPAS_DEVICE_LIST=nvme0n1
export DPAS_IO_MODE=INT
export DPAS_JOB_LIST=1
export DPAS_RUNTIME=5

cd scripts/micro_4krr
sudo -E bash ./run.sh
python3 ./parse.py 1
python3 ../../utils/pretty_print.py ./parsed_data
```

**What to look for**

- The command prints an `[IOPS]` table and a `[CPU]` table.
- Files created under:
  - `scripts/micro_4krr/parsed_data/`
  - `scripts/micro_4krr/result_data/`

### Optional: one-touch smoke test (micro-only)

If you want a one-touch run that covers **both** micro steps (Step 1 and Step 2) with shortened parameters:

```bash
sudo ./run_all.sh --draft --micro-only
```

---

## Detailed Instructions

This section provides the evaluation road map and full documentation to reproduce the artifact results.

### Artifact claims (what this artifact enables)

**The claims below are concrete and testable in this repository.** Absolute performance numbers may differ across machines; the artifact is intended to reproduce the **reported trends** and produce the same **metrics** as in the paper.

- **Claim 1 (kernel interface availability)**: On a compatible kernel, block devices expose DPAS-related sysfs knobs under `/sys/block/<dev>/queue/` (e.g., `pas_enabled`, `ehp_enabled`, `switch_enabled`, `io_poll_delay`, `switch_param*`).
- **Claim 2 (microbench outputs)**: The microbenchmarks generate per-mode performance summaries (IOPS and latency percentiles) and write parsed outputs under:
  - `scripts/micro_4krr/parsed_data/*`, `scripts/micro_4krr/result_data/*`
  - `scripts/micro_128krr/parsed_data/*`, `scripts/micro_128krr/result_data/*`
- **Claim 3 (macro benchmark outputs)**: The macro benchmark produces, for each workload (A–F) and each mode (**CP/LHP/EHP/PAS/DPAS/INT**), the following metrics and stores them in collected files under `scripts/result_collection/`:
  - YCSB throughput (`ops/sec`)
  - average CPU utilization (`cpu`)
  - a derived “efficiency” metric (`ops/sec per cpu`) via `scripts/result_collection/pretty_macro.py`

### Evaluation road map

Recommended evaluation order:

1. **Environment validation**
   - Confirm kernel sysfs knobs exist for your test devices.
   - Confirm fio has `pvsync2` if you plan to run microbenchmarks.
2. **Kick-the-tires (≤ 30 minutes)**
   - Run the Step 1 (`scripts/micro_4krr`) smoke test in Getting Started.
3. **Full evaluation**
   - Run microbenchmarks (Step 1–2) and macro benchmark (Step 3) using `run_all.sh`.
   - Collect and inspect outputs; optionally re-run with different devices or shortened sweeps.

### Kernel requirement (important)

The scripts expect additional sysfs queue attributes (e.g., `pas_enabled`, `ehp_enabled`, `switch_enabled`).
These attributes are implemented in the kernel tree vendored under `./kernel/`.

**If these files do not exist under `/sys/block/<dev>/queue/`, the macro benchmark will fail.**

We provide the kernel source for reproducibility; however, building and booting a kernel is system-dependent and may take longer than the kick-the-tires phase.
At a minimum, the reviewer should ensure they are running a kernel that includes the changes under `kernel/block/blk-sysfs.c` and related files.

### One-touch runner (`run_all.sh`)

Run everything:

```bash
sudo ./run_all.sh
```

Run only microbenchmarks:

```bash
sudo ./run_all.sh --micro-only
```

Run only macro benchmark:

```bash
sudo ./run_all.sh --macro-only
```

Smoke test mode (shorter runtimes/sweeps):

```bash
sudo ./run_all.sh --draft
```

Options:

- `--draft`: quick smoke test (smaller sweep + shorter runtimes)
- `--clean`: delete `./parsed_data` and `./result_data` before each micro experiment
- `--raw`: print raw parsed output instead of pretty tables (also suppresses macro pretty table printing)
- `--micro-only`: run only microbenchmarks
- `--macro-only`: run only macro benchmark

### Microbenchmarks (how to interpret outputs)

Each micro benchmark directory contains:

- `run.sh`: runs fio across a sweep (devices/modes/jobs/sizes)
- `parse.py`: parses fio logs into `parsed_data/` and `result_data/`
- `utils/pretty_print.py`: prints compact tables in the terminal (used by `run_all.sh`)

You can override the sweep without editing scripts using environment variables:

- `DPAS_DEVICE_LIST` (comma-separated, e.g., `nvme0n1,nvme2n1`)
- `DPAS_IO_MODE` (comma-separated)
- `DPAS_BS_LIST` (comma-separated, micro_128krr)
- `DPAS_JOB_LIST` (comma-separated, micro_4krr)
- `DPAS_RUNTIME` and sleep-related knobs (`DPAS_SLEEP_*`)

### Macro benchmark (how to interpret outputs)

The macro benchmark runs BGIO + YCSB workloads and collects per-mode results.
`run_all.sh` prints a per-device summary table automatically (unless `--raw` is used).

To print a summary from already collected files:

```bash
python3 scripts/result_collection/pretty_macro.py FIG20_P41 --dir scripts/result_collection
```

**Note (recommended for reviewers)**:
`pretty_macro.py` is intended as a **quick sanity-check** in the CLI (per-workload `ops` and `cpu avg`).
For the final verification / plotting step, we recommend copying the values from the collected files
(`scripts/result_collection/<PREFIX>_<workload>.txt`) into a spreadsheet (e.g., Excel) to avoid ambiguity.

### Expected runtime (reference)

- **Kick-the-tires smoke test**: typically well under 30 minutes.
- **Microbenchmarks** (full sweep): ~55–75 min total (device/system dependent).
- **Macro benchmark**: can take **significantly longer** depending on workloads, device speed, and module load times.

### Troubleshooting

- **`fio: fio_setaffinity failed`**
  - Cause: cpuset/cgroup CPU constraints.
  - Mitigation: scripts use `/proc/self/status` `Cpus_allowed_list`, but very restrictive environments may still fail.
- **Macro run prints `environment: line 1: ... Killed`**
  - Usually an OOM kill or external watchdog kill.
  - Check `dmesg` for OOM messages; try `--draft`, reduce the set of modes/workloads, and ensure sufficient RAM/swap.

### Cleanup

If previous runs left root-owned output directories inside the repo:

```bash
sudo ./scripts/cleanup_artifact_tree.sh
```

#!/usr/bin/env python3
"""
Pretty-print macrobench results collected by scripts/cp_res.sh.

Input format:
  scripts/result_collection/<PREFIX>_<workload>.txt
where each file contains repeated blocks like:
  <MODE_LABEL>
  ycsb
  ops/sec: <value>
  ...
  cpu: <value>
  ===============

This script keeps experiment flow unchanged: it only reads existing outputs.
"""

from __future__ import annotations

import argparse
import os
import re
import statistics
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple


MODE_NORMALIZE: Dict[str, str] = {
    # old labels (legacy)
    "Polling": "CP",
    "Hybrid-polling": "LHP",
    "Interrupt": "INT",
    # current labels
    "CP": "CP",
    "LHP": "LHP",
    "EHP": "EHP",
    "PAS": "PAS",
    "DPAS": "DPAS",
    "DPAS2": "DPAS2",
    "INT": "INT",
}

KNOWN_MODE_TOKENS = set(MODE_NORMALIZE.keys())


OPS_RE = re.compile(r"^ops/sec:\s*([0-9]+(?:\.[0-9]+)?)\s*$")
CPU_RE = re.compile(r"^cpu:\s*([0-9]+(?:\.[0-9]+)?)\s*$")
SEP_RE = re.compile(r"^=+\s*$")


@dataclass(frozen=True)
class Entry:
    ops: Optional[float]
    cpu: Optional[float]


def _format_num(v: Optional[float], kind: str) -> str:
    if v is None:
        return "NA"
    if kind == "ops":
        # e.g., 62371.4 -> 62.4k
        if v >= 1_000_000:
            return f"{v/1_000_000:.2f}M"
        if v >= 10_000:
            return f"{v/1_000:.1f}k"
        if v >= 1_000:
            return f"{v/1_000:.2f}k"
        return f"{v:.0f}"
    if kind == "cpu":
        return f"{v:.2f}"
    if kind == "ratio":
        return f"{v:.0f}"
    return str(v)


def _table(header: List[str], rows: List[List[str]]) -> str:
    widths = [len(h) for h in header]
    for r in rows:
        for i, c in enumerate(r):
            widths[i] = max(widths[i], len(c))

    def fmt_row(r: List[str]) -> str:
        out = []
        for i, c in enumerate(r):
            if i == 0:
                out.append(c.ljust(widths[i]))
            else:
                out.append(c.rjust(widths[i]))
        return "  ".join(out)

    sep = "  ".join("-" * w for w in widths)
    return "\n".join([fmt_row(header), sep] + [fmt_row(r) for r in rows])


def _stats(values: List[float]) -> Tuple[float, float, float, float]:
    values_sorted = sorted(values)
    mean = statistics.fmean(values_sorted)
    med = statistics.median(values_sorted)
    lo = values_sorted[0]
    hi = values_sorted[-1]
    return mean, med, lo, hi


def parse_file(path: str) -> Dict[str, Entry]:
    """
    Returns a mapping:
      normalized_mode -> Entry(ops, cpu)
    """
    out: Dict[str, Entry] = {}
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = [ln.rstrip("\n") for ln in f]

    i = 0
    while i < len(lines):
        token = lines[i].strip()
        if not token:
            i += 1
            continue
        if token == "ycsb" or OPS_RE.match(token) or CPU_RE.match(token) or SEP_RE.match(token):
            # Not a block header; skip.
            i += 1
            continue

        raw_mode = token
        mode = MODE_NORMALIZE.get(raw_mode, raw_mode)
        ops: Optional[float] = None
        cpu: Optional[float] = None

        i += 1
        while i < len(lines):
            ln = lines[i].strip()
            # Some collected files may miss the "====" separator between blocks.
            # If we see the next mode header, stop the current block without
            # consuming that line so it can be parsed as the next block.
            if ln in KNOWN_MODE_TOKENS and ln != "ycsb":
                break
            m_ops = OPS_RE.match(ln)
            if m_ops:
                ops = float(m_ops.group(1))
                i += 1
                continue
            m_cpu = CPU_RE.match(ln)
            if m_cpu:
                cpu = float(m_cpu.group(1))
                i += 1
                continue
            if SEP_RE.match(ln):
                i += 1
                break
            i += 1

        out[mode] = Entry(ops=ops, cpu=cpu)

    return out


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Pretty-print macrobench result_collection files as tables."
    )
    ap.add_argument("prefix", help="Prefix such as MACRO_P41 (reads <prefix>_*.txt)")
    ap.add_argument(
        "--dir",
        default=os.path.dirname(__file__),
        help="Directory containing <prefix>_*.txt (default: this script's directory)",
    )
    ap.add_argument(
        "--keep-legacy-names",
        action="store_true",
        help="Keep legacy naming (show DPAS/DPAS2 as-is; no paper label mapping).",
    )
    args = ap.parse_args()

    base_dir = os.path.abspath(args.dir)
    if not os.path.isdir(base_dir):
        raise SystemExit(f"[ERR] not a directory: {base_dir}")

    prefix = args.prefix
    files: List[Tuple[str, str]] = []
    for name in sorted(os.listdir(base_dir)):
        if not name.startswith(prefix + "_") or not name.endswith(".txt"):
            continue
        workload = name[len(prefix) + 1 : -4]  # between "_" and ".txt"
        files.append((workload, os.path.join(base_dir, name)))

    if not files:
        print(f"[ERR] no files found for prefix '{prefix}' in {base_dir}")
        print(f"      expected: {os.path.join(base_dir, prefix + '_<workload>.txt')}")
        return 2

    # workload -> mode -> Entry
    data: Dict[str, Dict[str, Entry]] = {}
    modes_seen: List[str] = []
    for workload, path in files:
        parsed = parse_file(path)
        data[workload] = parsed
        for m in parsed.keys():
            if m not in modes_seen:
                modes_seen.append(m)

    # Normalize mode ordering to the paper-friendly order.
    default_order = ["CP", "LHP", "EHP", "PAS", "DPAS", "DPAS2", "INT"]
    modes_ordered = [m for m in default_order if m in modes_seen] + [m for m in modes_seen if m not in default_order]
    workloads_ordered = sorted([w for w, _ in files])

    # Auto-detect whether the collected files already use the new paper labels.
    # If PAS exists as a mode label, we assume the new mapping is already applied
    # in the result files (so we must NOT remap DPAS -> PAS).
    has_pas_label = "PAS" in modes_seen

    def display_mode(m: str) -> str:
        if args.keep_legacy_names:
            return m
        # Paper label mapping requested:
        #   DPAS -> PAS, DPAS2 -> DPAS (legacy files only).
        if not has_pas_label:
            if m == "DPAS":
                return "PAS"
        if m == "DPAS2":
            return "DPAS"
        return m

    # Build tables.
    #
    # NOTE: For macrobench, workloads A-F are different workloads. Showing mean/min/max
    # across A-F can be misleading, so we only show per-workload values for ops.
    ops_header = ["MODE"] + [w.upper() for w in workloads_ordered]
    ops_rows: List[List[str]] = []
    cpu_header = ["MODE"] + [w.upper() for w in workloads_ordered]
    cpu_rows: List[List[str]] = []

    for mode in modes_ordered:
        ops_vals: List[float] = []
        cpu_vals: List[float] = []

        ops_cells: List[str] = []
        cpu_cells: List[str] = []

        for w in workloads_ordered:
            e = data.get(w, {}).get(mode)
            if e is None:
                ops_cells.append("NA")
                cpu_cells.append("NA")
                continue

            if e.ops is not None:
                ops_vals.append(e.ops)
            if e.cpu is not None:
                cpu_vals.append(e.cpu)

            ops_cells.append(_format_num(e.ops, "ops"))
            cpu_cells.append(_format_num(e.cpu, "cpu"))

        ops_rows.append([display_mode(mode)] + ops_cells)
        cpu_rows.append([display_mode(mode)] + cpu_cells)

    print(f"== Macrobench summary: {prefix} ==")
    print()
    print("[ops]")
    print(_table(ops_header, ops_rows))
    print()
    print("[cpu avg]")
    print(_table(cpu_header, cpu_rows))
    print()
    print(f"Files: {', '.join([prefix + '_' + w + '.txt' for w in workloads_ordered])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


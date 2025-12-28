#!/usr/bin/env python3

import os
import sys
from typing import List, Tuple


def _read_lines(path: str) -> List[str]:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read().splitlines()


Section = Tuple[str, List[str], List[List[str]]]


def parse_sections(lines: List[str]) -> List[Section]:
    sections: List[Section] = []
    i = 0
    while i < len(lines):
        token = lines[i].strip()
        if token in ("IOPS", "CPU"):
            metric = token
            i += 1
            while i < len(lines) and not lines[i].strip():
                i += 1
            if i >= len(lines):
                break
            header = lines[i].split()
            i += 1
            rows: List[List[str]] = []
            while i < len(lines) and lines[i].strip():
                rows.append(lines[i].split())
                i += 1
            sections.append((metric, header, rows))
        else:
            i += 1
    return sections


def _format_table(header: List[str], rows: List[List[str]]) -> str:
    cols = len(header)
    normalized: List[List[str]] = []
    for r in rows:
        if len(r) < cols:
            r = r + [""] * (cols - len(r))
        elif len(r) > cols:
            r = r[:cols]
        normalized.append(r)

    widths = [len(h) for h in header]
    for r in normalized:
        for c in range(cols):
            widths[c] = max(widths[c], len(r[c]))

    def fmt_row(r: List[str]) -> str:
        out = []
        for idx, cell in enumerate(r):
            # left align first column, right align others
            if idx == 0:
                out.append(cell.ljust(widths[idx]))
            else:
                out.append(cell.rjust(widths[idx]))
        return " | ".join(out)

    sep = "-+-".join("-" * w for w in widths)
    out_lines = [fmt_row(header), sep]
    out_lines += [fmt_row(r) for r in normalized]
    return "\n".join(out_lines)


def _bar(value: float, vmax: float, width: int = 18) -> str:
    if vmax <= 0:
        return ""
    n = int(round((value / vmax) * width))
    n = max(0, min(width, n))
    # Use ASCII-only bars for maximum terminal compatibility.
    return "#" * n + " " * (width - n)


def _try_float(s: str):
    try:
        return float(s)
    except Exception:
        return None


def print_summary(metric: str, header: List[str], rows: List[List[str]]) -> None:
    # Show a compact per-mode bar chart for the first row if possible.
    if not rows or len(header) < 2:
        return
    first = rows[0]
    if len(first) < 2:
        return
    labels = header[1:]
    values = []
    for j in range(1, len(header)):
        v = _try_float(first[j]) if j < len(first) else None
        if v is None:
            v = 0.0
        values.append(v)
    vmax = max(values) if values else 0.0

    row_key = header[0] if header else "Row"
    title = f"{metric} (Summary for {row_key}={first[0]})"
    print(title)
    for label, v in zip(labels, values):
        b = _bar(v, vmax)
        print(f"  {label:>6}  {v:>10g}  {b}")


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: pretty_print.py <parsed_data_dir_or_file>", file=sys.stderr)
        return 2

    target = sys.argv[1]
    files: List[str] = []
    if os.path.isdir(target):
        for name in sorted(os.listdir(target)):
            if name.endswith(".txt"):
                files.append(os.path.join(target, name))
    else:
        files = [target]

    if not files:
        print("[WARN] no .txt files found to print", file=sys.stderr)
        return 0

    for path in files:
        print()
        print(f"== {os.path.basename(path)} ==")
        lines = _read_lines(path)
        sections = parse_sections(lines)
        if not sections:
            print("(no IOPS/CPU sections found)")
            continue
        for metric, header, rows in sections:
            print()
            print(f"[{metric}]")
            print(_format_table(header, rows))
            print()
            print_summary(metric, header, rows)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())


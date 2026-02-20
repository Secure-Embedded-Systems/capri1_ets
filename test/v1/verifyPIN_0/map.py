#!/usr/bin/env python3
"""
map.py — Map scan bits to scan-layout signals in *reverse* order.

Rule: last bit of scan → first signal; ... ; first bit of scan → last signal.

Input:
  --bits   <path>   Path to a text file containing 0/1 characters (others ignored)
  --layout <path>   Path to a layout file with one signal per line
Output:
  --out    <path>   Path to write map.out (TSV: idx<TAB>signal<TAB>val), default: map.out

Example:
  python3 map.py --bits scan_dump_bits_12756_v1.txt --layout scan_layout_z_removed --out map.out

Notes:
- If bit count and layout line count differ, the shorter length is used (warned).
- Lines in the layout that are empty or whitespace-only are ignored.
"""
import argparse
import re
from pathlib import Path

def load_bits(p: Path):
    s = p.read_text(errors="ignore")
    s = re.sub(r"[^01]", "", s)  # keep only 0/1
    return [int(ch) for ch in s]

def load_layout(p: Path):
    lines = [ln.rstrip("\r\n") for ln in p.read_text(errors="ignore").splitlines()]
    lines = [ln for ln in lines if ln.strip() != ""]
    return lines

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bits", required=True, help="bit dump file (0/1 chars)")
    ap.add_argument("--layout", required=True, help="scan layout file (one signal per line)")
    ap.add_argument("--out", default="map.out", help="output file (TSV)")
    args = ap.parse_args()

    bits = load_bits(Path(args.bits))
    layout = load_layout(Path(args.layout))

    if len(bits) == 0:
        raise SystemExit("ERROR: no bits found in --bits")
    if len(layout) == 0:
        raise SystemExit("ERROR: no lines found in --layout")

    # Reverse as requested: last bit → first signal
    bits_rev = list(reversed(bits))

    n = min(len(bits_rev), len(layout))
    if len(bits_rev) != len(layout):
        print(f"WARNING: bit count ({len(bits_rev)}) != layout count ({len(layout)}). Using n={n} pairs.")

    outp = Path(args.out)
    with outp.open("w", encoding="utf-8") as f:
        f.write("# idx\tsignal\tval\n")
        for i in range(n):
            f.write(f"{i}\t{layout[i]}\t{bits_rev[i]}\n")

    print(f"Wrote {n} mappings to {outp} (reverse mapping: last bit → first signal).")
    print(f"  bits file  : {args.bits} (len={len(bits)})")
    print(f"  layout file: {args.layout} (lines={len(layout)})")

if __name__ == "__main__":
    main()


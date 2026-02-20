#!/usr/bin/env python3
import os
import sys
import subprocess

# --- Config (edit if needed) ---
START, END = 1, 9
LAYOUT_FILE = "scan_layout_z_removed.txt"  # change if your layout filename differs
MAP_SCRIPT = "map.py"
GROUP_SCRIPT = "group.py"

PY = sys.executable or "python3"

def run(cmd):
    print(">", " ".join(cmd))
    subprocess.run(cmd, check=True)

def main():
    for i in range(START, END + 1):
        bits = f"frame_{i}.txt"
        map_out = f"frame_{i}_map.out"
        outdir = f"frame_{i}"

        if not os.path.exists(bits):
            print(f"[skip] {bits} not found")
            continue

        run([PY, MAP_SCRIPT, "--bits", bits, "--layout", LAYOUT_FILE, "--out", map_out])
        os.makedirs(outdir, exist_ok=True)
        run([PY, GROUP_SCRIPT, "--map", map_out, "--outdir", outdir])

        print(f"[done] {bits} -> {map_out} -> {outdir}/")

if __name__ == "__main__":
    main()


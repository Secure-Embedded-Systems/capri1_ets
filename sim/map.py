#!/usr/bin/env python3
import csv
import sys

# ─── User‐adjustable constants ───────────────────────────────────────────────────────────
EXPECTED_COUNT = 12756
SCANDEF_PATH   = "./chip.scanDEF"
SCAN_DUMP_PATH = "./scan_dump.txt"
OUTPUT_CSV     = "signal_bit_mapping.csv"

# ─── 1. Parse the .scanDEF and collect all lines containing "( IN SI )" and "( OUT Q )"
signals = []
try:
    with open(SCANDEF_PATH, 'r') as f:
        for line in f:
            line = line.strip()
            if "( IN SI )" in line and "( OUT Q )" in line:
                # Everything before the first "(" is the full signal name
                sig_name = line.split('(')[0].strip()
                signals.append(sig_name)
except FileNotFoundError:
    print(f"Error: Could not open '{SCANDEF_PATH}'. Make sure the path/filename is correct.")
    sys.exit(1)

# Reverse so bottom‐of‐file signal → bit 0, next → bit 1, etc.
reversed_signals = list(reversed(signals))
num_signals = len(reversed_signals)

# Check the expected count of signals
if num_signals != EXPECTED_COUNT:
    print(f"Error: Expected {EXPECTED_COUNT} signals in '{SCANDEF_PATH}', but found {num_signals}.")
    print("Please verify your .scanDEF file.")
    sys.exit(1)

# ─── 2. Read scan_dump.txt and keep '0', '1', or 'x'/'X'
try:
    with open(SCAN_DUMP_PATH, 'r') as f:
        content = f.read().strip()
except FileNotFoundError:
    print(f"Error: Could not open '{SCAN_DUMP_PATH}'. Make sure the path/filename is correct.")
    sys.exit(1)


bits_raw = content.strip() 

# Keep only '0', '1', 'x', or 'X' characters
bits = "".join(c for c in bits_raw if c in "01xX")
bits = bits.lower()  # normalize to lowercase 'x'
num_bits = len(bits)

# Check the expected count of bits
if num_bits != EXPECTED_COUNT:
    print(f"Error: Expected {EXPECTED_COUNT} bits in '{SCAN_DUMP_PATH}', but extracted {num_bits}.")
    print("Please verify your scan_dump.txt (it must contain exactly 13 085 characters of 0/1/x).")
    sys.exit(1)


# ─── 3. Write CSV: Signal,Bit Index,Value for all 12756 entries
try:
    with open(OUTPUT_CSV, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["Signal", "Bit Index", "Value"])
        for i in range(EXPECTED_COUNT):
            writer.writerow([reversed_signals[i], i, bits[i]])

    print(f"Successfully saved full mapping ({EXPECTED_COUNT} entries) to '{OUTPUT_CSV}'.\n")
    print("Here are the first 10 lines as a preview:")
    with open(OUTPUT_CSV, 'r') as preview:
        for _ in range(11):  # header + 10 data lines
            line = preview.readline()
            if not line:
                break
            print(line.strip())
except IOError as e:
    print(f"Error writing to '{OUTPUT_CSV}': {e}")
    sys.exit(1)


#!/usr/bin/env python3
import sys

def chunk_bits(bits, size):
    """Split bits into chunks of up to `size` (last one may be shorter)."""
    return [bits[i:i+size] for i in range(0, len(bits), size)]

def bits_to_hex128(bits128):
    """Convert a 128-bit string into a 32-hex-digit string with underscores every 32 bits."""
    h = hex(int(bits128, 2))[2:].upper().zfill(32)
    return '_'.join(h[i:i+8] for i in range(0, 32, 8))

def print_128_lines(bits):
    """Print 128-bit lines with 4×32-bit chunks + hex summary."""
    for line in chunk_bits(bits, 128):
        if len(line) == 128:
            chunks = chunk_bits(line, 32)
            print(' '.join(chunks), bits_to_hex128(line))
        else:
            print(line)

def main():
    if len(sys.argv) not in (2, 3):
        print(f"Usage: {sys.argv[0]} <bitfile> [output_file]")
        sys.exit(1)

    bitfile = sys.argv[1]
    outfile = sys.argv[2] if len(sys.argv) == 3 else None

    # If an output filename is provided, redirect stdout there
    if outfile:
        sys.stdout = open(outfile, 'w')

    # Read and preprocess bits
    with open(bitfile, 'r') as f:
        raw = f.read()
    bits = ''.join(raw.split())
    if len(bits) < 12756:
        sys.exit(f"Error: only found {len(bits)} bits, need ≥12756")

    idx = 0

    # 1) Core & peripheral regs
    print("----Core and peripheral reg bits --------")
    regs = bits[idx:idx+4495]; idx += 4495
    print_128_lines(regs)
    print()

    # 2) Data memory
    print("----data memory--------")
    print(bits[idx]); idx += 1
    print(bits[idx:idx+32]); idx += 32
    data = bits[idx:idx+4096]; idx += 4096
    print_128_lines(data)
    print()

    # 3) Program memory
    print("-----program memory-------")
    print(bits[idx]); idx += 1
    print(bits[idx:idx+32]); idx += 32
    prog = bits[idx:idx+4096]; idx += 4096
    print_128_lines(prog)
    print()

    # 4) Final bits
    print("------------")
    print(bits[idx:idx+3])

if __name__ == "__main__":
    main()



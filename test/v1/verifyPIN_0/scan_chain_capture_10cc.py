#!/usr/bin/env python3
import pigpio
import time
import sys

# GPIO pin assignments (BCM numbering)
CLK = 12    # Clock pin for stepping the cycle
FETCH = 22  # Fetch pin (used to trigger capture of certain data, if applicable)
S_EN = 20   # Scan Enable pin
S_MODE = 21 # Scan Mode pin
TDI = 16    # Test Data In (scan chain input)
TDO = 7     # Test Data Out (scan chain output)

# Configuration
CHAIN_LENGTH = 12756   # number of bits in the scan chain
NUM_CYCLES   = 10      # number of clock cycles to capture (frames)

# Initialize pigpio and set up GPIO modes
pi = pigpio.pi()  # Connect to local pigpio daemon (must be running)
if not pi.connected:
    print("Error: pigpio daemon is not running or connection failed.")
    sys.exit(1)

# Configure GPIO directions
pi.set_mode(CLK, pigpio.OUTPUT)
pi.set_mode(FETCH, pigpio.OUTPUT)
pi.set_mode(S_EN, pigpio.OUTPUT)
pi.set_mode(S_MODE, pigpio.OUTPUT)
pi.set_mode(TDI, pigpio.OUTPUT)
pi.set_mode(TDO, pigpio.INPUT)

# Initialize output pins to default states
pi.write(CLK, 0)     # clock low
pi.write(FETCH, 0)   # fetch low (inactive)
pi.write(S_EN, 0)    # scan enable low (functional mode)
pi.write(S_MODE, 0)  # scan mode low (functional mode)
pi.write(TDI, 0)     # TDI low (idle)

# Loop over each program clock cycle (frame) to capture
for frame in range(NUM_CYCLES):
    # 1. Functional capture phase: pulse the clock once with scan disabled
    pi.write(S_EN, 0)   # ensure scan chain is in capture (functional) mode
    pi.write(S_MODE, 0)
    time.sleep(1e-6)    # small delay for stability
    # Pulse the clock (rising edge followed by falling edge)
    pi.write(CLK, 1)
    time.sleep(1e-6)    # 1 µs high pulse
    pi.write(CLK, 0)
    time.sleep(1e-6)    # 1 µs low to complete the cycle

    # 2. Scan shift phase: enable scan mode and shift out captured data
    pi.write(S_MODE, 1)  # enable scan mode (scan chain ready to shift)
    pi.write(S_EN, 1)    # enable scan shifting (if required by design)
    time.sleep(1e-6)
    bits = []            # list to collect bits for this frame
    for i in range(CHAIN_LENGTH):
        # Read the current bit at TDO (scan output)
        bit_val = pi.read(TDO)
        # Feed the bit back into TDI (scan input) to preserve chain content
        pi.write(TDI, bit_val)
        # Store the bit value ('0' or '1') in our list
        bits.append('1' if bit_val == 1 else '0')
        time.sleep(1e-6)  # brief delay after reading and setting TDI
        # Pulse clock to shift the next bit into TDO
        pi.write(CLK, 1)
        time.sleep(1e-6)
        pi.write(CLK, 0)
        # (After this pulse, the next bit in the chain moves into TDO)
    # End of shifting loop

    # 3. Save the captured scan chain bits to a file for this frame
    bit_string = ''.join(bits)
    filename = f"frame_{frame}.txt"
    with open(filename, 'w') as f:
        f.write(bit_string + "\n")
    print(f"Captured frame {frame} -> {filename}")

    # 4. Reset scan control signals to capture mode for the next cycle
    pi.write(S_EN, 0)
    pi.write(S_MODE, 0)
    # (Now ready to capture the next cycle)
# End of capture loop

# Cleanup: set pins to a safe state and close pigpio connection
pi.write(CLK, 0)
pi.write(TDI, 0)
pi.write(FETCH, 0)
pi.write(S_EN, 0)
pi.write(S_MODE, 0)
pi.stop()


# CAPRI-1 — ETS 2026: EMFI Analysis with Scan Chain Observability

This repository contains the **software, RTL, simulation scripts, and physical test data** for the CAPRI-1 RISC-V SoC, supporting the work presented at **ETS 2026** (European Test Symposium).

> **Note:** Synthesis netlists, standard cell libraries, place-and-route scripts, and other foundry-specific content are excluded due to NDA restrictions. Only RTL-level simulation is supported from this repository.

## Overview

CAPRI-1 is a CROC-based SoC featuring a **CVE2 (Ibex-class) RISC-V core** (RV32I + Zicsr), fabricated in a 180nm process. The chip integrates a **12,756-bit scan chain** that provides full internal state observability of the processor pipeline, register file, DFF-based SRAM, and CSRs.

Two VerifyPIN workloads were ported to the chip for **Electromagnetic Fault Injection (EMFI)** analysis:

- **vp0icp** — VerifyPIN_0: baseline PIN comparison without countermeasures
- **vp7icp** — VerifyPIN_7: PIN comparison hardened with six countermeasure layers (HB+FTL+INL+DPTC+DT+SC)

Fault effects were analysed cycle-by-cycle through the integrated scan chain, providing full internal state observability after each injected fault.

> See [CAPRI1.md](CAPRI1.md) for detailed pin mapping and architecture diagrams.
> See [ETS2026.pdf](ETS2026.pdf) for the EMFI experimental setup and analysis results.
> See [CAPRI1_verifyPIN0.pdf](CAPRI1_verifyPIN0.pdf) for VerifyPIN_0 execution trace analysis.

## Repository Structure

```
capri1_ets/
├── README.md
├── CAPRI1.md                   # Chip pin details, architecture, simulation flow
├── ETS2026.pdf                 # ETS 2026 paper (EMFI setup & results)
├── CAPRI1_verifyPIN0.pdf       # VerifyPIN_0 execution trace analysis
├── rtl/                        # RTL source files
│   ├── cve2/                   # CVE2 (Ibex) RISC-V core (RV32I)
│   ├── apb_uart/               # APB UART peripheral
│   ├── gpio/                   # GPIO controller
│   ├── timer_unit/             # Timer peripheral
│   ├── obi/                    # OBI interconnect
│   ├── riscv-dbg/              # RISC-V debug module (JTAG)
│   ├── common_cells/           # Common utility cells
│   ├── ro/                     # Ring oscillator module
│   ├── croc_soc.sv             # SoC top-level
│   ├── croc_domain.sv          # Clock/reset domain
│   └── user_domain.sv          # User expansion domain
├── sim/                        # Simulation environment
│   ├── Makefile                # RTL simulation targets
│   ├── tb_chip.sv              # Chip-level testbench
│   ├── chip.flist              # File list for compilation
│   ├── chip.scanDEF            # Scan chain layout definition
│   ├── wave.do                 # Waveform script
│   ├── map.py                  # Scan chain bit → signal mapping
│   ├── parse.py                # Scan dump parser
│   └── scan_out/               # Sample per-cycle state dumps
├── sw/                         # Software test programs
│   ├── Makefile                # Build system
│   ├── soc/                    # Startup (crt0.S), linker script (link.ld)
│   ├── lib/                    # Peripheral drivers (UART, GPIO, Timer)
│   ├── vp0icp/                 # VerifyPIN_0 source
│   ├── vp7icp/                 # VerifyPIN_7 source (with countermeasures)
│   ├── helloworld/             # Basic hello world test
│   ├── mul_uart_byte/          # Multiply + UART TX test
│   └── bin/                    # Pre-compiled hex files
└── test/                       # Physical chip testing
    └── v1/                     # Bring-up & scan capture scripts
        ├── prep_pins.sh        # GPIO/PWM pin configuration
        ├── rpi3_gpio.cfg       # OpenOCD Raspberry Pi adapter config
        ├── capri1_target.cfg   # OpenOCD CAPRI1 JTAG target config
        └── verifyPIN_0/        # Scan capture results & analysis scripts
```

## Prerequisites

- **ModelSim/QuestaSim** (vlog, vsim) — for RTL simulation
- **RISC-V GCC toolchain** (`riscv64-unknown-elf-gcc`) — for compiling test programs
- **Python 3** — for scan chain mapping/parsing scripts
- **Raspberry Pi 3/4** with `pigpio`, `raspi-gpio`, OpenOCD — for physical chip testing

## Quick Start

### 1) Build a Test Program

```bash
cd sw/
make PROGRAM=vp0icp    # generates .hex in sw/bin/
```

Available programs: `vp0icp`, `vp7icp`, `mul_uart_byte`, `helloworld`

### 2) Run RTL Simulation

```bash
cd sim/
make chip_sim_rtl PROGRAM=vp0icp
```

This compiles the RTL, loads the hex binary via JTAG into SRAM, runs for 190 clock cycles, and dumps per-cycle internal state to `scan_out/`.

### 3) Map Scan Chain Data

```bash
cd sim/
make map
```

Maps scan dump bits to RTL signal names using `chip.scanDEF`.

## Test Programs (ETS 2026 Workloads)

### vp0icp — VerifyPIN_0 (Baseline)

Basic PIN verification **without countermeasures**:
- User PIN: `{0x01, 0x02, 0x03, 0x04}`
- Card PIN: `{0x01, 0x02, 0x03, 0x05}` (last byte differs)
- Expected result: `ret = 1` (PIN mismatch) at DMEM `0x10000200`
- Under EMFI: faults can bypass comparison, granting unauthorized authentication

### vp7icp — VerifyPIN_7 (Hardened)

PIN verification **with six countermeasure layers**:
- **HB** — Hardened Byte comparison (constant-time)
- **FTL** — Fault Tolerance Logic (redundant checks)
- **INL** — Instruction-level countermeasures
- **DPTC** — Double-check PTC (redundant counter verification)
- **DT** — Data Transform (encoded internal representation)
- **SC** — Step Counter (execution flow integrity)

## Per-Cycle State Dump Format

Each cycle file in `sim/scan_out/` contains:
- **IMEM/DMEM**: Instruction and data memory contents (128 words each)
- **GPRs**: Register file x0–x31
- **IF Stage**: Instruction registers, prefetch buffer state
- **ID Stage**: FSM state, controller state, branch logic
- **LSU**: Load/store unit state
- **CSRs**: mtval, mepc, mcause, mtvec, mstatus, mcycle, etc.
- **OBI**: Demux select and counter state
- **GPIO**: Enable, direction, output registers

## Physical Chip Testing

See `test/v1/` for Raspberry Pi-based JTAG bring-up and scan chain capture scripts. Details in [CAPRI1.md](CAPRI1.md).

## Technology

- **Core**: CVE2 (Ibex-class), RV32I with Zicsr
- **SRAM**: 2 banks x 128 words (IMEM + DMEM), DFF-based (scan-visible)
- **Scan chain**: 12,756 bits
- **UART**: 115200 baud
- **JTAG ID**: `0x0c0c5db3`

## What's Excluded (NDA)

The following are **not included** due to foundry NDA restrictions:
- Standard cell library files and Verilog models
- Synthesis scripts and gate-level netlists (Cadence Genus)
- Place-and-route data (Cadence Innovus)
- STA scripts and timing reports
- SDF timing annotation files
- Chip-level pad ring wrapper (`chip.sv` references foundry I/O pad cells)

## Citation

If you use this work, please cite the ETS 2026 paper (see [ETS2026.pdf](ETS2026.pdf)).

## License

RTL components (CVE2, CROC, common_cells, OBI, etc.) retain their original open-source licenses. Software and test scripts in this repository are provided for academic and research use.

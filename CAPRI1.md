# CAPRI‑1 —  Notes

This document describes the CAPRI‑1.

---
<img width="673" height="565" alt="image" src="https://github.com/user-attachments/assets/9833937a-efc8-4b64-8279-bec8b3141cfe" />

## Pin details (pad ring overview)

**Conventions**
- `_i` = input, `_o` = output, `_n`/`_ni` = active‑low.
- Power/ground pads are distributed on every side: **VDDIO, VDD, VSSIO, VSS**.
- Pads marked “Unused” are reserved.

### Top side
| Pad    | Signal        | Dir   | Notes |
|:------:|:--------------|:-----:|:------|
| Top_0  | `clk_i`       | In    | Main core clock |
| Top_1  | `rst_ni`      | In    | Global reset, active‑low |
| Top_2  | `scan_en_i`   | In    | Scan enable |
| Top_3  | `scan_mode_i` | In    | Scan mode select |
| Top_4  | `ref_clk_i`   | In    | Reference clock |
| Top_5  | `tdi_i`       | In    | **Scan chain** serial input |
| Top_6  | `tdo_o`       | Out   | **Scan chain** serial output |
| Top_7–Top_11 | —       | —     | Unused |

### Left side
| Pad    | Signal          | Dir | Notes |
|:------:|:----------------|:---:|:------|
| Left_0 | `jtag_tck_i`    | In  | JTAG clock |
| Left_1 | `jtag_trst_ni`  | In  | JTAG reset, active‑low |
| Left_2 | `jtag_tms_i`    | In  | JTAG mode select |
| Left_3 | `jtag_tdi_i`    | In  | JTAG data input |
| Left_4 | `uart_rx_i`     | In  | UART RX |
| Left_5 | `fetch_en_i`    | In  | Core fetch enable / boot control |
| Left_6–Left_11 | —       | —   | Unused |

### Right side (RO/test interface)
| Pad     | Signal          | Dir | Notes |
|:-------:|:----------------|:---:|:------|
| Right_0 | `ro_clk`        | In  | RO domain clock |
| Right_1 | `ro_rst_n`      | In  | RO reset, active‑low |
| Right_2 | `ro_ce_n`       | In  | RO clock enable, active‑low |
| Right_3 | `ro_en`         | In  | RO enable |
| Right_4 | `ro_chain_i`    | In  | RO chain input |
| Right_5 | `ro_data_d[0]`  | In  | Drive/config data |
| Right_6 | `ro_data_d[1]`  | In  | Drive/config data |
| Right_7 | `ro_data_d[2]`  | In  | Drive/config data |
| Right_8 | `ro_data_d[3]`  | In  | Drive/config data |
| Right_9–Right_11 | —      | —   | Unused |

### Bottom side
| Pad      | Signal           | Dir | Notes |
|:--------:|:-----------------|:---:|:------|
| Bottom_0 | `jtag_tdo_o`     | Out | JTAG data output |
| Bottom_1 | `uart_tx_o`      | Out | UART TX |
| Bottom_2 | `status_o`       | Out | Status/heartbeat |
| Bottom_3 | `gpio_o[0]`      | Out | GPIO |
| Bottom_4 | `gpio_o[1]`      | Out | GPIO |
| Bottom_5 | `ro_q`           | Out | RO observation |
| Bottom_6 | `ro_data_q[0]`   | Out | RO captured data |
| Bottom_7 | `ro_data_q[1]`   | Out | RO captured data |
| Bottom_8 | `ro_scan_q`      | Out | RO scan out |
| Bottom_9 | `ro_data_q[2]`   | Out | RO captured data |
| Bottom_10| `ro_data_q[3]`   | Out | RO captured data |

---
<img width="1022" height="513" alt="image" src="https://github.com/user-attachments/assets/8ba398bb-c8f2-4504-b76e-13f61a993f71" />

## Ibex stage architecture with scan chain + 128 words * 32 DFF as IRAM/DRAM

**High‑level blocks**
- **Core:** `CVE2` (Ibex) RISC‑V core.
- **Interconnect:** `OBI Crossbar` connects the core to memory and a `USER` expansion port; an `OBI Demux` routes transactions to peripherals.
- **On‑chip memories:** `IRAM` (instruction RAM) and `DRAM` (data RAM).
- **Peripherals:** `UART`, `GPIO`, `TIMER`.
- **Debug:** `JTAG` + `Debug` block interfacing the core and testbench.
- **DFT:** Integrated **scan chain** controlled by `scan_en_i`, `scan_mode_i`, `tdi_i`/`tdo_o`; DFF‑based RAM is scan‑visible.

**Data/control flow (summary)**
- The Ibex core issues OBI transactions → the crossbar steers instruction fetches to **IRAM** and data accesses to **DRAM** (or peripherals via the demux).  
- JTAG/Debug provides external visibility and control; the scan chain enables structural test and state capture/restore across sequential elements.

---

## Simulation flow (software → RTL/Gate → testbench)
<img width="1187" height="605" alt="image" src="https://github.com/user-attachments/assets/f40ca2f0-84a9-43db-a4c6-34bed9a40edc" />
> The console log (slide) shows the JTAG loader writing memory locations, starting instruction fetch, resuming the hart, and detecting EOC to terminate the run.


**Software compilation (host)**
1. Write C‑based tests.
2. Compile with GCC/LLVM to **RISC‑V assembly**.
3. Assemble/link to a **RISC‑V executable binary** (ELF/HEX).

**RTL/Gate simulation**
1. Compile RTL with **Modelsim** to a host‑executable, cycle‑accurate model.
2. Run the simulation binary, loading the program image.

**CROC testbench sequence (JTAG‑driven)**
1. **JTAG loader** writes the program into DUT memory.
2. Program entry point is set; the core is **woken up** from reset/idle.
3. Core **executes** from the entry point.
4. Testbench polls **EOC** (end‑of‑computation) via JTAG and reads back results.

---


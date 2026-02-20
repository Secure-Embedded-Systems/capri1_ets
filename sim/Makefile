export PATH := /opt/riscv/bin:$(PATH)

GCC_VERSION := $(shell riscv64-unknown-elf-gcc -dumpversion)
export LD_LIBRARY_PATH := $(LD_LIBRARY_PATH):/opt/riscv/lib/gcc/riscv64-unknown-elf/$(GCC_VERSION)
export LDFLAGS := -fno-use-linker-plugin

PROGRAM ?= helloworld
SW_HEX := ../sw/bin/$(PROGRAM).hex
SW_C_SRCS := $(wildcard sw/*.c)
SW_H_SRCS := $(wildcard sw/*.h)
SW_S_SRCS := $(wildcard sw/*.S)
SW_LD_SRCS := $(wildcard sw/*.ld)

# NOTE: Gate-level simulation requires foundry standard cell Verilog models.
#       Set CELLS to point to your standard cell library Verilog files.
#       These are not included due to NDA restrictions.
CELLS ?=

NETLIST:=../syn/syn_output/chip_netlist.v
SDFFILE:="../syn/syn_output/chip_delays.sdf"

VLOG_ARGS  := -svinputport=compat
VSIM_ARGS  := -t 1ns -voptargs=+acc
VSIM_ARGS += -suppress vsim-3009 -suppress vsim-8683 -suppress vsim-8386 -suppress vsim-3601 -suppress vsim-3812 -suppress vopt-2122

FLIST := chip.flist

all:
	@echo "Targets are:(e.g. make <Targets> PROGRAM=addition)"
	@echo "   chip_sim_rtl PROGRAM=<program_name> :   Simulate chip-level RTL which is a wrapper on chip"
	@echo "   map :       map scan dump binary to corresponding signals "
	@echo "   clean:          Remove intermediate results"

chip_sim_rtl:
	rm -rf vsim/work
	mkdir -p scan_frames
	vlog $(VLOG_ARGS) -f $(FLIST) ../rtl/riscv-dbg/tb/jtag_test_simple.sv ./tb_chip.sv
	vsim -c +binary="$(realpath $(SW_HEX))" tb_chip $(VSIM_ARGS) -do wave.do

map:
	python3 map.py
	python3 parse.py scan_dump.txt parse_out.csv

$(SW_HEX): $(SW_C_SRCS) $(SW_H_SRCS) $(SW_S_SRCS) $(SW_LD_SRCS)
	$(MAKE) -C ../sw/ compile

software: $(SW_HEX)
sw: $(SW_HEX)

.PHONY: chip_sim_rtl rtl_sim software sw clean

clean:
	rm -rf transcript work vsim/work outputs reports *.log* *.cmd* *.vcd *.wlf *~ fv *.txt *.csv *.gtkw

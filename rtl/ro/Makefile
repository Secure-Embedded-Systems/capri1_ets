
# Makefile for op_asic_stuff testbench (ModelSim)
# ------------------------------------------------
# Usage:
#   make sim_rtl
#   make sim_gate
#   make view
#   make clean

VLIB      = vlib
VLOG      = vlog
VSIM      = vsim
WORKDIR   = work

RTL_SRCS  = customNand.v \
	    customInv.v \
	    ro_11_stage.v \
            inv_chain_11_stage.v \
            op_asic_stuff.v


TB_SRC    = tb_op_asic_stuff.v
VCD_FILE  = tb_op_asic_stuff.vcd

.PHONY: all sim_rtl sim_gate view clean $(WORKDIR)

all: sim_rtl

# create work library if needed
$(WORKDIR):
	-$(VLIB) $(WORKDIR)

# RTL‐level compile + sim
sim_rtl: $(WORKDIR)
	@echo "=== Compiling RTL + TB into '$(WORKDIR)' ==="
	$(VLOG) -work $(WORKDIR) $(RTL_SRCS) $(TB_SRC)
	@echo "=== Running RTL simulation (dumping to $(VCD_FILE)) ==="
	$(VSIM) -c work.tb_op_asic_stuff \
	  -do "run -all; quit -f"


# Launch GTKWave
view:
	@if [ ! -f $(VCD_FILE) ]; then \
	  echo "No VCD found! Run 'make sim_rtl' or 'make sim_gate' first."; \
	else \
	  gtkwave $(VCD_FILE); \
	fi

clean:
	-@rm -rf $(WORKDIR) transcript vsim.wlf $(VCD_FILE)
	-@echo "Cleaned."


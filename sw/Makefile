# Default program name (can be overridden via command line)
PROGRAM ?= 
PROGRAM_DIRS := $(wildcard */)
BINDIR  ?= bin
CRT0    ?= soc/crt0.S
LINK    ?= soc/link.ld

# If PROGRAM is not passed, show usage instructions
ifeq ($(strip $(PROGRAM)),)
all:
	@echo "Usage:"
	@echo "  make PROGRAM=<program_name>   Build the specified program (e.g., make PROGRAM=overflow)"
	@echo "  make clean                    Remove build artifacts from all programs"
else


# Toolchain
RISCV_XLEN    ?= 32
RISCV_MARCH   ?= rv$(RISCV_XLEN)i_zicsr2
RISCV_MABI    ?= ilp32
RISCV_PREFIX  ?= riscv64-unknown-elf-
RISCV_CC      ?= $(RISCV_PREFIX)gcc
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump
RISCV_OBJCOPY ?= $(RISCV_PREFIX)objcopy
RISCV_SIZE    ?= $(RISCV_PREFIX)size

# Flags
RISCV_FLAGS   ?= -march=$(RISCV_MARCH) \
                 -mabi=$(RISCV_MABI) \
                 -mcmodel=medany \
                 -static \
                 -std=gnu99 \
                 -Os \
                 -nostdlib \
                 -fno-builtin \
                 -ffreestanding \
                 -fno-use-linker-plugin

RISCV_CCFLAGS ?= $(RISCV_FLAGS)
RISCV_LDFLAGS ?= -static -nostartfiles -lm -lgcc $(RISCV_FLAGS)

# Source and object files
PROGRAM_SRC   := $(PROGRAM)/$(PROGRAM).c
PROGRAM_OBJ   := $(PROGRAM)/$(PROGRAM).o
PROGRAM_ELF   := $(PROGRAM)/$(PROGRAM).elf
PROGRAM_DUMP  := $(PROGRAM)/$(PROGRAM).dump
PROGRAM_HEX   := $(BINDIR)/$(PROGRAM).hex
PROGRAM_BIN   := $(PROGRAM)/$(PROGRAM).bin

# Default target
all: $(PROGRAM_ELF) $(PROGRAM_DUMP) $(PROGRAM_HEX)

# Create binary directory if it doesn't exist
$(BINDIR):
	mkdir -p $(BINDIR)

# Compile program source file
$(PROGRAM_OBJ): $(PROGRAM_SRC)
	$(RISCV_CC) $(RISCV_CCFLAGS) -c $< -o $@

# Compile CRT0
$(PROGRAM)/crt0.o: $(CRT0)
	$(RISCV_CC) $(RISCV_CCFLAGS) -c $< -o $@

# Link the program
$(PROGRAM_ELF): $(PROGRAM_OBJ) $(PROGRAM)/crt0.o
	$(RISCV_CC) -o $@ $^ $(RISCV_LDFLAGS) -T$(LINK)

# Generate assembly dump
$(PROGRAM_DUMP): $(PROGRAM_ELF)
	$(RISCV_OBJDUMP) -D -s $< > $@
	$(RISCV_SIZE) $<

# Generate hex file
$(PROGRAM_HEX): $(PROGRAM_ELF) | $(BINDIR)
	$(RISCV_OBJCOPY) -O verilog \
		--pad-to=0x10000400 \
		--gap-fill=0x00 \
		$< $@
# Generate raw binary
$(PROGRAM_BIN): $(PROGRAM_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@


endif

# Clean up generated files
clean:
	@echo "Cleaning all program directories..."
	@for dir in $(PROGRAM_DIRS); do \
		rm -f "$$dir"*.o "$$dir"*.elf "$$dir"*.dump; \
	done
	@rm -rf $(BINDIR)/
.PHONY: all clean


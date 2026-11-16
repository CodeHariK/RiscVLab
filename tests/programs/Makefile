# Assembles the bare-metal test programs into ELF executables and raw
# binaries for the emulator (it loads either).
# Uses only binutils (as, ld, objcopy, objdump): no C compiler needed.
#
# Homebrew's toolchain uses the riscv64-elf- prefix; override with
#   make CROSS=riscv64-unknown-elf-

CROSS     ?= riscv64-elf-
ARCH      := -march=rv64ima_zicsr -mabi=lp64
# -g: record which source line each instruction came from (DWARF line
# table), so the debugger can show the source. The code itself is unchanged.
ASFLAGS   := -g
LINK      := link.ld
BUILD     := build

# Test programs (*.s) and lessons for the debugger (lessons/*.s).
SOURCES := $(wildcard *.s) $(wildcard lessons/*.s)
BINARIES := $(patsubst %.s,$(BUILD)/%.bin,$(SOURCES))
LINES    := $(patsubst %.s,$(BUILD)/%.lines,$(SOURCES))

.PHONY: all clean

# Keep the .o and .elf files: make would otherwise delete them as
# intermediates. The .elf files are needed for ELF loading and debugging.
.SECONDARY:

all: $(BINARIES) $(LINES)

$(BUILD)/%.o: %.s
	@mkdir -p $(dir $@)
	$(CROSS)as $(ARCH) $(ASFLAGS) $< -o $@

# ELF executable: the emulator loads these directly.
$(BUILD)/%.elf: $(BUILD)/%.o $(LINK)
	$(CROSS)ld -T $(LINK) $< -o $@

# Raw binary (also loadable), plus a disassembly to read alongside traces.
$(BUILD)/%.bin: $(BUILD)/%.elf
	$(CROSS)objcopy -O binary $< $@
	$(CROSS)objdump -d -M no-aliases $< > $(BUILD)/$*.dis

# Address -> source line map for the debugger's Source view:
#   source <absolute path of the .s file>
#   <address in hex> <line number>     (one per instruction)
# taken from the line table that -g put in the ELF.
$(BUILD)/%.lines: $(BUILD)/%.elf
	@echo "source $(abspath $*.s)" > $@
	@$(CROSS)objdump --dwarf=decodedline $< | \
	  awk '$$2 ~ /^[0-9]+$$/ && $$3 ~ /^0x/ { sub(/^0x/, "", $$3); print $$3, $$2 }' >> $@

clean:
	rm -rf $(BUILD)

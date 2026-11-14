# Assembles the bare-metal test programs into ELF executables and raw
# binaries for the emulator (it loads either).
# Uses only binutils (as, ld, objcopy, objdump): no C compiler needed.
#
# Homebrew's toolchain uses the riscv64-elf- prefix; override with
#   make CROSS=riscv64-unknown-elf-

CROSS     ?= riscv64-elf-
ARCH      := -march=rv64i -mabi=lp64
LINK      := link.ld
BUILD     := build

SOURCES := $(wildcard *.s)
BINARIES := $(patsubst %.s,$(BUILD)/%.bin,$(SOURCES))

.PHONY: all clean

# Keep the .o and .elf files: make would otherwise delete them as
# intermediates. The .elf files are needed for ELF loading and debugging.
.SECONDARY:

all: $(BINARIES)

$(BUILD)/%.o: %.s
	@mkdir -p $(BUILD)
	$(CROSS)as $(ARCH) $< -o $@

# ELF executable: the emulator loads these directly.
$(BUILD)/%.elf: $(BUILD)/%.o $(LINK)
	$(CROSS)ld -T $(LINK) $< -o $@

# Raw binary (also loadable), plus a disassembly to read alongside traces.
$(BUILD)/%.bin: $(BUILD)/%.elf
	$(CROSS)objcopy -O binary $< $@
	$(CROSS)objdump -d -M no-aliases $< > $(BUILD)/$*.dis

clean:
	rm -rf $(BUILD)

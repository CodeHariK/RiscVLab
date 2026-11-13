# Assembles the bare-metal test programs into raw binaries for the emulator.
# Uses only binutils (as, ld, objcopy, objdump): no C compiler needed.
#
# Homebrew's toolchain uses the riscv64-elf- prefix; override with
#   make CROSS=riscv64-unknown-elf-

CROSS     ?= riscv64-elf-
ARCH      := -march=rv64i -mabi=lp64
LOAD_ADDR := 0x80000000
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

$(BUILD)/%.elf: $(BUILD)/%.o
	$(CROSS)ld -Ttext=$(LOAD_ADDR) $< -o $@

# Raw binary for the emulator, plus a disassembly to read alongside traces.
$(BUILD)/%.bin: $(BUILD)/%.elf
	$(CROSS)objcopy -O binary $< $@
	$(CROSS)objdump -d -M no-aliases $< > $(BUILD)/$*.dis

clean:
	rm -rf $(BUILD)

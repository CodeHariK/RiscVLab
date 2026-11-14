# Builds the official riscv-tests for the emulator.
#
#   ./fetch.sh        once: download the tests into src/
#   make              build every rv64ui-p test into build/
#
# rv64ui = 64-bit user-level integer instructions; -p = the "physical"
# environment: no virtual memory, runs in machine mode. Each test is an
# ELF that reports through `tohost`: exit code 0 = pass, n = test n failed.
#
# The tests are assembly with C preprocessor macros (.S). Instead of a full
# RISC-V GCC, this uses the host's C preprocessor (clang on macOS) and the
# RISC-V binutils. GCC would define __riscv_xlen itself; here it is given.
# (PREPROCESS, not CPP: make predefines CPP, so `CPP ?=` would be ignored.)

SRC     := src
BUILD   := build
CROSS   ?= riscv64-elf-
PREPROCESS ?= clang -E -P -x assembler-with-cpp
DEFINES := -D__riscv_xlen=64
INCLUDE := -I$(SRC)/env/p -I$(SRC)/env -I$(SRC)/isa/macros/scalar
ARCH    := -march=rv64i_zicsr_zifencei -mabi=lp64
LINK    := $(SRC)/env/p/link.ld

# The suite's own list of rv64ui tests (rv64ui_sc_tests).
-include $(SRC)/isa/rv64ui/Makefrag
TESTS := $(addprefix $(BUILD)/rv64ui-p-,$(rv64ui_sc_tests))

.PHONY: all clean check-source

all: check-source $(TESTS)

check-source:
	@test -d $(SRC)/env/p || { echo "riscv-tests source missing: run ./fetch.sh first"; exit 1; }

# One test: preprocess, assemble, link, and keep a disassembly to read
# alongside the emulator's trace.
$(BUILD)/rv64ui-p-%: $(SRC)/isa/rv64ui/%.S
	@mkdir -p $(BUILD)
	$(PREPROCESS) $(DEFINES) $(INCLUDE) $< -o $(BUILD)/$*.s
	$(CROSS)as $(ARCH) $(BUILD)/$*.s -o $(BUILD)/$*.o
	$(CROSS)ld -T $(LINK) $(BUILD)/$*.o -o $@
	$(CROSS)objdump -d -M no-aliases $@ > $@.dis

clean:
	rm -rf $(BUILD)

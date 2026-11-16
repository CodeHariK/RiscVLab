# Builds the official riscv-tests for the emulator.
#
#   ./fetch.sh        once: download the tests into src/
#   make              build every rv64ui-p and rv64um-p test into build/
#
# rv64ui = 64-bit user-level integer instructions, rv64um = multiply and
# divide (the M extension); -p = the "physical" environment: no virtual
# memory, runs in machine mode. Each test is an
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
ARCH    := -march=rv64im_zicsr_zifencei -mabi=lp64
LINK    := $(SRC)/env/p/link.ld

# The suites' own lists of tests (rv64ui_sc_tests, rv64um_sc_tests).
-include $(SRC)/isa/rv64ui/Makefrag
-include $(SRC)/isa/rv64um/Makefrag
TESTS := $(addprefix $(BUILD)/rv64ui-p-,$(rv64ui_sc_tests)) \
         $(addprefix $(BUILD)/rv64um-p-,$(rv64um_sc_tests))
LINES := $(addsuffix .lines,$(TESTS))

.PHONY: all clean check-source

all: check-source $(TESTS) $(LINES)

check-source:
	@test -d $(SRC)/env/p || { echo "riscv-tests source missing: run ./fetch.sh first"; exit 1; }

# One test: preprocess, assemble, link, and keep a disassembly to read
# alongside the emulator's trace. The test macros expand to many
# instructions joined by ';' on one line; split_statements.awk puts each on
# its own line, so the debugger's Source view can follow them one by one.
$(BUILD)/rv64ui-p-%: $(SRC)/isa/rv64ui/%.S
	$(call build_test,rv64ui-$*)

$(BUILD)/rv64um-p-%: $(SRC)/isa/rv64um/%.S
	$(call build_test,rv64um-$*)

# $(1): a name for the intermediate files, e.g. rv64ui-add.
define build_test
	@mkdir -p $(BUILD)
	$(PREPROCESS) $(DEFINES) $(INCLUDE) $< | awk -f split_statements.awk > $(BUILD)/$(1).s
	$(CROSS)as $(ARCH) -g $(BUILD)/$(1).s -o $(BUILD)/$(1).o
	$(CROSS)ld -T $(LINK) $(BUILD)/$(1).o -o $@
	$(CROSS)objdump -d -M no-aliases $@ > $@.dis
endef

# Address -> source line map for the debugger's Source view (see
# tests/programs/Makefile). The source is the preprocessed test, with the
# macros expanded.
$(BUILD)/rv64ui-p-%.lines: $(BUILD)/rv64ui-p-%
	$(call line_map,rv64ui-$*)

$(BUILD)/rv64um-p-%.lines: $(BUILD)/rv64um-p-%
	$(call line_map,rv64um-$*)

define line_map
	@echo "source $(abspath $(BUILD)/$(1).s)" > $@
	@$(CROSS)objdump --dwarf=decodedline $< | \
	  awk '$$2 ~ /^[0-9]+$$/ && $$3 ~ /^0x/ { sub(/^0x/, "", $$3); print $$3, $$2 }' >> $@
endef

clean:
	rm -rf $(BUILD)

# Build and run the RiscVOdin emulator.
#
#   make              release build of the command-line runner -> build/rvemu
#   make debug        debug build                              -> build/rvemu-debug
#   make test         unit tests, then build the test programs, run them, check undo and the disassembler
#   make unit         unit tests only (unit_tests/, `odin test`)
#   make run PROGRAM=path/to/program.bin [ARGS=--trace]
#   make riscv-tests  build and run the official rv64ui, rv64um and rv64ua tests (run ../tests/riscv-tests/fetch.sh once first)
#   make debugger     build the step debugger -> build/rvdbg
#   make debug-ui     open the debugger with the lessons and tests listed
#                     (UI_PROGRAM=path/to/program to open a specific one)
#
# Source: core/ is the emulator itself (package rv, no file or console I/O),
# loader/ loads programs and disasm/ turns instructions into text;
# cli/ is the command-line front end; debugger/ is the step debugger
# (raylib + Clay, from vendor/clay-odin).

ODIN      ?= odin
BUILD_DIR := build
BINARY    := $(BUILD_DIR)/rvemu
DEBUG_BIN := $(BUILD_DIR)/rvemu-debug
SOURCES   := $(wildcard core/*.odin loader/*.odin disasm/*.odin cli/*.odin)
DEBUGGER  := $(BUILD_DIR)/rvdbg
DEBUGGER_SOURCES := $(wildcard core/*.odin loader/*.odin disasm/*.odin debugger/*.odin debugger/state/*.odin debugger/view/*.odin debugger/ui/*.odin debugger/reference/*.odin vendor/clay-odin/*.odin) $(wildcard debugger/ui/fonts/*.ttf ../docs/reference/*.md)

PROGRAMS_DIR := ../tests/programs
PROGRAMS_BIN := $(PROGRAMS_DIR)/build
PROGRAM      ?= $(PROGRAMS_BIN)/sum.elf

.PHONY: all debug run programs test unit riscv-tests clean debugger debug-ui

all: $(BINARY)

$(BINARY): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build cli -out:$(BINARY) -o:speed

debug: $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build cli -out:$(DEBUG_BIN) -debug

run: $(BINARY)
	./$(BINARY) $(PROGRAM) $(ARGS)

debugger: $(DEBUGGER)

$(DEBUGGER): $(DEBUGGER_SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build debugger -out:$(DEBUGGER)

debug-ui: $(DEBUGGER) programs
	./$(DEBUGGER) --tests ../tests $(UI_PROGRAM)

programs:
	$(MAKE) -C $(PROGRAMS_DIR)

# Each program reports through its exit code (see the .s files). Every
# program is run twice: as an ELF executable and as a raw binary. Then for
# every program: undo all steps and compare, and diff the disassembler
# against objdump.
TEST_PROGRAMS := sum rv64i_check csr_check trap_check mret_check
FORMATS       := elf bin

# Unit tests for core rules that no test program can reach yet.
unit:
	@mkdir -p $(BUILD_DIR)
	$(ODIN) test unit_tests -out:$(BUILD_DIR)/unit_tests

test: unit $(BINARY) programs
	@for format in $(FORMATS); do \
	  ./$(BINARY) $(PROGRAMS_BIN)/sum.$$format; code=$$?; \
	  if [ $$code -eq 55 ]; then echo "PASS sum.$$format"; else echo "FAIL sum.$$format (exit $$code, expected 55)"; exit 1; fi; \
	  for program in rv64i_check csr_check trap_check mret_check; do \
	    ./$(BINARY) $(PROGRAMS_BIN)/$$program.$$format; code=$$?; \
	    if [ $$code -eq 0 ]; then echo "PASS $$program.$$format"; else echo "FAIL $$program.$$format (check $$code failed)"; exit 1; fi; \
	  done; \
	done
	@sh ../tests/run_lessons.sh ./$(BINARY) $(PROGRAMS_DIR)/lessons $(PROGRAMS_BIN)/lessons
	@for program in $(TEST_PROGRAMS); do \
	  ./$(BINARY) $(PROGRAMS_BIN)/$$program.elf --check-undo || exit 1; \
	done
	@for program in $(TEST_PROGRAMS); do for format in $(FORMATS); do \
	  sh ../tests/compare_disasm.sh ./$(BINARY) $(PROGRAMS_BIN)/$$program.$$format $(PROGRAMS_BIN)/$$program.dis || exit 1; \
	done; done

# The official riscv-tests (rv64ui-p): downloaded separately, so not part
# of `make test`.
riscv-tests: $(BINARY)
	$(MAKE) -C ../tests/riscv-tests
	sh ../tests/riscv-tests/run.sh ./$(BINARY) ../tests/riscv-tests/build

clean:
	rm -rf $(BUILD_DIR)

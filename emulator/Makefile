# Build and run the RiscVOdin emulator.
#
#   make              release build of the command-line runner -> build/rvemu
#                     (without step recording: fastest, but no --trace or --check-undo)
#   make check-build  the same, recording steps                -> build/rvemu-check
#   make debug        debug build, recording steps             -> build/rvemu-debug
#   make test         unit tests and the docs check, then build the test programs, run them, check undo and the disassembler
#   make unit         unit tests only (unit_tests/, `odin test`)
#   make docs-check   check the docs: every Related item and lesson # Docs: name is an entry, plain ASCII
#   make run PROGRAM=path/to/program.bin [ARGS=--trace]   (uses build/rvemu-check)
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
# -vet: unused imports and variables, shadowing and the like are errors.
VET       := -vet
BUILD_DIR := build
BINARY    := $(BUILD_DIR)/rvemu
# The same runner with step recording (core/history.odin, DEBUG_RECORD_STEPS):
# what --trace and --check-undo need. build/rvemu is built without it.
CHECK_BIN := $(BUILD_DIR)/rvemu-check
DEBUG_BIN := $(BUILD_DIR)/rvemu-debug
SOURCES   := $(wildcard core/*.odin devices/*.odin loader/*.odin disasm/*.odin cli/*.odin)
DEBUGGER  := $(BUILD_DIR)/rvdbg
DEBUGGER_SOURCES := $(wildcard core/*.odin devices/*.odin loader/*.odin disasm/*.odin debugger/*.odin debugger/state/*.odin debugger/view/*.odin debugger/ui/*.odin debugger/reference/*.odin vendor/clay-odin/*.odin) $(wildcard debugger/ui/fonts/*.ttf ../docs/reference/*.md)

PROGRAMS_DIR := ../tests/programs
PROGRAMS_BIN := $(PROGRAMS_DIR)/build
PROGRAM      ?= $(PROGRAMS_BIN)/sum.elf

.PHONY: all check-build debug run programs test unit docs-check riscv-tests clean debugger debug-ui

all: $(BINARY)

$(BINARY): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build cli -out:$(BINARY) -o:speed $(VET) -define:DEBUG_RECORD_STEPS=false

check-build: $(CHECK_BIN)

$(CHECK_BIN): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build cli -out:$(CHECK_BIN) -o:speed $(VET)

debug: $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build cli -out:$(DEBUG_BIN) -debug $(VET)

run: $(CHECK_BIN)
	./$(CHECK_BIN) $(PROGRAM) $(ARGS)

debugger: $(DEBUGGER)

$(DEBUGGER): $(DEBUGGER_SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build debugger -out:$(DEBUGGER) $(VET)

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
	$(ODIN) test unit_tests -out:$(BUILD_DIR)/unit_tests $(VET)

# Checks on the docs (debugger/reference/reference_test.odin), with the
# same parser the Docs window uses.
docs-check:
	@mkdir -p $(BUILD_DIR)
	$(ODIN) test debugger/reference -out:$(BUILD_DIR)/docs_check $(VET)

# Both builds: plain runs use build/rvemu (no step recording), the undo
# checks build/rvemu-check, so code on both sides of `when DEBUG_RECORD_STEPS`
# is compiled and run.
test: unit docs-check $(BINARY) $(CHECK_BIN) programs
	@for format in $(FORMATS); do \
	  ./$(BINARY) $(PROGRAMS_BIN)/sum.$$format; code=$$?; \
	  if [ $$code -eq 55 ]; then echo "PASS sum.$$format"; else echo "FAIL sum.$$format (exit $$code, expected 55)"; exit 1; fi; \
	  for program in rv64i_check csr_check trap_check mret_check; do \
	    ./$(BINARY) $(PROGRAMS_BIN)/$$program.$$format; code=$$?; \
	    if [ $$code -eq 0 ]; then echo "PASS $$program.$$format"; else echo "FAIL $$program.$$format (check $$code failed)"; exit 1; fi; \
	  done; \
	done
	@sh ../tests/run_lessons.sh ./$(BINARY) $(PROGRAMS_DIR)/lessons $(PROGRAMS_BIN)/lessons ./$(CHECK_BIN)
	@for program in $(TEST_PROGRAMS); do \
	  ./$(CHECK_BIN) $(PROGRAMS_BIN)/$$program.elf --check-undo || exit 1; \
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

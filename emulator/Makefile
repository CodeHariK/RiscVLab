# Build and run the RiscVOdin emulator.
#
#   make              release build of the command-line runner -> build/rvemu
#   make debug        debug build                              -> build/rvemu-debug
#   make test         build the test programs, run them, check undo and the disassembler
#   make run PROGRAM=path/to/program.bin [ARGS=--trace]
#   make debugger     build the step debugger -> build/rvdbg
#   make debug-ui PROGRAM=path/to/program.bin   open a program in the debugger
#
# Source: core/ is the emulator itself (package rv, no file or console I/O);
# cli/ is the command-line front end; debugger/ is the step debugger
# (raylib + Clay, from vendor/clay-odin).

ODIN      ?= odin
BUILD_DIR := build
BINARY    := $(BUILD_DIR)/rvemu
DEBUG_BIN := $(BUILD_DIR)/rvemu-debug
SOURCES   := $(wildcard core/*.odin cli/*.odin)
DEBUGGER  := $(BUILD_DIR)/rvdbg
DEBUGGER_SOURCES := $(wildcard core/*.odin debugger/*.odin vendor/clay-odin/*.odin) $(wildcard debugger/fonts/*.ttf)

PROGRAMS_DIR := ../tests/programs
PROGRAMS_BIN := $(PROGRAMS_DIR)/build
PROGRAM      ?= $(PROGRAMS_BIN)/sum.bin

.PHONY: all debug run programs test clean debugger debug-ui

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
	./$(DEBUGGER) $(PROGRAM)

programs:
	$(MAKE) -C $(PROGRAMS_DIR)

# Each program reports through its exit code (see the .s files).
# Then for every program: undo all steps and compare, and diff the
# disassembler against objdump.
TEST_PROGRAMS := sum rv64i_check

test: $(BINARY) programs
	@./$(BINARY) $(PROGRAMS_BIN)/sum.bin; \
	  code=$$?; if [ $$code -eq 55 ]; then echo "PASS sum"; else echo "FAIL sum (exit $$code, expected 55)"; exit 1; fi
	@./$(BINARY) $(PROGRAMS_BIN)/rv64i_check.bin; \
	  code=$$?; if [ $$code -eq 0 ]; then echo "PASS rv64i_check"; else echo "FAIL rv64i_check (check $$code failed)"; exit 1; fi
	@for program in $(TEST_PROGRAMS); do \
	  ./$(BINARY) $(PROGRAMS_BIN)/$$program.bin --check-undo || exit 1; \
	done
	@for program in $(TEST_PROGRAMS); do \
	  ../tests/compare_disasm.sh ./$(BINARY) $(PROGRAMS_BIN)/$$program.bin $(PROGRAMS_BIN)/$$program.dis || exit 1; \
	done

clean:
	rm -rf $(BUILD_DIR)

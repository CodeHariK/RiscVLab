# Build and run the RiscVOdin emulator.
#
#   make              release build -> build/rvemu
#   make debug        debug build   -> build/rvemu-debug
#   make test         build the test programs and run them
#   make run PROGRAM=path/to/program.bin [ARGS=--trace]

ODIN      ?= odin
BUILD_DIR := build
BINARY    := $(BUILD_DIR)/rvemu
DEBUG_BIN := $(BUILD_DIR)/rvemu-debug
SOURCES   := $(wildcard src/*.odin)

PROGRAMS_DIR := ../tests/programs
PROGRAMS_BIN := $(PROGRAMS_DIR)/build

.PHONY: all debug run programs test clean

all: $(BINARY)

$(BINARY): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build src -out:$(BINARY) -o:speed

debug: $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build src -out:$(DEBUG_BIN) -debug

run: $(BINARY)
	./$(BINARY) $(PROGRAM) $(ARGS)

programs:
	$(MAKE) -C $(PROGRAMS_DIR)

# Each program reports through its exit code (see the .s files).
test: $(BINARY) programs
	@./$(BINARY) $(PROGRAMS_BIN)/sum.bin; \
	  code=$$?; if [ $$code -eq 55 ]; then echo "PASS sum"; else echo "FAIL sum (exit $$code, expected 55)"; exit 1; fi
	@./$(BINARY) $(PROGRAMS_BIN)/rv64i_check.bin; \
	  code=$$?; if [ $$code -eq 0 ]; then echo "PASS rv64i_check"; else echo "FAIL rv64i_check (check $$code failed)"; exit 1; fi

clean:
	rm -rf $(BUILD_DIR)

package rvemu

import "core:fmt"
import "core:strconv"
import rv "../core"

// Upper bound on executed instructions, so a buggy program can't hang the
// emulator forever. Override with --max-steps (0 means no limit).
MAX_STEPS_DEFAULT :: u64(100_000_000)

Mode :: enum {
	Run,         // run the program and report how it stopped
	Disassemble, // print the program's disassembly and exit
	Check_Undo,  // run, undo every step, check the state is back to the start
}

Options :: struct {
	program_path: string,
	mode:         Mode,
	trace:        bool,
	max_steps:    u64,
}

// Parses: rvemu <program> [--trace] [--disasm] [--check-undo] [--max-steps N]
parse_options :: proc(args: []string) -> (options: Options, ok: bool) {
	options.max_steps = MAX_STEPS_DEFAULT

	for i := 1; i < len(args); i += 1 {
		argument := args[i]
		switch argument {
		case "--trace":
			options.trace = true
		case "--disasm":
			options.mode = .Disassemble
		case "--check-undo":
			options.mode = .Check_Undo
		case "--max-steps":
			i += 1
			if i >= len(args) {
				fmt.eprintln("error: --max-steps needs a number")
				return options, false
			}
			value, parsed := strconv.parse_u64(args[i])
			if !parsed {
				fmt.eprintfln("error: --max-steps: %s is not a number", args[i])
				return options, false
			}
			options.max_steps = value
		case:
			if options.program_path != "" {
				fmt.eprintfln("error: unexpected argument %s", argument)
				return options, false
			}
			options.program_path = argument
		}
	}

	if options.program_path == "" {
		return options, false
	}
	return options, true
}

print_usage :: proc() {
	fmt.eprintln("usage: rvemu <program> [options]")
	fmt.eprintln("  program          RISC-V ELF executable, or raw binary (loaded and started at 0x80000000)")
	fmt.eprintln("  --trace          print every executed instruction")
	fmt.eprintln("  --disasm         print the program's disassembly instead of running it")
	fmt.eprintln("  --check-undo     run, then undo every step and check the state matches the start")
	fmt.eprintln("  --max-steps N    stop after N instructions (0 = no limit)")
}

// False (with a message) if the options need something this build left
// out: a build without step recording (rv.DEBUG_RECORD_STEPS, core/history.odin)
// has nothing to undo and doesn't note what each step wrote.
options_fit_build :: proc(options: Options) -> bool {
	when !rv.DEBUG_RECORD_STEPS {
		if options.trace || options.mode == .Check_Undo {
			fmt.eprintln("error: this rvemu doesn't record steps, so it can't --trace or --check-undo: use build/rvemu-check")
			return false
		}
	}
	return true
}

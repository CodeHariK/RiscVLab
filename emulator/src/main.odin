package emulator

import "core:os"

// RiscVOdin: a RISC-V (RV64) emulator, built up milestone by milestone
// towards booting xv6. See ../README.md for the current milestone.
main :: proc() {
	os.exit(run())
}

// Separate from `main` so deferred cleanup runs before os.exit.
run :: proc() -> int {
	options, ok := parse_options(os.args)
	if !ok {
		print_usage()
		return 2
	}

	machine := machine_create(RAM_SIZE_DEFAULT)
	defer machine_destroy(&machine)

	if !load_raw_binary(&machine.bus, options.program_path) {
		return 1
	}

	result := machine_run(&machine, options.max_steps, options.trace)
	return machine_report(&machine, result)
}

package rvemu

import "core:os"
import rv "../core"
import loader "../loader"

// rvemu: command-line front end for the RiscVOdin core.
// Runs a program (ELF executable or raw binary) and reports how it stopped;
// can also trace every instruction, list a program's disassembly, or
// self-test undo.
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

	image, image_ok := read_program(options.program_path)
	if !image_ok {
		return 1
	}
	defer delete(image)

	// Only the undo check needs history; normal runs skip recording.
	history_capacity := rv.HISTORY_CAPACITY_DEFAULT if options.mode == .Check_Undo else 0
	machine := rv.machine_create(rv.RAM_SIZE_DEFAULT, history_capacity)
	defer rv.machine_destroy(&machine)

	program, load_error := loader.load_program(&machine, image)
	if load_error != nil {
		print_load_error(options.program_path, load_error)
		return 1
	}

	switch options.mode {
	case .Run:
		observer: rv.Step_Observer = nil
		if options.trace {
			observer = print_trace_line
		}
		result := rv.machine_run(&machine, options.max_steps, observer)
		return report_result(&machine, result)
	case .Check_Undo:
		return check_undo(&machine, options.max_steps)
	case .Disassemble:
		print_disassembly(&machine, program)
	}
	return 0
}

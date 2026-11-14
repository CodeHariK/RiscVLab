package rv

// Loading a program, whatever its format. Front ends pass the file's bytes
// and get back where to start and what range holds the code.
//
//   - ELF executables (detected by their magic number): segments go to
//     their physical addresses; execution starts at the ELF entry point.
//   - Anything else is a raw binary (`objcopy -O binary`): copied to
//     RAM_BASE and started there.

Program_Format :: enum {
	Raw,
	Elf,
}

Program :: struct {
	format:     Program_Format,
	entry:      u64,
	code_start: u64,
	code_end:   u64,
	tohost:     Maybe(u64), // ELF only; used for riscv-tests results later
}

Load_Error :: union {
	Raw_Load_Error,
	Elf_Error,
}

Raw_Load_Error :: enum {
	None,
	Larger_Than_Ram,
}

// Loads the program into the machine's RAM and points the PC at its entry.
machine_load_program :: proc(machine: ^Machine, image: []u8) -> (program: Program, error: Load_Error) {
	if is_elf(image) {
		elf, elf_error := load_elf(&machine.bus, image)
		if elf_error != .None {
			return {}, elf_error
		}
		program = Program {
			format     = .Elf,
			entry      = elf.entry,
			code_start = elf.code_start,
			code_end   = elf.code_end,
			tohost     = elf.tohost,
		}
	} else {
		if !load_image(&machine.bus, image) {
			return {}, Raw_Load_Error.Larger_Than_Ram
		}
		program = Program {
			format     = .Raw,
			entry      = RAM_BASE,
			code_start = RAM_BASE,
			code_end   = RAM_BASE + u64(len(image)),
		}
	}
	machine.cpu.pc = program.entry
	return program, nil
}

package rv

REGISTER_COUNT :: 32

// ABI register numbers that the emulator itself needs to read.
REG_A0 :: u32(10)

// The register written by the last instruction, kept for the trace log.
Register_Write :: struct {
	valid: bool,
	index: u32,
	value: u64,
}

// Architectural state of one RISC-V hart (hardware thread).
//
// The hart starts in machine mode. MRET can take it down to user mode,
// and every trap brings it back up to machine mode (privilege.odin).
// Supervisor mode comes next.
Cpu :: struct {
	// Integer registers x0..x31. x0 always reads as zero.
	regs:       [REGISTER_COUNT]u64,
	// Address of the instruction being executed.
	pc:         u64,
	// Address of the next instruction. `cpu_step` sets it to pc + 4 before
	// executing; jumps and taken branches overwrite it.
	next_pc:    u64,
	// Not a CSR: what turns mcycle into the step clock, the machine's time
	// that the CLINT follows (step_clock = mcycle + step_clock_offset). It
	// changes only when a program writes mcycle (csr_write).
	step_clock_offset: u64,
	// Set when this step's CSR instruction wrote minstret / mcycle: the
	// written value then stands, without the instruction's own count
	// (cpu_step). Cleared at the start of each step. (mcycle also counts a
	// trap or interrupt taken into a handler: machine_step does that.)
	minstret_written: bool,
	mcycle_written:   bool,
	// Current privilege level. (Next to the bools above, so the three
	// share one 8-byte slot.)
	privilege:  Privilege,
	// Control and status registers (csr.odin).
	csr:        Csr_File,
	// Last register write, for tracing. Cleared at the start of each step.
	debug_last_write: Register_Write,
	// The address LR reserved for the next SC (rv64a.odin).
	reservation: Reservation,
	// What the current instruction overwrote, so it can be undone.
	// Filled in during the step; `machine_step` saves it to the history.
	debug_undo: Undo_Record,
}

// The step clock: one tick per step, like mcycle, but no program can
// change it. It is the platform's time, which devices that keep time (the
// CLINT's mtime) follow; the bus calls pass it as `now`. It must be apart
// from mcycle because a program can write mcycle, and on real hardware
// that doesn't move the timer (docs: emulator-time).
//
// It isn't a counter of its own, though: mcycle already ticks once per
// step, so the clock is mcycle plus an offset, which changes only when a
// program writes mcycle (csr_write), by just as much as keeps the clock
// going. So a step costs nothing extra, and undo needs no field for it:
// putting mcycle back puts the clock back.
step_clock :: #force_inline proc(cpu: ^Cpu) -> u64 {
	return cpu.csr.mcycle + cpu.step_clock_offset
}

// What LR.W / LR.D reserved: SC succeeds only on the same address and
// size while this is still valid.
Reservation :: struct {
	valid:   bool,
	address: u64,
	size:    u64,
}

// Changes the reservation, keeping the old one in the undo record (the
// first change in a step is the one to restore).
reservation_set :: proc(cpu: ^Cpu, reservation: Reservation) {
	when DEBUG_RECORD_STEPS {
		if !cpu.debug_undo.reservation_changed {
			cpu.debug_undo.reservation_changed = true
			cpu.debug_undo.reservation_old = cpu.reservation
		}
	}
	cpu.reservation = reservation
}

reg_read :: #force_inline proc(cpu: ^Cpu, index: u32) -> u64 {
	return cpu.regs[index]
}

// Writes a register. Writes to x0 are discarded, which is how the
// hardware keeps it hard-wired to zero. The old value goes into the undo
// record. This is the only place registers change, so undo can't miss one.
reg_write :: #force_inline proc(cpu: ^Cpu, index: u32, value: u64) {
	if index == 0 {
		return
	}
	when DEBUG_RECORD_STEPS {
		cpu.debug_undo.register_changed = true
		cpu.debug_undo.register_index = index
		cpu.debug_undo.register_old = cpu.regs[index]
		cpu.debug_last_write = Register_Write{valid = true, index = index, value = value}
	}
	cpu.regs[index] = value
}

// ------------------------------------------------------------ one instruction

// Every instruction is 4 bytes: without the C extension there are no
// 2-byte ones, so the next instruction is always at pc + 4.
INSTRUCTION_SIZE :: u64(4)

// Fetches, decodes and executes one instruction.
//
// On success the PC moves to `next_pc`, and minstret and mcycle count
// the instruction (unless it wrote that counter: a CSR write takes effect
// after the instruction, so the written value is what the next one reads).
// On a trap the PC stays on the faulting instruction, which is where
// `mepc` points, and neither counts here: the instruction didn't
// complete. A trap taken into a handler still takes a cycle; machine_step
// counts that one.
cpu_step :: proc(cpu: ^Cpu, bus: ^Bus) -> Step_Result {
	when DEBUG_RECORD_STEPS {
		cpu.debug_last_write = {}
	}
	cpu.minstret_written = false
	cpu.mcycle_written = false

	instruction, fetched := bus_fetch(bus, cpu.pc)
	if !fetched {
		return trap_make(.Instruction_Access_Fault, cpu.pc)
	}

	cpu.next_pc = cpu.pc + INSTRUCTION_SIZE
	if trap, has_trap := execute(cpu, bus, instruction).?; has_trap {
		return trap
	}

	cpu.pc = cpu.next_pc
	if !cpu.minstret_written {
		cpu.csr.minstret += 1
	}
	if !cpu.mcycle_written {
		cpu.csr.mcycle += 1
	}
	return nil
}

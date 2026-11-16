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
// The hart starts in machine mode, which is the only mode so far; traps
// enter machine mode too (priv_trap.odin).
Cpu :: struct {
	// Integer registers x0..x31. x0 always reads as zero.
	regs:       [REGISTER_COUNT]u64,
	// Address of the instruction being executed.
	pc:         u64,
	// Address of the next instruction. `cpu_step` sets it to pc + 4 before
	// executing; jumps and taken branches overwrite it.
	next_pc:    u64,
	// Instructions completed without a trap: the `minstret` CSR.
	instret:    u64,
	// Control and status registers (csr.odin).
	csr:        Csr_File,
	// Current privilege level.
	privilege:  Privilege,
	// Last register write, for tracing. Cleared at the start of each step.
	last_write: Register_Write,
	// The address LR reserved for the next SC (rv64a.odin).
	reservation: Reservation,
	// What the current instruction overwrote, so it can be undone.
	// Filled in during the step; `machine_step` saves it to the history.
	undo:       Undo_Record,
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
	if !cpu.undo.reservation_changed {
		cpu.undo.reservation_changed = true
		cpu.undo.reservation_old = cpu.reservation
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
	cpu.undo.register_changed = true
	cpu.undo.register_index = index
	cpu.undo.register_old = cpu.regs[index]
	cpu.regs[index] = value
	cpu.last_write = Register_Write{valid = true, index = index, value = value}
}

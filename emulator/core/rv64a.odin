package rv

// The A extension: atomic memory operations (opcode AMO, R-type).
//
//   LR.W / LR.D           load-reserved: load, and reserve the address
//   SC.W / SC.D           store-conditional: store only if the reservation
//                         still holds; rd = 0 on success, 1 on failure
//   AMOSWAP AMOADD AMOAND AMOOR AMOXOR AMOMIN AMOMAX AMOMINU AMOMAXU
//   (.W and .D)           rd = memory, then memory = rd op rs2, as one step
//
// Why: with several harts (or interrupts), "load, add, store" as three
// instructions can interleave with another hart's, and one update is lost.
// An AMO does the whole read-modify-write as one indivisible step, and an
// LR / SC pair lets software build any such step: the SC fails if anything
// may have touched the location since the LR, and the code retries.
//
// Encoding: funct5 (bits 31..27) picks the operation, bit 26 is aq
// (acquire) and bit 25 rl (release): memory-ordering hints for other
// harts. With one hart that runs everything in order they need nothing.
// funct3 = 010 for .W (32 bits, the loaded value sign-extended), 011 for .D.
//
// Unlike ordinary loads and stores, atomics must be naturally aligned
// (a .W address a multiple of 4, a .D address of 8), or they trap:
// Load_Address_Misaligned for LR, Store_Address_Misaligned for SC and AMOs.
// AMOs and SC report access faults as Store_Access_Fault, since they write.
//
// The reservation (Cpu.reservation) is set by LR and cleared by SC (pass or
// fail) and by trap entry, so an SC never succeeds across a trap. On one
// hart nothing else can touch the memory in between.
//
// Atomics work on RAM only: on a device address they raise an access
// fault, as on many real chips (each region of the memory map says
// whether it supports atomics). Undo needs it too: a step that traps must
// change nothing, but an AMO on a device would do its load, which may
// change the device (a UART read takes a byte), before finding out that
// the store fails.

OPCODE_AMO :: 0b010_1111

AMO_WORD :: 0b010
AMO_DOUBLE :: 0b011

AMO_LR :: 0b00010
AMO_SC :: 0b00011
AMO_SWAP :: 0b00001
AMO_ADD :: 0b00000
AMO_XOR :: 0b00100
AMO_AND :: 0b01100
AMO_OR :: 0b01000
AMO_MIN :: 0b10000
AMO_MAX :: 0b10100
AMO_MINU :: 0b11000
AMO_MAXU :: 0b11100

funct5 :: #force_inline proc(instruction: u32) -> u32 {
	return instruction >> 27
}

exec_amo :: proc(cpu: ^Cpu, bus: ^Bus, instruction: u32) -> Step_Result {
	size: u64
	switch funct3(instruction) {
	case AMO_WORD:
		size = 4
	case AMO_DOUBLE:
		size = 8
	case:
		return illegal_instruction(instruction)
	}
	// The address is rs1 itself: atomics have no offset.
	address := reg_read(cpu, rs1(instruction))

	// funct5 picks the operation; aq / rl need nothing here (see above).
	switch funct5(instruction) {
	case AMO_LR:
		if rs2(instruction) != 0 {
			return illegal_instruction(instruction)
		}
		return exec_lr(cpu, bus, instruction, address, size)
	case AMO_SC:
		return exec_sc(cpu, bus, instruction, address, size)
	case AMO_SWAP, AMO_ADD, AMO_XOR, AMO_AND, AMO_OR, AMO_MIN, AMO_MAX, AMO_MINU, AMO_MAXU:
		return exec_read_modify_write(cpu, bus, instruction, address, size)
	}
	return illegal_instruction(instruction)
}

// LR.W / LR.D: rd = the value at `address` (.W sign-extended), and
// reserve the address for the next SC.
@(private = "file")
exec_lr :: proc(cpu: ^Cpu, bus: ^Bus, instruction: u32, address: u64, size: u64) -> Step_Result {
	if address % size != 0 {
		return trap_make(.Load_Address_Misaligned, address)
	}
	if !bus_is_ram(bus, address, size) {
		return trap_make(.Load_Access_Fault, address)
	}
	value, ok := bus_load(bus, address, size, step_clock(cpu))
	if !ok {
		return trap_make(.Load_Access_Fault, address)
	}
	reservation_set(cpu, Reservation{valid = true, address = address, size = size})
	reg_write(cpu, rd(instruction), amo_extend(value, size))
	return nil
}

// SC.W / SC.D: store rs2 at `address` only if the reservation from the
// last LR still holds (same address and size); rd = 0 if it stored,
// 1 if not.
@(private = "file")
exec_sc :: proc(cpu: ^Cpu, bus: ^Bus, instruction: u32, address: u64, size: u64) -> Step_Result {
	if address % size != 0 {
		return trap_make(.Store_Address_Misaligned, address)
	}
	if !bus_is_ram(bus, address, size) {
		return trap_make(.Store_Access_Fault, address)
	}
	reservation := cpu.reservation
	holds := reservation.valid && reservation.address == address && reservation.size == size
	// The store comes before anything else changes: if it faults, the step
	// must have changed nothing (with no handler, the machine stops and
	// nothing is recorded for undo).
	if holds && !amo_store(cpu, bus, address, size, reg_read(cpu, rs2(instruction))) {
		return trap_make(.Store_Access_Fault, address)
	}
	// Pass or fail, the reservation is used up.
	reservation_set(cpu, Reservation{})
	reg_write(cpu, rd(instruction), 0 if holds else 1)
	return nil
}

// The AMOs (AMOSWAP, AMOADD, ...): rd = the value at `address`, and
// memory = that value op rs2, as one step that nothing can come between.
@(private = "file")
exec_read_modify_write :: proc(cpu: ^Cpu, bus: ^Bus, instruction: u32, address: u64, size: u64) -> Step_Result {
	// Every check comes first. An AMO writes, so even a failing read is
	// reported as a store fault (Store_Address_Misaligned,
	// Store_Access_Fault), as the spec says.
	if address % size != 0 {
		return trap_make(.Store_Address_Misaligned, address)
	}
	if !bus_is_ram(bus, address, size) {
		return trap_make(.Store_Access_Fault, address)
	}
	raw, ok := bus_load(bus, address, size, step_clock(cpu))
	if !ok {
		return trap_make(.Store_Access_Fault, address)
	}
	// .W works on 32-bit values: both are sign-extended to 64 bits, so
	// rd gets a sign-extended result and MIN / MAX compare them as
	// signed 32-bit numbers. (The upper half of `result` is cut off again
	// by the 4-byte store.)
	old := amo_extend(raw, size)
	operand := amo_extend(reg_read(cpu, rs2(instruction)), size)

	result: u64
	switch funct5(instruction) {
	case AMO_SWAP:
		result = operand
	case AMO_ADD:
		result = old + operand
	case AMO_XOR:
		result = old ~ operand
	case AMO_AND:
		result = old & operand
	case AMO_OR:
		result = old | operand
	case AMO_MIN:
		result = old if i64(old) < i64(operand) else operand
	case AMO_MAX:
		result = old if i64(old) > i64(operand) else operand
	case AMO_MINU:
		// Unsigned: for .W, compare the 32-bit values, not their
		// sign-extended forms (0x80000000 is large, not negative).
		result = old if unsigned_value(old, size) < unsigned_value(operand, size) else operand
	case AMO_MAXU:
		result = old if unsigned_value(old, size) > unsigned_value(operand, size) else operand
	}
	// Store, then write rd: if the store fails, nothing has changed yet,
	// so the trap leaves the step with nothing to undo.
	if !amo_store(cpu, bus, address, size, result) {
		return trap_make(.Store_Access_Fault, address)
	}
	reg_write(cpu, rd(instruction), old)
	return nil
}

// .W values are sign-extended from 32 bits (in registers and for the
// signed MIN / MAX); .D values are used as they are.
@(private = "file")
amo_extend :: proc(value: u64, size: u64) -> u64 {
	return sign_extend_32(value) if size == 4 else value
}

// For MINU / MAXU on .W: compare the 32-bit values as unsigned.
@(private = "file")
unsigned_value :: proc(value: u64, size: u64) -> u64 {
	return u64(u32(value)) if size == 4 else value
}

// Stores and records the old bytes for undo, as exec_store does.
@(private = "file")
amo_store :: proc(cpu: ^Cpu, bus: ^Bus, address: u64, size: u64, value: u64) -> bool {
	// Atomics only reach RAM (exec_* check bus_is_ram), where a peek
	// always works. (Not recording: no old bytes to save.)
	when DEBUG_RECORD_STEPS {
		old_value, _ := bus_peek(bus, address, size, step_clock(cpu))
	}
	if !bus_store(bus, address, size, value, step_clock(cpu)) {
		return false
	}
	when DEBUG_RECORD_STEPS {
		cpu.debug_undo.memory_changed = true
		cpu.debug_undo.memory_address = address
		cpu.debug_undo.memory_size = size
		cpu.debug_undo.memory_old = old_value
	}
	return true
}

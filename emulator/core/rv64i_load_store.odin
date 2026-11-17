package rv

// Loads and stores. The address is always rs1 + a 12-bit signed offset.
//
// funct3 encodes the size in its low two bits (0 = byte, 1 = half,
// 2 = word, 3 = double), and for loads bit 2 means "zero-extend"
// instead of "sign-extend".

// LB / LH / LW / LD / LBU / LHU / LWU rd, offset(rs1).
exec_load :: proc(cpu: ^Cpu, bus: ^Bus, instruction: u32) -> Step_Result {
	kind := funct3(instruction)
	if kind == 0b111 {
		return illegal_instruction(instruction) // would be "LDU", which doesn't exist
	}

	address := reg_read(cpu, rs1(instruction)) + imm_i(instruction)
	size := u64(1) << (kind & 0b11)
	value, ok := bus_load(bus, address, size)
	if !ok {
		return trap_make(.Load_Access_Fault, address)
	}

	switch kind {
	case 0b000:
		value = u64(i64(i8(value))) // LB
	case 0b001:
		value = u64(i64(i16(value))) // LH
	case 0b010:
		value = u64(i64(i32(value))) // LW
	// LD, LBU, LHU, LWU: already 64 bits or zero-extended by the bus.
	}

	reg_write(cpu, rd(instruction), value)
	return nil
}

// SB / SH / SW / SD rs2, offset(rs1): store the low bytes of rs2.
exec_store :: proc(cpu: ^Cpu, bus: ^Bus, instruction: u32) -> Step_Result {
	kind := funct3(instruction)
	if kind > 0b011 {
		return illegal_instruction(instruction)
	}

	address := reg_read(cpu, rs1(instruction)) + imm_s(instruction)
	size := u64(1) << kind

	// Save the bytes about to be overwritten, for undo (a peek: it must not
	// count as a read for a device).
	old_value, readable := bus_peek(bus, address, size)
	if !readable || !bus_store(bus, address, size, reg_read(cpu, rs2(instruction))) {
		return trap_make(.Store_Access_Fault, address)
	}
	cpu.undo.memory_changed = true
	cpu.undo.memory_address = address
	cpu.undo.memory_size = size
	cpu.undo.memory_old = old_value
	return nil
}

package state

import rv "../../core"

// The Steps view: one line for every step taken so far, newest last.
//
//   #12  80000014  blt t0,t1,8000000c     jumped to 0x8000000c
//   #13  8000000c  add a0,a0,t0           a0 <- 6
//
// Each Next adds an entry (unless the program stopped, which changes
// nothing); Prev removes the last one; Reset clears the list. Entries keep
// raw values, and the text is only built for the lines on screen.
//
// Besides what changed, each entry keeps what the instruction read just
// before it ran (Step_Inputs), so the detailed view (step_detail.odin) can
// show how it reached its result.

// What an instruction reads, captured just before it runs.
Step_Inputs :: struct {
	rs1_value:  u64,
	rs2_value:  u64,
	csr_value:  u64, // a CSR instruction's CSR, before it is written
	load_value: u64, // the bytes at a load's (or atomic's) address, before extension
	reservation: rv.Reservation, // the LR reservation, for explaining an SC
}

Timeline_Entry :: struct {
	pc:           u64,
	instruction:  u32,
	next_pc:      u64, // where execution went: shows jumps and taken branches
	record:       rv.Undo_Record, // what changed (old values)
	trap:         Maybe(rv.Trap), // a trap taken into a handler
	register_new: u64, // new values, read right after the step
	memory_new:   u64,
	csr_new:      u64,
	using inputs: Step_Inputs,
	// Which step had last written what this one wrote (last_writes.odin),
	// to put back on Prev.
	writes:       Step_Writes,
	// Only in the Next preview: the instruction traps with no handler set
	// up (mtvec = 0), so running it stops the machine instead.
	stops:        bool,
}

// Reads what the instruction at `pc` is about to use.
step_inputs_capture :: proc(session: ^Session, instruction: u32) -> Step_Inputs {
	machine := &session.machine
	inputs := Step_Inputs {
		rs1_value = rv.reg_read(&machine.cpu, rv.rs1(instruction)),
		rs2_value = rv.reg_read(&machine.cpu, rv.rs2(instruction)),
	}
	switch rv.opcode(instruction) {
	case rv.OPCODE_SYSTEM:
		if rv.funct3(instruction) != 0 {
			inputs.csr_value, _ = rv.csr_read(&machine.cpu, rv.csr_address(instruction))
		}
	case rv.OPCODE_LOAD:
		address := inputs.rs1_value + rv.imm_i(instruction)
		size := u64(1) << (rv.funct3(instruction) & 0b11)
		inputs.load_value, _ = rv.bus_peek(&machine.bus, address, size)
	case rv.OPCODE_AMO:
		size := u64(1) << (rv.funct3(instruction) & 0b11)
		inputs.load_value, _ = rv.bus_peek(&machine.bus, inputs.rs1_value, size)
		inputs.reservation = machine.cpu.reservation
	}
	return inputs
}

// Adds the step that just ran from `pc`.
timeline_record :: proc(session: ^Session, pc: u64, instruction: u32, inputs: Step_Inputs) {
	append(&session.timeline, timeline_entry_make(session, pc, instruction, inputs))
}

// The entry for the step that just ran from `pc`: what it read (`inputs`,
// captured before it ran), what it changed and where it went.
timeline_entry_make :: proc(session: ^Session, pc: u64, instruction: u32, inputs: Step_Inputs) -> Timeline_Entry {
	machine := &session.machine
	record := machine.cpu.undo
	entry := Timeline_Entry {
		pc          = pc,
		instruction = instruction,
		next_pc     = machine.cpu.pc,
		record      = record,
		trap        = machine.last_trap,
		inputs      = inputs,
	}
	if record.register_changed {
		entry.register_new = machine.cpu.regs[record.register_index]
	}
	if record.memory_changed {
		entry.memory_new, _ = rv.bus_peek(&machine.bus, record.memory_address, record.memory_size)
	}
	if record.csr_changed {
		entry.csr_new, _ = rv.csr_read(&machine.cpu, record.csr_address)
	}
	return entry
}

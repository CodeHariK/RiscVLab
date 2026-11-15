package rvdbg

import "core:fmt"
import "core:strings"
import rv "../core"

// The Steps view: one line for every step taken so far, newest last.
//
//   #12  80000014  blt t0,t1,8000000c     jumped to 0x8000000c
//   #13  8000000c  add a0,a0,t0           a0 <- 6
//
// Each Next adds an entry (unless the program stopped, which changes
// nothing); Prev removes the last one; Reset clears the list. Entries keep
// raw values, and the text is only built for the lines on screen.

Timeline_Entry :: struct {
	pc:           u64,
	instruction:  u32,
	next_pc:      u64, // where execution went: shows jumps and taken branches
	record:       rv.Undo_Record, // what changed (old values)
	trap:         Maybe(rv.Trap), // a trap taken into a handler
	register_new: u64, // new values, read right after the step
	memory_new:   u64,
	csr_new:      u64,
}

// Adds the step that just ran from `pc`.
timeline_record :: proc(session: ^Session, pc: u64, instruction: u32) {
	machine := &session.machine
	record := machine.cpu.undo
	entry := Timeline_Entry {
		pc          = pc,
		instruction = instruction,
		next_pc     = machine.cpu.pc,
		record      = record,
		trap        = machine.last_trap,
	}
	if record.register_changed {
		entry.register_new = machine.cpu.regs[record.register_index]
	}
	if record.memory_changed {
		entry.memory_new, _ = rv.bus_load(&machine.bus, record.memory_address, record.memory_size)
	}
	if record.csr_changed {
		entry.csr_new, _ = rv.csr_read(&machine.cpu, record.csr_address)
	}
	append(&session.timeline, entry)
}

// The step's line: number, address, disassembly, and what it did.
timeline_text :: proc(number: int, entry: Timeline_Entry) -> string {
	buffer: [rv.DISASM_BUFFER_SIZE]u8
	text := rv.disassemble(buffer[:], entry.pc, entry.instruction)
	return fmt.tprintf("#%-4d %08x  %-24s %s", number, entry.pc, text, timeline_effect(entry))
}

@(private = "file")
timeline_effect :: proc(entry: Timeline_Entry) -> string {
	if trap, took_trap := entry.trap.?; took_trap {
		return fmt.tprintf("trap %v -> handler 0x%x", trap.cause, entry.next_pc)
	}
	builder := strings.builder_make(context.temp_allocator)
	record := entry.record
	if record.register_changed {
		append_effect(&builder, fmt.tprintf("%s <- %s", rv.register_name(record.register_index), value_text(entry.register_new)))
	}
	if record.memory_changed {
		append_effect(&builder, fmt.tprintf("mem[0x%x] <- %s", record.memory_address, value_text(entry.memory_new)))
	}
	if record.csr_changed {
		append_effect(&builder, fmt.tprintf("%s <- %s", rv.csr_name(record.csr_address), value_text(entry.csr_new)))
	}
	if entry.next_pc != entry.pc + rv.INSTRUCTION_SIZE {
		append_effect(&builder, fmt.tprintf("jumped to 0x%x", entry.next_pc))
	}
	return strings.to_string(builder)
}

@(private = "file")
append_effect :: proc(builder: ^strings.Builder, text: string) {
	if strings.builder_len(builder^) > 0 {
		strings.write_string(builder, ", ")
	}
	strings.write_string(builder, text)
}

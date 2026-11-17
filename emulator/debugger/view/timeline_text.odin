package view

import "core:fmt"
import "core:strings"
import rv "../../core"
import disasm "../../disasm"
import state "../state"

// One line of text per step, for the Steps tab and the Explanation lines
// (the steps themselves are recorded in state/timeline.odin).

// The step's line: number, address, disassembly, and what it did.
// `coming` marks the preview of the step Next will run (">" for "#").
timeline_text :: proc(session: ^state.Session, number: int, entry: state.Timeline_Entry, coming := false) -> string {
	buffer: [disasm.BUFFER_SIZE]u8
	text := disasm.disassemble(buffer[:], entry.pc, entry.instruction)
	marker := ">" if coming else "#"
	return fmt.tprintf("%s%-4d %08x  %-24s %s", marker, number, entry.pc, text, timeline_effect(session, entry))
}

@(private)
timeline_effect :: proc(session: ^state.Session, entry: state.Timeline_Entry) -> string {
	if trap, took_trap := entry.trap.?; took_trap && entry.stops {
		return fmt.tprintf("%v, no trap handler: the machine stops", trap.cause)
	}
	if trap, took_trap := entry.trap.?; took_trap {
		return fmt.tprintf("trap %v -> handler 0x%x", trap.cause, entry.next_pc)
	}
	builder := strings.builder_make(context.temp_allocator)
	record := entry.record
	if record.register_changed {
		append_part(&builder, fmt.tprintf("%s <- %s", disasm.register_name(record.register_index), value_text(entry.register_new)))
	}
	if record.memory_changed {
		if place, on_device := device_place(session, record.memory_address, true); on_device {
			// A device register reads back something else (THR is write
			// only): show what was written.
			append_part(&builder, fmt.tprintf("%s <- %s", place, device_value_text(session, record.memory_address, true, entry.rs2_value)))
		} else {
			append_part(&builder, fmt.tprintf("mem[0x%x] <- %s", record.memory_address, value_text(entry.memory_new)))
		}
	}
	if record.csr_changed {
		append_part(&builder, fmt.tprintf("%s <- %s", disasm.csr_name(record.csr_address), value_text(entry.csr_new)))
	}
	if entry.next_pc != entry.pc + rv.INSTRUCTION_SIZE {
		append_part(&builder, fmt.tprintf("jumped to 0x%x", entry.next_pc))
	} else if rv.opcode(entry.instruction) == rv.OPCODE_BRANCH {
		append_part(&builder, "branch not taken")
	}
	return strings.to_string(builder)
}

package view

import "core:fmt"
import clay "../../vendor/clay-odin"
import rv "../../core"
import disasm "../../disasm"
import ui "../ui"
import state "../state"

// The CSRs tab: the privilege level and every implemented CSR, what each
// value means (csr_meaning.odin), and what the last step changed.

// The privilege level and every implemented CSR (see csr_meaning.odin).
// Whatever the last step changed comes first, highlighted, so it's in view
// without scrolling; the rest keep their usual order. Two rows per CSR, so
// the panel doesn't need to be wide:
//
//   #4  mstatus  0x300  0x0000000000001880
//   MIE=0 MPIE=1 MPP=Machine
//
// "#4": step 4 last wrote it (state/last_writes.odin).
@(private)
tab_csrs :: proc(session: ^state.Session) {
	colors := ui.palette()
	cpu := &session.machine.cpu

	rows := make([dynamic]ui.Table_Row, 0, 2 * len(csr_view_order) + 1, context.temp_allocator)
	append(&rows, ui.Table_Row{cells = ui.cells({}, {text = "privilege"}, {}, {text = fmt.tprintf("%v", cpu.privilege)})})
	for address in csrs_changed_first(session) {
		value, _ := rv.csr_read(cpu, address)
		highlight := colors.changed if csr_changed_by_last_step(session, address) else ui.COLOR_NONE
		append(&rows, ui.Table_Row{
			cells = ui.cells(
				{text = step_mark(state.last_write_csr(session, address)), color = colors.text_dim},
				{text = disasm.csr_name(address)},
				{text = fmt.tprintf("0x%03x", address)},
				{text = fmt.tprintf("0x%016x", value)},
			),
			background = highlight,
		})
		append(&rows, ui.Table_Row{
			cells = ui.cells({text = csr_meaning(session, address, value), color = colors.text_dim}),
			background = highlight,
			span = true,
			span_from = 1, // under the name, not the "#N" column
		})
	}
	// The "#N" column keeps its width before anything has been written.
	options := tab_table()
	options.min_columns = {"#99"}
	ui.table(clay.ID("CsrTable"), rows[:], options)
}

// csr_view_order with the CSRs the last step changed moved to the front,
// each group keeping its usual order.
@(private)
csrs_changed_first :: proc(session: ^state.Session) -> []u32 {
	ordered := make([dynamic]u32, 0, len(csr_view_order), context.temp_allocator)
	for address in csr_view_order {
		if csr_changed_by_last_step(session, address) {
			append(&ordered, address)
		}
	}
	for address in csr_view_order {
		if !csr_changed_by_last_step(session, address) {
			append(&ordered, address)
		}
	}
	return ordered[:]
}

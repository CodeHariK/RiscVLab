package view

import "core:fmt"
import clay "../../vendor/clay-odin"
import rv "../../core"
import disasm "../../disasm"
import ui "../ui"
import state "../state"

// The CSRs tab: the privilege level and every implemented CSR, what each
// value means (csr_meaning.odin), and what the last step changed.

// The privilege level and every implemented CSR (see csr_meaning.odin),
// with whatever the last step changed highlighted. Two rows per CSR, so
// the panel doesn't need to be wide:
//
//   mstatus  0x300  0x0000000000001880
//   MIE=0 MPIE=1 MPP=Machine
@(private)
tab_csrs :: proc(session: ^state.Session) {
	colors := ui.palette()
	cpu := &session.machine.cpu

	rows := make([dynamic]ui.Table_Row, 0, 2 * len(csr_view_order) + 1, context.temp_allocator)
	append(&rows, ui.Table_Row{cells = ui.cells({text = "privilege"}, {}, {text = fmt.tprintf("%v", cpu.privilege)})})
	for address in csr_view_order {
		value, _ := rv.csr_read(cpu, address)
		highlight := colors.changed if csr_changed_by_last_step(session, address) else ui.COLOR_NONE
		append(&rows, ui.Table_Row{
			cells = ui.cells(
				{text = disasm.csr_name(address)},
				{text = fmt.tprintf("0x%03x", address)},
				{text = fmt.tprintf("0x%016x", value)},
			),
			background = highlight,
		})
		append(&rows, ui.Table_Row{
			cells = ui.cells({text = csr_meaning(cpu, address, value), color = colors.text_dim}),
			background = highlight,
			span = true,
		})
	}
	ui.table(clay.ID("CsrTable"), rows[:], tab_table())
}

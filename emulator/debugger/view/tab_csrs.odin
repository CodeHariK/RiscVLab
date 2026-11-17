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
// with whatever the last step changed highlighted.
@(private)
tab_csrs :: proc(session: ^state.Session) {
	colors := ui.palette()
	cpu := &session.machine.cpu

	privilege_text := fmt.tprintf("%-9s %v", "privilege", cpu.privilege)
	if clay.UI(clay.ID("PrivilegeLine"))({layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 1, 6}}}) {
		clay.TextDynamic(privilege_text, ui.text_config(.Code_Small, colors.text))
	}

	for address, index in csr_view_order {
		value, _ := rv.csr_read(cpu, address)
		// Two lines per CSR, so the panel doesn't need to be wide:
		//   mstatus   0x300 0x0000000000001880
		//             MIE=0 MPIE=1 MPP=Machine
		text := fmt.tprintf("%-9s 0x%03x 0x%016x", disasm.csr_name(address), address, value)
		meaning := fmt.tprintf("%-9s %s", "", csr_meaning(cpu, address, value))
		highlight := colors.changed if csr_changed_by_last_step(session, address) else ui.COLOR_NONE
		if clay.UI(clay.ID("CsrLine", u32(index)))({
			layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = {6, 6, 2, 2}},
			backgroundColor = highlight,
			cornerRadius = clay.CornerRadiusAll(3),
		}) {
			clay.TextDynamic(text, ui.text_config(.Code_Small, colors.text))
			clay.TextDynamic(meaning, ui.text_config(.Code_Small, colors.text_dim))
		}
	}
}

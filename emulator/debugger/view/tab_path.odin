package view

import "core:fmt"
import "core:strings"
import clay "../../vendor/clay-odin"
import disasm "../../disasm"
import ui "../ui"
import state "../state"

// The Path tab: the emulator functions the step Next will run goes
// through, as a tree of calls with each function's file (path_text,
// step_detail.odin), next to the Encoding tab, which shows what the same
// step does. The steps already run have theirs in Steps -> Detailed.

tab_path :: proc(session: ^state.Session) {
	colors := ui.palette()
	entry, has_preview := session.preview.?
	if !has_preview {
		wrapped_text("No next step: the program has stopped.", ui.text_config(.Code_Small, colors.text_dim))
		return
	}
	buffer: [disasm.BUFFER_SIZE]u8
	text := disasm.disassemble(buffer[:], entry.pc, entry.instruction)
	wrapped_text(fmt.tprintf("Next: %08x  %s", entry.pc, text), ui.text_config(.Code_Small, colors.text_dim))
	if clay.UI()({layout = {sizing = {height = clay.SizingFixed(6)}}}) {}
	for line in strings.split_lines(path_text(entry), context.temp_allocator) {
		clay.TextDynamic(line, ui.text_config(.Code_Small, colors.text))
	}
}

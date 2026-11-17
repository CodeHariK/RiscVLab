package view

import "core:fmt"
import "core:slice"
import "core:strings"
import clay "../../vendor/clay-odin"
import rv "../../core"
import disasm "../../disasm"
import ui "../ui"
import reference "../reference"
import state "../state"

// The Docs window: what instructions, pseudo-instructions and directives
// are for, in plain words (reference/, from docs/reference/). It opens over
// everything else, with the list of entries on the left and the chosen
// entry on the right. Open it with the Docs button in the toolbar or the
// D key; Esc or Close closes it, and it reopens as it was left (search,
// entry, scroll positions).
//
// Keyboard while open: type to search (names, titles and text), Backspace
// to delete, Up / Down to go through the entries listed, Left / Right to
// step the program, so you can read along.
//
// It follows the instruction Next will run, showing up to four entries:
//   - the pseudo-instruction its source line uses (`la`, `li`, `ret`, ...),
//     first, since that is what the source says;
//   - the instruction itself;
//   - the CSR it reads or writes, for a CSR instruction;
//   - the trap cause, when it will trap (from the preview).
// Clicking an entry in the list pins that one instead, until "Follow next
// instruction" is clicked.
//
// Entry bodies are Markdown, drawn by ui.markdown (ui/markdown.odin) with
// the section labels below in a column of their own.

DOCS_ENTRY_ID :: "DocsEntry" // + entry index
DOCS_LESSON_ENTRY_ID :: "DocsLessonEntry" // + entry index, in the "This lesson" group
// How far into a source file to look for its "# Docs:" line.
LESSON_HEADER_LINES :: 10
BUTTON_ID_DOCS_FOLLOW :: "DocsFollow"
BUTTON_ID_DOCS_CLOSE :: "DocsClose"
DOCS_LIST_WIDTH :: 420
DOCS_LIST_ID :: "DocsList"
DOCS_PAGE_ID :: "DocsPage"
DOCS_LABEL_WIDTH :: 130 // fits "How it works"

doc_labels := [?]string{"Does", "Becomes", "How it works", "Fields", "For", "Pseudo", "Emulator", "Watch out", "Related", "Example"}

// Draws the window when it is open. Called last, so it lies on top.
docs_modal :: proc(session: ^state.Session) {
	if display.docs_open {
		ui.modal_window("DocsWindow", "Docs", BUTTON_ID_DOCS_CLOSE, docs_header, docs_panes, session)
	}
}

// "Follow next instruction" next to the title, once an entry is pinned.
@(private)
docs_header :: proc() {
	if display.docs_pinned >= 0 {
		ui.modal_button(BUTTON_ID_DOCS_FOLLOW, "Follow next instruction")
	}
}

// The search box and entry list on the left, the entries on the right.
@(private)
docs_panes :: proc(data: rawptr) {
	session := (^state.Session)(data)
	if clay.UI(clay.ID("DocsPanes"))({layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, childGap = 16}}) {
		shown := docs_shown_entry(session)
		if clay.UI(clay.ID("DocsLeft"))({
			layout = {sizing = {clay.SizingFixed(DOCS_LIST_WIDTH), clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = 6},
		}) {
			ui.search_box("DocsSearch", &display.docs_search, "Type to search the docs")
			ui.modal_hint("Up / Down: entries   Left / Right: step")
			ui.scroll_keep(&display.docs_list_scroll, clay.ID(DOCS_LIST_ID))
			ui.scroll_keep(&display.docs_page_scroll, clay.ID(DOCS_PAGE_ID))
			if display.docs_scroll_pending && shown >= 0 {
				if ui.scroll_into_view(clay.ID(DOCS_LIST_ID), clay.ID(DOCS_ENTRY_ID, u32(shown))) {
					display.docs_scroll_pending = false
				}
			}
			if clay.UI(clay.ID(DOCS_LIST_ID))({
				layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, layoutDirection = .TopToBottom},
				clip = {vertical = true, childOffset = clay.GetScrollOffset()},
			}) {
				docs_index(session, shown)
			}
		}
		// Clipping only up and down lets the text wrap at the pane's width.
		if clay.UI(clay.ID(DOCS_PAGE_ID))({
			layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = 2},
			clip = {vertical = true, childOffset = clay.GetScrollOffset()},
		}) {
			docs_content(session)
		}
	}
}

// The entry the list highlights: the pinned one, or the next instruction's.
docs_shown_entry :: proc(session: ^state.Session) -> int {
	if display.docs_pinned >= 0 {
		return display.docs_pinned
	}
	return reference.find(next_mnemonic(session))
}

@(private)
docs_content :: proc(session: ^state.Session) {
	colors := ui.palette()
	if display.docs_pinned >= 0 {
		docs_entry(reference.entries[display.docs_pinned], 0)
		return
	}

	mnemonic := next_mnemonic(session)
	written := source_word(session)
	pseudo := -1
	if written != "" && written != mnemonic {
		if found := reference.find(written); found >= 0 && reference.entries[found].group != .Instructions {
			pseudo = found
		}
	}
	following := fmt.tprintf("Following the next instruction: %s", mnemonic)
	if pseudo >= 0 {
		following = fmt.tprintf("%s (the source says %s)", following, written)
	}
	clay.TextDynamic(following, ui.text_config(.Code_Small, colors.text_dim))

	shown := [4]int{pseudo, reference.find(mnemonic), reference.find(next_csr_name(session)), reference.find(next_trap_name(session))}
	if shown[1] < 0 && mnemonic != "" {
		clay.TextDynamic(fmt.tprintf("No entry for %s yet.", mnemonic), ui.text_config(.Text, colors.text))
	}
	for index, slot in shown {
		if index >= 0 {
			docs_entry(reference.entries[index], u32(slot))
		}
	}
}

// The CSR the next instruction uses, e.g. "mstatus"; "" if it is not a
// CSR instruction.
@(private)
next_csr_name :: proc(session: ^state.Session) -> string {
	raw, ok := rv.bus_load(&session.machine.bus, session.machine.cpu.pc, 4)
	instruction := u32(raw)
	if !ok || rv.opcode(instruction) != rv.OPCODE_SYSTEM || rv.funct3(instruction) == 0 {
		return ""
	}
	return disasm.csr_name(rv.csr_address(instruction))
}

// The cause of the trap the next instruction will raise, as named in
// traps.md (e.g. "Illegal_Instruction"); "" if it won't trap.
@(private)
next_trap_name :: proc(session: ^state.Session) -> string {
	entry, has_preview := session.preview.?
	if !has_preview {
		return ""
	}
	trap, traps := entry.trap.?
	if !traps {
		return ""
	}
	return fmt.tprintf("%v", trap.cause)
}

// The first word of the source line the next instruction came from, e.g.
// "la" (labels and comments left out); "" without a source line.
@(private)
source_word :: proc(session: ^state.Session) -> string {
	if !session.has_source {
		return ""
	}
	line, known := state.source_line_at(&session.source, session.machine.cpu.pc)
	if !known || line < 1 || line > len(session.source.lines) {
		return ""
	}
	code := session.source.lines[line - 1]
	if hash := strings.index_byte(code, '#'); hash >= 0 {
		code = code[:hash]
	}
	words := strings.fields(code, context.temp_allocator)
	for word in words {
		if strings.has_suffix(word, ":") {
			continue // a label in front of the instruction
		}
		return word
	}
	return ""
}

// The mnemonic of the instruction at the PC, e.g. "lw"; "" outside memory.
@(private)
next_mnemonic :: proc(session: ^state.Session) -> string {
	pc := session.machine.cpu.pc
	raw, ok := rv.bus_load(&session.machine.bus, pc, 4)
	if !ok {
		return ""
	}
	buffer: [disasm.BUFFER_SIZE]u8
	text := disasm.disassemble(buffer[:], pc, u32(raw))
	// Atomics carry their ordering bits in the name (amoswap.w.aq); the
	// docs list them without.
	mnemonic := first_word(text)
	for suffix in ([]string{".aqrl", ".aq", ".rl"}) {
		if strings.has_suffix(mnemonic, suffix) {
			mnemonic = mnemonic[:len(mnemonic) - len(suffix)]
			break
		}
	}
	return strings.clone(mnemonic, context.temp_allocator)
}

// `slot` keeps the ids of the (up to two) entries shown apart.
@(private)
docs_entry :: proc(entry: reference.Entry, slot: u32) {
	colors := ui.palette()
	if clay.UI(clay.ID("DocsEntryShown", slot))({layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = {top = 8, bottom = 16}, childGap = 3}}) {
		clay.TextDynamic(reference.entry_heading(entry), ui.text_config(.Title, colors.title))
		ui.markdown(fmt.tprintf("DocsEntry%d", slot), entry.lines, doc_labels[:], DOCS_LABEL_WIDTH)
	}
}

// The open lesson's entries first ("This lesson", without a search), then
// the entries that match the search, grouped by file; click one to pin
// it. With a search, entries whose heading matches come first, so a group
// can appear twice.
@(private)
docs_index :: proc(session: ^state.Session, shown: int) {
	colors := ui.palette()
	if lesson := lesson_doc_entries(session); len(lesson) > 0 && display.docs_search.length == 0 {
		if clay.UI(clay.ID("DocsLessonTitle"))({layout = {padding = {top = 4, bottom = 4}}}) {
			clay.TextDynamic("This lesson", ui.text_config(.Title, colors.title))
		}
		for index in lesson {
			docs_row(DOCS_LESSON_ENTRY_ID, index, shown)
		}
	}
	matches := docs_filtered()
	if len(matches) == 0 {
		clay.TextDynamic("Nothing matches the search.", ui.text_config(.Code_Small, colors.text_dim))
	}
	previous_group := -1
	headings: u32 = 0
	for index in matches {
		entry := reference.entries[index]
		if int(entry.group) != previous_group {
			previous_group = int(entry.group)
			headings += 1
			if clay.UI(clay.ID("DocsGroupTitle", headings))({layout = {padding = {top = 10, bottom = 4}}}) {
				clay.TextDynamic(reference.group_names[entry.group], ui.text_config(.Title, colors.title))
			}
		}
		docs_row(DOCS_ENTRY_ID, index, shown)
	}
}

// One clickable entry in the list (`id` + the entry's index).
@(private)
docs_row :: proc(id: string, index: int, shown: int) {
	colors := ui.palette()
	element_id := clay.ID(id, u32(index))
	background := ui.COLOR_NONE
	if index == shown {
		background = colors.current_line
	} else if clay.PointerOver(element_id) {
		background = colors.button_hover
	}
	if clay.UI(element_id)({
		layout = {sizing = {width = clay.SizingGrow()}, padding = {8, 8, 3, 3}},
		backgroundColor = background,
		cornerRadius = clay.CornerRadiusAll(4),
	}) {
		clay.TextDynamic(reference.entry_heading(reference.entries[index]), ui.text_config(.Code_Small, colors.text))
	}
}

// The entries that match the Docs window's search box.
docs_filtered :: proc() -> []int {
	return reference.filter(ui.search_text(&display.docs_search))
}

// The entries the open program names on a "# Docs: a, b, c" line near the
// top of its source (every lesson has one), in that order.
lesson_doc_entries :: proc(session: ^state.Session) -> []int {
	if !session.has_source {
		return nil
	}
	entries := make([dynamic]int, context.temp_allocator)
	for line, number in session.source.lines {
		if number >= LESSON_HEADER_LINES {
			break
		}
		text := strings.trim_space(line)
		if !strings.has_prefix(text, "# Docs:") {
			continue
		}
		for name in strings.split(text[len("# Docs:"):], ",", context.temp_allocator) {
			index := reference.find(strings.trim_space(name))
			if index >= 0 && !slice.contains(entries[:], index) {
				append(&entries, index)
			}
		}
	}
	return entries[:]
}

// After opening a program: the Docs window starts on the lesson's first
// entry (or follows the next instruction if it names none).
docs_show_lesson :: proc(session: ^state.Session) {
	entries := lesson_doc_entries(session)
	display.docs_pinned = entries[0] if len(entries) > 0 else -1
	display.docs_scroll_pending = true
	display.docs_page_scroll.position = {}
}

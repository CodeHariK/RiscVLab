package view

import "core:fmt"
import "core:slice"
import "core:strings"
import clay "../../vendor/clay-odin"
import rl "vendor:raylib"
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
// Clicking an entry in the list, or a link on an entry's Related line
// (docs_related.odin), pins that one instead, until "Follow next
// instruction" is clicked. A link under "Lessons" opens that lesson
// and closes the window.
//
// Entry bodies are Markdown, drawn by ui.markdown (ui/markdown.odin) with
// the section labels below in a column of their own.

DOCS_ENTRY_ID :: "DocsEntry" // + entry index
DOCS_LESSON_ENTRY_ID :: "DocsLessonEntry" // + entry index, in the "This lesson" group
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
			docs_scroll_to_section()
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

// After a link to "entry#Section": once the entry is on the page, scroll
// so that section's heading is at the top.
@(private)
docs_scroll_to_section :: proc() {
	section := display.docs_section_pending
	if section < 0 {
		return
	}
	if display.docs_pinned != display.docs_section_entry {
		display.docs_section_pending = -1 // another entry was chosen first
		return
	}
	if display.docs_page_drawn != display.docs_pinned {
		return // not on the page yet
	}
	if ui.scroll_to_top(clay.ID(DOCS_PAGE_ID), clay.ID(docs_heading_id(0), u32(section))) {
		display.docs_section_pending = -1
	}
}

// The id of the "### " headings of the entry in page slot `slot` (+ the
// section's number in the entry).
docs_heading_id :: proc(slot: u32) -> string {
	return fmt.tprintf("DocsHeading%d", slot)
}

// How wide the entry page is: the window, less its margins, padding and
// border, the list on the left and the gap after it. Worked out from the
// screen rather than read from the layout: content too wide for the page
// would widen it, and a width read back from it would never shrink.
docs_page_width :: proc() -> f32 {
	window := f32(rl.GetScreenWidth()) - 2 * (ui.MODAL_MARGIN + ui.PANEL_PADDING + ui.BORDER_WIDTH)
	return window - DOCS_LIST_WIDTH - 16 // 16: the gap between list and page (docs_panes)
}

// The entry the list highlights: the pinned one, or the next instruction's.
docs_shown_entry :: proc(session: ^state.Session) -> int {
	if display.docs_pinned >= 0 {
		return display.docs_pinned
	}
	return reference.find(next_mnemonic(session))
}

// The entries on the page, by slot: the pinned one alone in slot 0, or
// those for the next instruction (see the top of this file): its
// pseudo-instruction, the instruction, its CSR, its trap. -1 = empty slot.
// The slot keeps each entry's element ids apart.
docs_page_entries :: proc(session: ^state.Session) -> [4]int {
	if display.docs_pinned >= 0 {
		return {display.docs_pinned, -1, -1, -1}
	}
	mnemonic := next_mnemonic(session)
	return {
		docs_pseudo_entry(session, mnemonic),
		reference.find(mnemonic),
		reference.find(next_csr_name(session)),
		reference.find(next_trap_name(session)),
	}
}

// The entry for the pseudo-instruction the source line uses for the next
// instruction (`la` for an auipc), or -1 if the source says the same as
// the disassembly.
@(private)
docs_pseudo_entry :: proc(session: ^state.Session, mnemonic: string) -> int {
	written := source_word(session)
	if written == "" || written == mnemonic {
		return -1
	}
	if found := reference.find(written); found >= 0 && reference.entries[found].group != .Instructions {
		return found
	}
	return -1
}

@(private)
docs_content :: proc(session: ^state.Session) {
	colors := ui.palette()
	shown := docs_page_entries(session)
	display.docs_page_drawn = display.docs_pinned
	if display.docs_pinned < 0 {
		mnemonic := next_mnemonic(session)
		following := fmt.tprintf("Following the next instruction: %s", mnemonic)
		if shown[0] >= 0 {
			following = fmt.tprintf("%s (the source says %s)", following, source_word(session))
		}
		clay.TextDynamic(following, ui.text_config(.Code_Small, colors.text_dim))
		if shown[1] < 0 && mnemonic != "" {
			clay.TextDynamic(fmt.tprintf("No entry for %s yet.", mnemonic), ui.text_config(.Text, colors.text))
		}
	}
	for index, slot in shown {
		if index >= 0 {
			docs_entry(index, u32(slot))
		}
	}
}

// The CSR the next instruction uses, e.g. "mstatus"; "" if it is not a
// CSR instruction.
@(private)
next_csr_name :: proc(session: ^state.Session) -> string {
	raw, ok := rv.machine_peek(&session.machine, session.machine.cpu.pc, 4)
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
	if rv.trap_is_interrupt(trap.cause) {
		return "interrupt" // one entry covers them all
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
	raw, ok := rv.machine_peek(&session.machine, pc, 4)
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

// Entry `index`; `slot` keeps the ids of the (up to four) entries shown
// apart. The body is Markdown, except the Related line, drawn as links
// where it stands, followed by links to the lessons about the entry
// (docs_related.odin).
@(private)
docs_entry :: proc(index: int, slot: u32) {
	colors := ui.palette()
	entry := reference.entries[index]
	if clay.UI(clay.ID("DocsEntryShown", slot))({layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = {top = 8, bottom = 16}, childGap = 3}}) {
		clay.TextDynamic(reference.entry_heading(entry), ui.text_config(.Title, colors.title))
		related := -1
		for line, at in entry.lines {
			if strings.has_prefix(line, reference.RELATED_LABEL) {
				related = at
				break
			}
		}
		if related < 0 {
			ui.markdown(fmt.tprintf("DocsEntry%d", slot), entry.lines, doc_labels[:], DOCS_LABEL_WIDTH, docs_page_width(), docs_heading_id(slot))
			docs_lesson_links(index, slot)
			return
		}
		// Two Markdown parts need two ids, for their tables' ids.
		// The headings after the Related line go on numbering from the
		// ones before it.
		before := entry.lines[:related]
		headings_before: u32 = 0
		for line in before {
			if strings.has_prefix(line, reference.SECTION_PREFIX) {
				headings_before += 1
			}
		}
		ui.markdown(fmt.tprintf("DocsEntry%d", slot), before, doc_labels[:], DOCS_LABEL_WIDTH, docs_page_width(), docs_heading_id(slot))
		docs_related_links(entry, slot)
		docs_lesson_links(index, slot)
		ui.markdown(fmt.tprintf("DocsEntry%dAfter", slot), entry.lines[related + 1:], doc_labels[:], DOCS_LABEL_WIDTH, docs_page_width(), docs_heading_id(slot), headings_before)
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
		if number >= state.HEADER_LINES {
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

package rvdbg

import "core:fmt"
import "core:slice"
import "core:strings"
import clay "../vendor/clay-odin"
import rv "../core"

// The Docs window: what instructions, pseudo-instructions and directives
// are for, in plain words (docs.odin, from docs/reference/). It opens over
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
// Body lines are drawn by kind, in two columns: section labels on the
// left, everything else in the text column, so a section reads as one
// block:
//   "Does: ..."         a section label (Does, Becomes, How it works, ...)
//                       and its first text
//   "- ..." / "1. ..."  a bullet or numbered step, wrapped under itself
//   ``` ... ```         a code block, in the code colour
//   "*U-type, RV64I*"   the format line, dimmed
//   anything else       more text of the current section
// Backticks (Markdown code marks) are left out.

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
DOCS_MARKER_WIDTH :: 28 // "-" or "1." in front of a bullet or step

doc_labels := [?]string{"Does", "Becomes", "How it works", "Fields", "For", "Pseudo", "Emulator", "Watch out", "Related", "Example"}

// Draws the window when it is open. Called last, so it lies on top.
docs_modal :: proc(session: ^Session) {
	if view.docs_open {
		modal_window(session, "DocsWindow", "Docs", BUTTON_ID_DOCS_CLOSE, docs_header, docs_panes)
	}
}

// "Follow next instruction" next to the title, once an entry is pinned.
@(private = "file")
docs_header :: proc() {
	if view.docs_pinned >= 0 {
		modal_button(BUTTON_ID_DOCS_FOLLOW, "Follow next instruction")
	}
}

// The search box and entry list on the left, the entries on the right.
@(private = "file")
docs_panes :: proc(session: ^Session) {
	if clay.UI(clay.ID("DocsPanes"))({layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, childGap = 16}}) {
		shown := docs_shown_entry(session)
		if clay.UI(clay.ID("DocsLeft"))({
			layout = {sizing = {clay.SizingFixed(DOCS_LIST_WIDTH), clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = 6},
		}) {
			search_box("DocsSearch", &view.docs_search, "Type to search the docs")
			modal_hint("Up / Down: entries   Left / Right: step")
			scroll_keep(&view.docs_list_scroll, clay.ID(DOCS_LIST_ID))
			scroll_keep(&view.docs_page_scroll, clay.ID(DOCS_PAGE_ID))
			if view.docs_scroll_pending && shown >= 0 {
				if scroll_into_view(clay.ID(DOCS_LIST_ID), clay.ID(DOCS_ENTRY_ID, u32(shown))) {
					view.docs_scroll_pending = false
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
docs_shown_entry :: proc(session: ^Session) -> int {
	if view.docs_pinned >= 0 {
		return view.docs_pinned
	}
	return docs_find(next_mnemonic(session))
}

@(private = "file")
docs_content :: proc(session: ^Session) {
	colors := palette()
	if view.docs_pinned >= 0 {
		docs_entry(docs.entries[view.docs_pinned], 0)
		return
	}

	mnemonic := next_mnemonic(session)
	written := source_word(session)
	pseudo := -1
	if written != "" && written != mnemonic {
		if found := docs_find(written); found >= 0 && docs.entries[found].group != .Instructions {
			pseudo = found
		}
	}
	following := fmt.tprintf("Following the next instruction: %s", mnemonic)
	if pseudo >= 0 {
		following = fmt.tprintf("%s (the source says %s)", following, written)
	}
	clay.TextDynamic(following, text_config(.Code_Small, colors.text_dim))

	shown := [4]int{pseudo, docs_find(mnemonic), docs_find(next_csr_name(session)), docs_find(next_trap_name(session))}
	if shown[1] < 0 && mnemonic != "" {
		clay.TextDynamic(fmt.tprintf("No entry for %s yet.", mnemonic), text_config(.Text, colors.text))
	}
	for index, slot in shown {
		if index >= 0 {
			docs_entry(docs.entries[index], u32(slot))
		}
	}
}

// The CSR the next instruction uses, e.g. "mstatus"; "" if it is not a
// CSR instruction.
@(private = "file")
next_csr_name :: proc(session: ^Session) -> string {
	raw, ok := rv.bus_load(&session.machine.bus, session.machine.cpu.pc, 4)
	instruction := u32(raw)
	if !ok || rv.opcode(instruction) != rv.OPCODE_SYSTEM || rv.funct3(instruction) == 0 {
		return ""
	}
	return rv.csr_name(rv.csr_address(instruction))
}

// The cause of the trap the next instruction will raise, as named in
// traps.md (e.g. "Illegal_Instruction"); "" if it won't trap.
@(private = "file")
next_trap_name :: proc(session: ^Session) -> string {
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
@(private = "file")
source_word :: proc(session: ^Session) -> string {
	if !session.has_source {
		return ""
	}
	line, known := source_line_at(&session.source, session.machine.cpu.pc)
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
@(private = "file")
next_mnemonic :: proc(session: ^Session) -> string {
	pc := session.machine.cpu.pc
	raw, ok := rv.bus_load(&session.machine.bus, pc, 4)
	if !ok {
		return ""
	}
	buffer: [rv.DISASM_BUFFER_SIZE]u8
	text := rv.disassemble(buffer[:], pc, u32(raw))
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
@(private = "file")
docs_entry :: proc(entry: Doc_Entry, slot: u32) {
	colors := palette()
	if clay.UI(clay.ID("DocsEntryShown", slot))({layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = {top = 8, bottom = 16}, childGap = 3}}) {
		clay.TextDynamic(docs_heading(entry), text_config(.Title, colors.title))
		in_code := false
		for line in entry.lines {
			if strings.has_prefix(strings.trim_space(line), "```") {
				in_code = !in_code
				continue
			}
			if in_code {
				docs_section_row("", "", line, colors.accent)
			} else {
				docs_line(line)
			}
		}
	}
}

// One line outside a code block: a section label with its first text, a
// bullet or numbered step, the format line, a blank line, or more text of
// the section.
@(private = "file")
docs_line :: proc(line: string) {
	colors := palette()
	if strings.trim_space(line) == "" {
		if clay.UI()({layout = {sizing = {height = clay.SizingFixed(6)}}}) {}
		return
	}
	text, _ := strings.remove_all(line, "`", context.temp_allocator)
	if strings.has_prefix(text, "*") && strings.has_suffix(text, "*") && len(text) > 1 {
		clay.TextDynamic(text[1:len(text) - 1], text_config(.Code_Small, colors.text_dim))
		return
	}
	for label in doc_labels {
		if strings.has_prefix(text, label) && strings.has_prefix(text[len(label):], ":") {
			if clay.UI()({layout = {sizing = {height = clay.SizingFixed(4)}}}) {}
			docs_section_row(label, "", strings.trim_space(text[len(label) + 1:]), colors.text)
			return
		}
	}
	if strings.has_prefix(text, "- ") {
		docs_section_row("", "-", text[2:], colors.text)
		return
	}
	if marker, rest, numbered := numbered_step(text); numbered {
		docs_section_row("", marker, rest, colors.text)
		return
	}
	docs_section_row("", "", text, colors.text)
}

// "1. text" -> ("1.", "text", true).
@(private = "file")
numbered_step :: proc(text: string) -> (marker: string, rest: string, ok: bool) {
	digits := 0
	for digits < len(text) && text[digits] >= '0' && text[digits] <= '9' {
		digits += 1
	}
	if digits == 0 || !strings.has_prefix(text[digits:], ". ") {
		return "", "", false
	}
	return text[:digits + 1], text[digits + 2:], true
}

// A row in the label column layout: the section label (or nothing), then
// an optional bullet / step marker, then the text, which wraps within its
// own column so continued lines stay lined up.
@(private = "file")
docs_section_row :: proc(label: string, marker: string, text: string, color: clay.Color) {
	colors := palette()
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = 8}}) {
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(DOCS_LABEL_WIDTH)}}}) {
			if label != "" {
				clay.TextDynamic(label, text_config(.Code_Small, colors.accent))
			}
		}
		if marker != "" {
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(DOCS_MARKER_WIDTH)}}}) {
				clay.TextDynamic(marker, text_config(.Code_Small, colors.text_dim))
			}
		}
		if text != "" {
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}}}) {
				clay.TextDynamic(text, text_config(.Code_Small, color))
			}
		}
	}
}

// The open lesson's entries first ("This lesson", without a search), then
// the entries that match the search, grouped by file; click one to pin
// it. With a search, entries whose heading matches come first, so a group
// can appear twice.
@(private = "file")
docs_index :: proc(session: ^Session, shown: int) {
	colors := palette()
	if lesson := lesson_doc_entries(session); len(lesson) > 0 && view.docs_search.length == 0 {
		if clay.UI(clay.ID("DocsLessonTitle"))({layout = {padding = {top = 4, bottom = 4}}}) {
			clay.TextDynamic("This lesson", text_config(.Title, colors.title))
		}
		for index in lesson {
			docs_row(DOCS_LESSON_ENTRY_ID, index, shown)
		}
	}
	matches := docs_filtered()
	if len(matches) == 0 {
		clay.TextDynamic("Nothing matches the search.", text_config(.Code_Small, colors.text_dim))
	}
	previous_group := -1
	headings: u32 = 0
	for index in matches {
		entry := docs.entries[index]
		if int(entry.group) != previous_group {
			previous_group = int(entry.group)
			headings += 1
			if clay.UI(clay.ID("DocsGroupTitle", headings))({layout = {padding = {top = 10, bottom = 4}}}) {
				clay.TextDynamic(doc_group_names[entry.group], text_config(.Title, colors.title))
			}
		}
		docs_row(DOCS_ENTRY_ID, index, shown)
	}
}

// One clickable entry in the list (`id` + the entry's index).
@(private = "file")
docs_row :: proc(id: string, index: int, shown: int) {
	colors := palette()
	element_id := clay.ID(id, u32(index))
	background := COLOR_NONE
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
		clay.TextDynamic(docs_heading(docs.entries[index]), text_config(.Code_Small, colors.text))
	}
}

// The entries the open program names on a "# Docs: a, b, c" line near the
// top of its source (every lesson has one), in that order.
lesson_doc_entries :: proc(session: ^Session) -> []int {
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
			index := docs_find(strings.trim_space(name))
			if index >= 0 && !slice.contains(entries[:], index) {
				append(&entries, index)
			}
		}
	}
	return entries[:]
}

// After opening a program: the Docs window starts on the lesson's first
// entry (or follows the next instruction if it names none).
docs_show_lesson :: proc(session: ^Session) {
	entries := lesson_doc_entries(session)
	view.docs_pinned = entries[0] if len(entries) > 0 else -1
	view.docs_scroll_pending = true
	view.docs_page_scroll.position = {}
}

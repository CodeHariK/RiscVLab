package rvdbg

import "core:fmt"
import "core:strings"
import clay "../vendor/clay-odin"
import rv "../core"

// The Docs tab of the side panel: what an instruction is for, in plain
// words (docs.odin, from docs/reference/). It follows the instruction Next
// will run; clicking an entry in the list below pins that one instead,
// until "Follow next instruction" is clicked.
//
// Body lines are drawn by kind:
//   "Does: ..."         label (Does, For, Pseudo, Watch out, Related, Example) + text
//   "    code"          an example, in the code colour
//   "*U-type, RV64I*"   the format line, dimmed
// Backticks (Markdown code marks) are left out.

DOCS_ENTRY_ID :: "DocsEntry" // + entry index
BUTTON_ID_DOCS_FOLLOW :: "DocsFollow"
DOCS_LABEL_WIDTH :: 100

doc_labels := [?]string{"Does", "For", "Pseudo", "Watch out", "Related", "Example"}

docs_view :: proc(session: ^Session) {
	// The side panel's content area scrolls, and in Clay a scrolling area
	// lets its children be as wide as they like, so text would never wrap.
	// Giving the docs the area's width (from last frame) makes long lines
	// wrap at the panel's edge.
	area := clay.GetElementData(clay.ID("SideContent")).boundingBox
	width := clay.SizingGrow()
	if area.width > 0 {
		width = clay.SizingFixed(area.width)
	}
	if clay.UI(clay.ID("DocsView"))({layout = {sizing = {width = width}, layoutDirection = .TopToBottom, childGap = 2}}) {
		docs_content(session)
	}
}

@(private = "file")
docs_content :: proc(session: ^Session) {
	colors := palette()
	shown := view.docs_pinned
	if shown < 0 {
		mnemonic := next_mnemonic(session)
		shown = docs_find(mnemonic)
		clay.TextDynamic(fmt.tprintf("Following the next instruction: %s", mnemonic), text_config(.Code_Small, colors.text_dim))
		if shown < 0 && mnemonic != "" {
			clay.TextDynamic(fmt.tprintf("No entry for %s yet.", mnemonic), text_config(.Text, colors.text))
		}
	} else {
		docs_follow_button()
	}
	if shown >= 0 {
		docs_entry(docs.entries[shown])
	}
	docs_index(shown)
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
	return strings.clone(first_word(text), context.temp_allocator)
}

@(private = "file")
docs_follow_button :: proc() {
	colors := palette()
	element_id := clay.ID(BUTTON_ID_DOCS_FOLLOW)
	if clay.UI(element_id)({
		layout = {padding = {10, 10, 4, 4}},
		backgroundColor = colors.button_hover if clay.PointerOver(element_id) else colors.button,
		cornerRadius = clay.CornerRadiusAll(CORNER_RADIUS),
		border = {colors.border, clay.BorderOutside(BORDER_WIDTH)},
	}) {
		clay.TextDynamic("Follow next instruction", text_config(.Code_Small, colors.button_text))
	}
}

@(private = "file")
docs_entry :: proc(entry: Doc_Entry) {
	colors := palette()
	if clay.UI(clay.ID("DocsEntryShown"))({layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = {top = 8, bottom = 12}, childGap = 2}}) {
		clay.TextDynamic(docs_heading(entry), text_config(.Title, colors.title))
		for line in entry.lines {
			docs_line(line)
		}
	}
}

@(private = "file")
docs_line :: proc(line: string) {
	colors := palette()
	if strings.trim_space(line) == "" {
		if clay.UI()({layout = {sizing = {height = clay.SizingFixed(6)}}}) {}
		return
	}
	if strings.has_prefix(line, "    ") {
		if clay.UI()({layout = {padding = {left = 16}}}) {
			clay.TextDynamic(line[4:], text_config(.Code_Small, colors.accent))
		}
		return
	}
	text, _ := strings.remove_all(line, "`", context.temp_allocator)
	if strings.has_prefix(text, "*") && strings.has_suffix(text, "*") && len(text) > 1 {
		clay.TextDynamic(text[1:len(text) - 1], text_config(.Code_Small, colors.text_dim))
		return
	}
	for label in doc_labels {
		if strings.has_prefix(text, label) && strings.has_prefix(text[len(label):], ":") {
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = 8}}) {
				if clay.UI()({layout = {sizing = {width = clay.SizingFixed(DOCS_LABEL_WIDTH)}}}) {
					clay.TextDynamic(label, text_config(.Code_Small, colors.accent))
				}
				clay.TextDynamic(strings.trim_space(text[len(label) + 1:]), text_config(.Code_Small, colors.text))
			}
			return
		}
	}
	clay.TextDynamic(text, text_config(.Code_Small, colors.text))
}

// Every entry; click one to pin it.
@(private = "file")
docs_index :: proc(shown: int) {
	colors := palette()
	if clay.UI(clay.ID("DocsIndexTitle"))({layout = {padding = {top = 6, bottom = 4}}}) {
		clay.TextDynamic("All instructions", text_config(.Title, colors.title))
	}
	for entry, index in docs.entries {
		element_id := clay.ID(DOCS_ENTRY_ID, u32(index))
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
			clay.TextDynamic(docs_heading(entry), text_config(.Code_Small, colors.text))
		}
	}
}

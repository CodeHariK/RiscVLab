package rvdbg

import "core:fmt"
import "core:strings"
import clay "../vendor/clay-odin"
import rl "vendor:raylib"
import rv "../core"

// The Docs window: what instructions, pseudo-instructions and directives
// are for, in plain words (docs.odin, from docs/reference/). It opens over
// everything else, with the list of entries on the left and the chosen
// entry on the right. Open and close it with the Docs button in the
// toolbar or the D key; Esc or Close also close it. The arrow keys still
// step while it is open, so you can read along.
//
// It follows the instruction Next will run; when its source line uses a
// pseudo-instruction (`la`, `li`, `ret`, ...), that entry is shown first,
// since that is what the source says. Clicking an entry in the list pins
// that one instead, until "Follow next instruction" is clicked.
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
BUTTON_ID_DOCS_FOLLOW :: "DocsFollow"
BUTTON_ID_DOCS_CLOSE :: "DocsClose"
DOCS_LIST_WIDTH :: 420
DOCS_MARGIN :: 48 // space left around the window
DOCS_OVERLAY_COLOR :: clay.Color{20, 10, 40, 110}
DOCS_LABEL_WIDTH :: 130 // fits "How it works"
DOCS_MARKER_WIDTH :: 28 // "-" or "1." in front of a bullet or step

doc_labels := [?]string{"Does", "Becomes", "How it works", "For", "Pseudo", "Watch out", "Related", "Example"}

// Draws the window when it is open. Called last, so it lies on top.
docs_modal :: proc(session: ^Session) {
	if !view.docs_open {
		return
	}
	colors := palette()
	if clay.UI(clay.ID("DocsOverlay"))({
		layout = {
			sizing = {clay.SizingFixed(f32(rl.GetScreenWidth())), clay.SizingFixed(f32(rl.GetScreenHeight()))},
			padding = clay.PaddingAll(DOCS_MARGIN),
		},
		floating = {attachTo = .Root, zIndex = 100, pointerCaptureMode = .Capture},
		backgroundColor = DOCS_OVERLAY_COLOR,
	}) {
		if clay.UI(clay.ID("DocsWindow"))({
			layout = {
				sizing = {clay.SizingGrow(), clay.SizingGrow()},
				layoutDirection = .TopToBottom,
				padding = clay.PaddingAll(PANEL_PADDING),
				childGap = 10,
			},
			backgroundColor = colors.panel,
			cornerRadius = clay.CornerRadiusAll(CORNER_RADIUS),
			border = {colors.border, clay.BorderOutside(BORDER_WIDTH)},
		}) {
			docs_header()
			if clay.UI(clay.ID("DocsPanes"))({layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, childGap = 16}}) {
				shown := docs_shown_entry(session)
				if clay.UI(clay.ID("DocsList"))({
					layout = {sizing = {clay.SizingFixed(DOCS_LIST_WIDTH), clay.SizingGrow()}, layoutDirection = .TopToBottom},
					clip = {vertical = true, childOffset = clay.GetScrollOffset()},
				}) {
					docs_index(shown)
				}
				// Clipping only up and down lets the text wrap at the
				// pane's width.
				if clay.UI(clay.ID("DocsPage"))({
					layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = 2},
					clip = {vertical = true, childOffset = clay.GetScrollOffset()},
				}) {
					docs_content(session)
				}
			}
		}
	}
}

@(private = "file")
docs_header :: proc() {
	colors := palette()
	if clay.UI(clay.ID("DocsHeader"))({layout = {sizing = {width = clay.SizingGrow()}, childGap = 10, childAlignment = {y = .Center}}}) {
		clay.TextDynamic("Docs", text_config(.Title, colors.title))
		if view.docs_pinned >= 0 {
			docs_button(BUTTON_ID_DOCS_FOLLOW, "Follow next instruction")
		}
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}}}) {}
		docs_button(BUTTON_ID_DOCS_CLOSE, "Close (Esc)")
	}
}

// The entry the list highlights: the pinned one, or the next instruction's.
@(private = "file")
docs_shown_entry :: proc(session: ^Session) -> int {
	if view.docs_pinned >= 0 {
		return view.docs_pinned
	}
	return docs_find(next_mnemonic(session))
}

@(private = "file")
docs_content :: proc(session: ^Session) {
	colors := palette()
	shown := view.docs_pinned
	if shown < 0 {
		mnemonic := next_mnemonic(session)
		shown = docs_find(mnemonic)
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
		if pseudo >= 0 {
			docs_entry(docs.entries[pseudo], 0)
		}
		if shown < 0 && mnemonic != "" {
			clay.TextDynamic(fmt.tprintf("No entry for %s yet.", mnemonic), text_config(.Text, colors.text))
		}
	}
	if shown >= 0 {
		docs_entry(docs.entries[shown], 1)
	}
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
	return strings.clone(first_word(text), context.temp_allocator)
}

@(private = "file")
docs_button :: proc(id: string, label: string) {
	colors := palette()
	element_id := clay.ID(id)
	if clay.UI(element_id)({
		layout = {padding = {10, 10, 4, 4}},
		backgroundColor = colors.button_hover if clay.PointerOver(element_id) else colors.button,
		cornerRadius = clay.CornerRadiusAll(CORNER_RADIUS),
		border = {colors.border, clay.BorderOutside(BORDER_WIDTH)},
	}) {
		clay.TextDynamic(label, text_config(.Code_Small, colors.button_text))
	}
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

// Every entry, grouped by file; click one to pin it.
@(private = "file")
docs_index :: proc(shown: int) {
	colors := palette()
	previous_group := -1
	for entry, index in docs.entries {
		if int(entry.group) != previous_group {
			previous_group = int(entry.group)
			if clay.UI(clay.ID("DocsGroupTitle", u32(entry.group)))({layout = {padding = {top = 10, bottom = 4}}}) {
				clay.TextDynamic(doc_group_names[entry.group], text_config(.Title, colors.title))
			}
		}
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

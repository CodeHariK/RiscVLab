package view

import "core:path/filepath"
import "core:strings"
import clay "../../vendor/clay-odin"
import ui "../ui"
import state "../state"

// The Programs window: every program the debugger can open (state.catalog.odin),
// grouped, with its title and description. Open it with the Programs
// button, the P key or ~ (the key left of 1).
//
// Keyboard: type to search (title, description, file name), Backspace to
// delete, Up / Down to choose, Enter to open the chosen program, Esc to
// close. A click on a program opens it too. Opening a program closes the
// window. The search, the choice and the scroll position stay as they
// were for the next time it opens.

BUTTON_ID_PROGRAMS_CLOSE :: "ProgramsClose"
PROGRAM_ROW_ID :: "ProgramRow" // + catalog index
PROGRAM_LIST_ID :: "ProgramList"

// Catalog indices that match the search, in catalog order.
programs_filtered :: proc() -> []int {
	query := ui.search_text(&display.programs_search)
	matches := make([dynamic]int, context.temp_allocator)
	for entry, index in state.catalog.entries {
		text := strings.to_lower(
			strings.join({entry.title, entry.description, filepath.base(entry.path), state.catalog_group_names[entry.group]}, " ", context.temp_allocator),
			context.temp_allocator,
		)
		if ui.search_matches(query, text) {
			append(&matches, index)
		}
	}
	return matches[:]
}

programs_modal :: proc(session: ^state.Session) {
	if display.programs_open {
		ui.modal_window("ProgramsWindow", "Programs", BUTTON_ID_PROGRAMS_CLOSE, nil, programs_content, session)
	}
}

@(private)
programs_content :: proc(data: rawptr) {
	session := (^state.Session)(data)
	colors := ui.palette()
	ui.search_box("ProgramsSearch", &display.programs_search, "Type to search programs")
	ui.modal_hint("Up / Down to choose, Enter to open, Esc to close")

	matches := programs_filtered()
	display.program_cursor = clamp(display.program_cursor, 0, max(0, len(matches) - 1))
	ui.scroll_keep(&display.programs_list_scroll, clay.ID(PROGRAM_LIST_ID))
	if display.programs_scroll_pending && len(matches) > 0 {
		row := clay.ID(PROGRAM_ROW_ID, u32(matches[display.program_cursor]))
		if ui.scroll_into_view(clay.ID(PROGRAM_LIST_ID), row) {
			display.programs_scroll_pending = false
		}
	}

	if clay.UI(clay.ID(PROGRAM_LIST_ID))({
		layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = 2},
		clip = {vertical = true, childOffset = clay.GetScrollOffset()},
	}) {
		if len(state.catalog.entries) == 0 {
			clay.TextDynamic("No program list: start rvdbg with --tests <tests folder>.", ui.text_config(.Text, colors.text_dim))
			return
		}
		if len(matches) == 0 {
			clay.TextDynamic("No program matches the search.", ui.text_config(.Text, colors.text_dim))
		}
		previous_group := -1
		for index, position in matches {
			entry := state.catalog.entries[index]
			if int(entry.group) != previous_group {
				previous_group = int(entry.group)
				if clay.UI(clay.ID("ProgramGroup", u32(entry.group)))({layout = {padding = {4, 4, 10, 4}}}) {
					clay.TextDynamic(state.catalog_group_names[entry.group], ui.text_config(.Title, colors.title))
				}
			}
			program_row(index, entry, position == display.program_cursor)
		}
	}
}

// One program: title (marked if it is the one open) and description. The
// chosen row has the current-line background.
@(private)
program_row :: proc(index: int, entry: state.Catalog_Entry, chosen: bool) {
	colors := ui.palette()
	element_id := clay.ID(PROGRAM_ROW_ID, u32(index))
	background := ui.COLOR_NONE
	if chosen {
		background = colors.current_line
	} else if clay.PointerOver(element_id) {
		background = colors.button_hover
	}
	if clay.UI(element_id)({
		layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = {8, 8, 4, 4}, childGap = 2},
		backgroundColor = background,
		cornerRadius = clay.CornerRadiusAll(4),
	}) {
		title := entry.title
		if index == display.selected_program {
			title = strings.concatenate({title, "   (open)"}, context.temp_allocator)
		}
		clay.TextDynamic(title, ui.text_config(.Text, colors.text))
		if entry.description != "" {
			clay.TextDynamic(entry.description, ui.text_config(.Code_Small, colors.text_dim))
		}
	}
}

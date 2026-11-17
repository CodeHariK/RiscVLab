package rvdbg

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import ui "ui"
import view "view"
import state "state"

// The debugger remembers how it was left: theme, panel layout, the tab
// each panel shows, the Steps and Memory modes, and the last program
// opened. Saved as JSON in the user's config folder
// (~/Library/Application Support/RiscVLab/rvdbg.json on macOS), not in
// the repository.
//
// Loaded once at startup (settings_load), and checked: a value that
// doesn't fit (a layout without some panel, a tab its panel doesn't have)
// is replaced by the default. Saved (settings_save) right after anything
// it holds changes: the Theme button, the end of a drag, a tab click,
// opening a program, Reset layout, and on quit.
//
// Enums are written by name, so the file reads well and survives enums
// gaining values. Fields missing from the file keep their defaults;
// unknown ones are ignored, so files from older or newer builds load.

SETTINGS_FOLDER :: "RiscVLab"
SETTINGS_FILE :: "rvdbg.json"

Saved_Settings :: struct {
	theme:          ui.Theme_Choice,
	layout:         view.Saved_Layout,
	selected_tab:   [view.Panel]view.Tab,
	steps_detailed: bool,
	memory_layout:  view.Memory_Layout,
	// A path, not a position in the program list: adding a lesson moves
	// the others.
	last_program:   string,
}

// The settings file's path; "" if the config folder is unknown.
@(private = "file")
settings_path :: proc() -> string {
	config, error := os.user_config_dir(context.temp_allocator)
	if error != nil {
		return ""
	}
	path, join_error := filepath.join({config, SETTINGS_FOLDER, SETTINGS_FILE}, context.temp_allocator)
	if join_error != nil {
		return ""
	}
	return path
}

// Reads the file and applies what is valid. Returns the last program's
// path ("" if none was saved); the caller opens it if it still exists.
settings_load :: proc() -> (last_program: string) {
	path := settings_path()
	if path == "" {
		return ""
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		return "" // first run: nothing saved yet
	}
	// Start from the current values, so a field the file lacks keeps them.
	saved := settings_current(nil)
	if error := json.unmarshal(data, &saved, allocator = context.temp_allocator); error != nil {
		fmt.eprintfln("warning: ignoring %s: %v", path, error)
		return ""
	}

	ui.settings.theme = saved.theme
	if !view.layout_apply(saved.layout) {
		view.reset_panel_layout()
	}
	for tab, panel in saved.selected_tab {
		if tab_in_panel(tab, panel) {
			view.display.selected_tab[panel] = tab
		}
	}
	view.display.steps_detailed = saved.steps_detailed
	view.display.memory_layout = saved.memory_layout
	return saved.last_program
}

// Writes the current settings. Failing to save only loses them for next
// time, so it is reported and otherwise ignored.
settings_save :: proc(session: ^state.Session) {
	path := settings_path()
	if path == "" {
		return
	}
	data, marshal_error := json.marshal(
		settings_current(session),
		{pretty = true, use_enum_names = true},
		context.temp_allocator,
	)
	if marshal_error != nil {
		return
	}
	os.make_directory_all(filepath.dir(path))
	if error := os.write_entire_file(path, data); error != nil {
		fmt.eprintfln("warning: cannot save settings to %s: %v", path, error)
	}
}

@(private = "file")
settings_current :: proc(session: ^state.Session) -> Saved_Settings {
	settings := Saved_Settings {
		theme          = ui.settings.theme,
		layout         = view.layout_to_save(),
		selected_tab   = view.display.selected_tab,
		steps_detailed = view.display.steps_detailed,
		memory_layout  = view.display.memory_layout,
	}
	if session != nil {
		settings.last_program = session.program_path
	}
	return settings
}

@(private = "file")
tab_in_panel :: proc(tab: view.Tab, panel: view.Panel) -> bool {
	for candidate in view.panel_tabs[panel] {
		if candidate == tab {
			return true
		}
	}
	return false
}

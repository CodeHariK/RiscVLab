package rvdbg

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import clay "../vendor/clay-odin"
import rl "vendor:raylib"
import ui "ui"
import reference "reference"
import view "view"
import state "state"

// rvdbg: step debugger for the RiscVOdin core (raylib window, Clay layout).
//
//   rvdbg [program] [--tests <tests folder>] [--windowed]
//         [--steps N] [--tab <name>]... [--docs <entry>] [--screenshot <file.png>]
//
// With --tests, the Programs window lists the lessons and tests found there.
// --windowed opens a normal maximized window instead of native fullscreen
// (which on macOS is a Space of its own, out of reach of screen capture).
//
// Scripted runs, to look at the UI without clicking: --steps runs N
// instructions after opening the program, --tab selects a tab by name
// (Devices, Memory, Steps, ...; repeat for several), --docs opens the Docs
// window on an entry (a name from its heading: lw, mtvec, uart, ..., or
// entry#Section for one of its "### " sections), and
// --screenshot saves the window as a PNG once the layout has settled,
// then quits.
// A scripted run never saves the settings (settings_file.odin).
//
// Controls: Reset, Prev / Next (buttons, or the left / right arrow keys).
main :: proc() {
	os.exit(run())
}

run :: proc() -> int {
	options, ok := parse_arguments(os.args)
	if !ok {
		fmt.eprintln("usage: rvdbg [program] [--tests <folder>] [--windowed] [--steps N] [--tab <name>]... [--docs <entry>] [--screenshot <file.png>]")
		fmt.eprintln("  program              ELF or raw binary to open (default: the last one opened, or the first listed)")
		fmt.eprintln("  --tests <folder>     list the lessons and tests found in that folder")
		fmt.eprintln("  --windowed           a normal maximized window, not native fullscreen")
		fmt.eprintln("  --steps N            run N instructions after opening the program")
		fmt.eprintln("  --tab <name>         select a tab (Source, Steps, Memory, Devices, ...); repeatable")
		fmt.eprintln("  --docs <entry>       open the Docs window on that entry (lw, mtvec, uart, ..., or entry#Section)")
		fmt.eprintln("  --screenshot <file>  save the window as a PNG, then quit")
		return 2
	}
	program_path, tests_root := options.program_path, options.tests_root
	saving = !options.scripted

	view.reset_panel_layout()
	last_program := settings_load() // settings_file.odin
	reference.load()
	defer reference.destroy()
	if tests_root != "" {
		state.catalog_load(tests_root)
	}
	// No program named: reopen the last one if it is still in the list,
	// otherwise offer the list with the first one open.
	if program_path == "" && last_program != "" && state.catalog_find(last_program) >= 0 {
		program_path = last_program
	}
	if program_path == "" && len(state.catalog.entries) > 0 {
		program_path = state.catalog.entries[0].path
		view.display.programs_open = true // let the user pick one
	}
	if program_path == "" {
		fmt.eprintln("error: no program given and none found (build the tests first)")
		return 1
	}

	session: state.Session
	if !state.session_open(&session, program_path) {
		return 1
	}
	defer state.session_destroy(&session)
	view.display.selected_program = state.catalog_find(program_path)
	view.docs_show_lesson(&session)
	if options.scripted {
		view.display.programs_open = false
		for _ in 0 ..< options.steps {
			state.session_next(&session)
		}
		for tab in options.tabs {
			view.display.selected_tab[view.panel_of(tab)] = tab
		}
		if options.docs != "" {
			name, section_name := options.docs, ""
			if hash := strings.index_byte(name, '#'); hash >= 0 {
				name, section_name = name[:hash], name[hash + 1:]
			}
			entry := reference.find(name)
			if entry < 0 {
				fmt.eprintfln("error: --docs: no entry called %s", name)
				return 2
			}
			section := -1
			if section_name != "" {
				section = reference.find_section(entry, section_name)
				if section < 0 {
					fmt.eprintfln("error: --docs: %s has no section called %s", name, section_name)
					return 2
				}
			}
			view.display.docs_open = true
			view.display.docs_pinned = entry
			view.display.docs_scroll_pending = true
			view.display.docs_section_entry = entry
			view.display.docs_section_pending = section
		}
	}

	clay_memory := init_clay()
	defer free(clay_memory)

	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .MSAA_4X_HINT})
	rl.InitWindow(ui.WINDOW_WIDTH, ui.WINDOW_HEIGHT, "RiscVOdin debugger")
	defer rl.CloseWindow()
	if options.windowed || options.screenshot != "" {
		rl.MaximizeWindow()
	} else {
		start_full_screen() // window_mode_darwin.odin / window_mode_other.odin
	}
	rl.SetTargetFPS(60)
	// Esc closes the Docs window; it should not quit the debugger (raylib's
	// default).
	rl.SetExitKey(.KEY_NULL)
	ui.load_fonts()

	// Redraw only when something happens. With event waiting on, the end of
	// a frame (rl.EndDrawing) sleeps until there is input: a mouse move,
	// click, wheel, key or window resize. Nothing on screen moves by itself,
	// so an idle debugger then uses no CPU instead of redrawing 60 times a
	// second.
	//
	// Every frame that follows a wait is followed by one more without
	// waiting: some things are laid out from the previous frame (hit tests,
	// the Docs wrap width), and the extra frame lets them settle.
	//
	// A screenshot run never waits: it draws SCREENSHOT_FRAME frames, so
	// sizes taken from the previous frame (wrapping, visible lines) settle,
	// saves the last one and quits.
	wait_after_frame := false
	frame := 0
	for !rl.WindowShouldClose() {
		defer free_all(context.temp_allocator)
		frame += 1
		if wait_after_frame && options.screenshot == "" {
			rl.EnableEventWaiting()
		} else {
			rl.DisableEventWaiting()
		}
		wait_after_frame = !wait_after_frame

		// After a long wait the frame time is huge; Clay only uses it for
		// scroll momentum, so cap it.
		frame_time := min(rl.GetFrameTime(), MAX_FRAME_TIME)
		clay.SetLayoutDimensions({f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())})
		clay.SetPointerState(rl.GetMousePosition(), rl.IsMouseButtonDown(.LEFT))
		clay.UpdateScrollContainers(false, rl.GetMouseWheelMoveV(), frame_time)

		handle_input(&session)
		render_commands := view.build_layout(&session, frame_time)

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		ui.clay_raylib_render(&render_commands)
		if options.screenshot != "" && frame == SCREENSHOT_FRAME {
			saved := save_screenshot(options.screenshot)
			rl.EndDrawing()
			return 0 if saved else 1
		}
		rl.EndDrawing()
	}
	settings_save(&session)
	return 0
}

// Longest frame time passed to Clay (seconds).
MAX_FRAME_TIME :: 1.0 / 30.0

// The frame a --screenshot run saves: the first few use sizes from the
// frame before, which don't exist yet on frame 1.
SCREENSHOT_FRAME :: 5

// Saves what has been drawn this frame (before it is shown) as a PNG.
@(private = "file")
save_screenshot :: proc(path: string) -> bool {
	image := rl.LoadImageFromScreen()
	defer rl.UnloadImage(image)
	if !rl.ExportImage(image, strings.clone_to_cstring(path, context.temp_allocator)) {
		fmt.eprintfln("error: cannot write the screenshot to %s", path)
		return false
	}
	fmt.printfln("screenshot: %s (%dx%d)", path, image.width, image.height)
	return true
}

Options :: struct {
	program_path: string,
	tests_root:   string,
	windowed:     bool,
	steps:        int,
	tabs:         [dynamic]view.Tab,
	docs:         string, // --docs: the entry to open the Docs window on
	screenshot:   string,
	// Any of --steps, --tab, --docs, --screenshot: a run that isn't the user's
	// session, so it doesn't save the settings.
	scripted:     bool,
}

// Gives Clay the memory it asks for and the text-measuring callback.
@(private = "file")
init_clay :: proc() -> rawptr {
	size := clay.MinMemorySize()
	memory := make([^]u8, size)
	arena := clay.CreateArenaWithCapacityAndMemory(c.size_t(size), memory)
	clay.Initialize(arena, {ui.WINDOW_WIDTH, ui.WINDOW_HEIGHT}, {handler = clay_error})
	clay.SetMeasureTextFunction(ui.measure_text, nil)
	return memory
}

@(private = "file")
clay_error :: proc "c" (error: clay.ErrorData) {
	context = runtime.default_context()
	fmt.eprintfln("clay error: %s", string(error.errorText.chars[:error.errorText.length]))
}

@(private = "file")
parse_arguments :: proc(args: []string) -> (options: Options, ok: bool) {
	for i := 1; i < len(args); i += 1 {
		argument := args[i]
		has_value := i + 1 < len(args)
		switch {
		case argument == "--tests" && has_value:
			i += 1
			options.tests_root = args[i]
		case argument == "--windowed":
			options.windowed = true
		case argument == "--steps" && has_value:
			i += 1
			steps, parsed := strconv.parse_int(args[i])
			if !parsed || steps < 0 {
				fmt.eprintfln("error: --steps: %s is not a count", args[i])
				return {}, false
			}
			options.steps = steps
			options.scripted = true
		case argument == "--tab" && has_value:
			i += 1
			tab, found := view.tab_named(args[i])
			if !found {
				fmt.eprintfln("error: --tab: no tab called %s", args[i])
				return {}, false
			}
			append(&options.tabs, tab)
			options.scripted = true
		case argument == "--docs" && has_value:
			i += 1
			options.docs = args[i]
			options.scripted = true
		case argument == "--screenshot" && has_value:
			i += 1
			options.screenshot = args[i]
			options.scripted = true
		case options.program_path == "" && !strings.has_prefix(argument, "--"):
			options.program_path = argument
		case:
			return {}, false
		}
	}
	return options, true
}

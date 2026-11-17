package rvdbg

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import clay "../vendor/clay-odin"
import rl "vendor:raylib"
import ui "ui"
import reference "reference"
import view "view"
import state "state"

// rvdbg: step debugger for the RiscVOdin core (raylib window, Clay layout).
//
//   rvdbg [program] [--tests <tests folder>]
//
// With --tests, the Programs window lists the lessons and tests found there.
//
// Controls: Reset, Prev / Next (buttons, or the left / right arrow keys).
main :: proc() {
	os.exit(run())
}

run :: proc() -> int {
	program_path, tests_root, ok := parse_arguments(os.args)
	if !ok {
		fmt.eprintln("usage: rvdbg [program] [--tests <tests folder>]")
		fmt.eprintln("  program            ELF or raw binary to open (default: the first listed program)")
		fmt.eprintln("  --tests <folder>   list the lessons and tests found in that folder")
		return 2
	}

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

	clay_memory := init_clay()
	defer free(clay_memory)

	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .MSAA_4X_HINT})
	rl.InitWindow(ui.WINDOW_WIDTH, ui.WINDOW_HEIGHT, "RiscVOdin debugger")
	defer rl.CloseWindow()
	start_full_screen() // window_mode_darwin.odin / window_mode_other.odin
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
	wait_after_frame := false
	for !rl.WindowShouldClose() {
		defer free_all(context.temp_allocator)
		if wait_after_frame {
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
		rl.EndDrawing()
	}
	settings_save(&session)
	return 0
}

// Longest frame time passed to Clay (seconds).
MAX_FRAME_TIME :: 1.0 / 30.0

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
parse_arguments :: proc(args: []string) -> (program_path: string, tests_root: string, ok: bool) {
	for i := 1; i < len(args); i += 1 {
		if args[i] == "--tests" && i + 1 < len(args) {
			i += 1
			tests_root = args[i]
		} else if program_path == "" && !strings.has_prefix(args[i], "--") {
			program_path = args[i]
		} else {
			return "", "", false
		}
	}
	return program_path, tests_root, true
}

package rvdbg

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import clay "../vendor/clay-odin"
import rl "vendor:raylib"

// rvdbg: step debugger for the RiscVOdin core (raylib window, Clay layout).
//
//   rvdbg [program] [--tests <tests folder>]
//
// With --tests, the Programs tab lists the lessons and tests found there.
//
// Controls: Start, Prev / Next (buttons, or the left / right arrow keys).
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

	reset_panel_layout()
	if tests_root != "" {
		catalog_load(tests_root)
	}
	if program_path == "" && len(catalog.entries) > 0 {
		program_path = catalog.entries[0].path
		view.side_tab = .Programs
	}
	if program_path == "" {
		fmt.eprintln("error: no program given and none found (build the tests first)")
		return 1
	}

	session: Session
	if !session_open(&session, program_path) {
		return 1
	}
	defer session_destroy(&session)
	view.selected_program = catalog_find(program_path)

	clay_memory := init_clay()
	defer free(clay_memory)

	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .MSAA_4X_HINT})
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "RiscVOdin debugger")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	load_fonts()

	for !rl.WindowShouldClose() {
		defer free_all(context.temp_allocator)

		clay.SetLayoutDimensions({f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())})
		clay.SetPointerState(transmute(clay.Vector2)rl.GetMousePosition(), rl.IsMouseButtonDown(.LEFT))
		clay.UpdateScrollContainers(false, transmute(clay.Vector2)rl.GetMouseWheelMoveV(), rl.GetFrameTime())

		handle_input(&session)
		render_commands := build_layout(&session, rl.GetFrameTime())

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		clay_raylib_render(&render_commands)
		rl.EndDrawing()
	}
	return 0
}

// Gives Clay the memory it asks for and the text-measuring callback.
@(private = "file")
init_clay :: proc() -> rawptr {
	size := clay.MinMemorySize()
	memory := make([^]u8, size)
	arena := clay.CreateArenaWithCapacityAndMemory(c.size_t(size), memory)
	clay.Initialize(arena, {WINDOW_WIDTH, WINDOW_HEIGHT}, {handler = clay_error})
	clay.SetMeasureTextFunction(measure_text, nil)
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

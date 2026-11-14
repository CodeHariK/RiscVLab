package rvdbg

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import clay "../vendor/clay-odin"
import rl "vendor:raylib"

// rvdbg: step debugger for the RiscVOdin core (raylib window, Clay layout).
//
//   rvdbg <program>      (ELF executable or raw binary)
//
// Controls: Start, Prev / Next (buttons, or the left / right arrow keys).
main :: proc() {
	os.exit(run())
}

run :: proc() -> int {
	if len(os.args) != 2 {
		fmt.eprintln("usage: rvdbg <program>")
		return 2
	}
	program_path := os.args[1]

	image, image_ok := read_program(program_path)
	if !image_ok {
		return 1
	}
	defer delete(image)

	session, load_error := session_create(image, filepath.base(program_path))
	if load_error != nil {
		fmt.eprintfln("error: cannot load %s: %v", program_path, load_error)
		return 1
	}
	defer session_destroy(&session)

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

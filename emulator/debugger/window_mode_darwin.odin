package rvdbg

import "core:dynlib"
import rl "vendor:raylib"

// Makes the window fill the screen at startup (window_mode_other.odin
// for other systems).
//
// On macOS this is native fullscreen, as with the window's green button:
// the window moves to its own Space, and the green button or Ctrl+Cmd+F
// brings it back. raylib has no call for that (its ToggleFullscreen changes
// the display mode instead), so this asks the window itself: raylib's
// window handle on macOS is the NSWindow, and `toggleFullScreen:` is the
// method the green button calls.
//
// The message is sent through the Objective-C runtime's own functions,
// looked up in libobjc when needed. (Odin's objc_send would be the usual
// way, but it crashes this compiler version when building in parallel.)
// If anything is missing, the window is maximized instead.

OBJC_LIBRARY :: "/usr/lib/libobjc.A.dylib"

@(private = "file")
Select_Proc :: #type proc "c" (name: cstring) -> rawptr
@(private = "file")
Send_Proc :: #type proc "c" (receiver: rawptr, selector: rawptr, argument: rawptr)

start_full_screen :: proc() {
	window := rl.GetWindowHandle()
	library, loaded := dynlib.load_library(OBJC_LIBRARY)
	if window == nil || !loaded {
		rl.MaximizeWindow()
		return
	}
	select_address, found_select := dynlib.symbol_address(library, "sel_registerName")
	send_address, found_send := dynlib.symbol_address(library, "objc_msgSend")
	if !found_select || !found_send {
		rl.MaximizeWindow()
		return
	}
	select := Select_Proc(select_address)
	send := Send_Proc(send_address)
	send(window, select("toggleFullScreen:"), nil)
}

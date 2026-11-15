#+build !darwin
package rvdbg

import rl "vendor:raylib"

// Makes the window fill the screen at startup: maximized (macOS uses
// native fullscreen instead, window_mode_darwin.odin).
start_full_screen :: proc() {
	rl.MaximizeWindow()
}

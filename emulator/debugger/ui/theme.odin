package ui

import clay "../../vendor/clay-odin"

// Look of the debugger: palettes, text styles and spacing. The current
// palette depends on `settings` (settings.odin). Layout code asks
// `palette()` for colours and `text_config` for text, so it never needs
// to know which theme or font is active.

// The window size before it goes fullscreen at startup (window_mode_*.odin),
// and after leaving fullscreen. The window is resizable.
WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 800

PANEL_PADDING :: 14
PANEL_GAP :: 14
CORNER_RADIUS :: 8
BORDER_WIDTH :: 2

// ---------------------------------------------------------------- colours

Palette :: struct {
	background:   clay.Color,
	panel:        clay.Color,
	border:       clay.Color,
	text:         clay.Color,
	text_dim:     clay.Color,
	title:        clay.Color,
	accent:       clay.Color,
	button:       clay.Color,
	button_hover: clay.Color,
	button_text:  clay.Color,
	current_line: clay.Color, // the instruction at the PC
	changed:      clay.Color, // the register the last step wrote
	stopped:      clay.Color, // status text once the program has stopped
	unreachable:  clay.Color, // a register that can't be reached right now (UART DLAB)
}

COLOR_NONE :: clay.Color{0, 0, 0, 0}

// Light: pale lilac panels with deeper violet borders and titles.
LIGHT_PALETTE :: Palette {
	background   = {238, 233, 247, 255},
	panel        = {250, 248, 254, 255},
	border       = {150, 122, 200, 255},
	text         = {38, 28, 58, 255},
	text_dim     = {118, 104, 145, 255},
	title        = {104, 66, 168, 255},
	accent       = {146, 88, 196, 255},
	button       = {238, 233, 247, 255},
	button_hover = {224, 215, 242, 255},
	button_text  = {104, 66, 168, 255},
	current_line = {221, 207, 246, 255},
	changed      = {196, 176, 240, 200},
	stopped      = {196, 46, 92, 255},
	unreachable  = {250, 222, 228, 255},
}

// Dark: cool greys with the same warm accents.
DARK_PALETTE :: Palette {
	background   = {24, 26, 31, 255},
	panel        = {33, 36, 43, 255},
	border       = {70, 77, 92, 255},
	text         = {220, 223, 228, 255},
	text_dim     = {130, 136, 148, 255},
	title        = {150, 190, 255, 255},
	accent       = {240, 170, 90, 255},
	button       = {44, 48, 58, 255},
	button_hover = {64, 70, 84, 255},
	button_text  = {220, 223, 228, 255},
	current_line = {56, 76, 120, 255},
	changed      = {110, 85, 30, 220},
	stopped      = {255, 140, 90, 255},
	unreachable  = {78, 40, 48, 255},
}

palette :: proc() -> Palette {
	switch settings.theme {
	case .Light:
		return LIGHT_PALETTE
	case .Dark:
		return DARK_PALETTE
	}
	return LIGHT_PALETTE
}

// ------------------------------------------------------------------ fonts

// What a piece of text is for; `text_config` turns it into a font + size.
Font_Style :: enum u16 {
	Title,      // panel titles
	Text,       // buttons, labels, explanation text
	Code,       // disassembly
	Code_Small, // registers
}

// Everything is JetBrains Mono Medium (monospace, so columns line up).
font_sizes := [Font_Style]u16 {
	.Title      = 22,
	.Text       = 18,
	.Code       = 18,
	.Code_Small = 16,
}

text_config :: proc(style: Font_Style, color: clay.Color) -> clay.TextElementConfig {
	return clay.TextElementConfig {
		fontId    = u16(style),
		fontSize  = font_sizes[style],
		textColor = color,
	}
}

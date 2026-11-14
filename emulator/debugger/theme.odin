package rvdbg

import clay "../vendor/clay-odin"

// Look of the debugger: palettes, text styles and spacing. The current
// palette depends on `settings` (settings.odin). Layout code asks
// `palette()` for colours and `text_config` for text, so it never needs
// to know which theme or font is active.

// Fits comfortably on a 1920x1080 screen; the window is resizable.
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
	stripe:       [5]clay.Color, // bands under the toolbar
	// Encoding strip: one colour per kind of field.
	fields:       [Field_Kind]clay.Color,
}

COLOR_NONE :: clay.Color{0, 0, 0, 0}

// Light: the Clay website's palette.
LIGHT_PALETTE :: Palette {
	background   = {244, 235, 230, 255},
	panel        = {250, 246, 243, 255},
	border       = {168, 66, 28, 255},
	text         = {61, 26, 5, 255},
	text_dim     = {140, 105, 85, 255},
	title        = {168, 66, 28, 255},
	accent       = {225, 138, 50, 255},
	button       = {244, 235, 230, 255},
	button_hover = {224, 215, 210, 255},
	button_text  = {168, 66, 28, 255},
	current_line = {240, 213, 137, 255},
	changed      = {236, 189, 80, 160},
	stopped      = {200, 60, 20, 255},
	stripe       = {{240, 213, 137, 255}, {236, 189, 80, 255}, {225, 138, 50, 255}, {223, 110, 44, 255}, {168, 66, 28, 255}},
	fields       = {
		.Opcode    = {40, 130, 60, 255}, // green
		.Rd        = {30, 90, 190, 255}, // blue
		.Rs1       = {130, 60, 170, 255}, // purple
		.Rs2       = {170, 50, 120, 255}, // magenta
		.Funct     = {200, 100, 20, 255}, // orange
		.Immediate = {150, 110, 0, 255}, // gold
		.Csr       = {0, 128, 128, 255}, // teal
		.Unknown   = {140, 105, 85, 255},
	},
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
	stripe       = {{30, 40, 60, 255}, {40, 60, 95, 255}, {56, 76, 120, 255}, {80, 110, 170, 255}, {150, 190, 255, 255}},
	fields       = {
		.Opcode    = {120, 210, 130, 255},
		.Rd        = {120, 170, 255, 255},
		.Rs1       = {200, 150, 255, 255},
		.Rs2       = {255, 140, 200, 255},
		.Funct     = {255, 170, 90, 255},
		.Immediate = {240, 210, 100, 255},
		.Csr       = {100, 220, 210, 255},
		.Unknown   = {130, 136, 148, 255},
	},
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

package view

import clay "../../vendor/clay-odin"
import ui "../ui"

// One colour per kind of encoding field (Field_Kind, encoding.odin), for
// the Encoding strip and the register tags, in each theme. These belong to
// the debugger rather than the generic theme (ui/theme.odin), which knows
// nothing about RISC-V.

@(private)
LIGHT_FIELD_COLORS := [Field_Kind]clay.Color {
	.Opcode    = {40, 130, 60, 255}, // green
	.Rd        = {30, 90, 190, 255}, // blue
	.Rs1       = {150, 50, 160, 255}, // purple
	.Rs2       = {190, 50, 110, 255}, // magenta
	.Funct     = {200, 100, 20, 255}, // orange
	.Immediate = {150, 110, 0, 255}, // gold
	.Csr       = {0, 128, 128, 255}, // teal
	.Unknown   = {118, 104, 145, 255},
}

@(private)
DARK_FIELD_COLORS := [Field_Kind]clay.Color {
	.Opcode    = {120, 210, 130, 255},
	.Rd        = {120, 170, 255, 255},
	.Rs1       = {200, 150, 255, 255},
	.Rs2       = {255, 140, 200, 255},
	.Funct     = {255, 170, 90, 255},
	.Immediate = {240, 210, 100, 255},
	.Csr       = {100, 220, 210, 255},
	.Unknown   = {130, 136, 148, 255},
}

field_color :: proc(kind: Field_Kind) -> clay.Color {
	switch ui.settings.theme {
	case .Dark:
		return DARK_FIELD_COLORS[kind]
	case .Light:
	}
	return LIGHT_FIELD_COLORS[kind]
}

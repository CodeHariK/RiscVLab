package ui

import rl "vendor:raylib"

// The debugger's font: JetBrains Mono Medium, embedded in the binary at
// compile time (licence: fonts/README.md).
@(rodata)
embedded_font := #load("fonts/JetBrainsMono-Medium.ttf")

// Loads one copy of the font per text style (see `font_sizes` in
// theme.odin) into the `raylib_fonts` table the Clay renderer draws with.
// Same approach as the Clay example: rasterise at twice the drawn size
// and use trilinear filtering.
load_fonts :: proc() {
	for size, style in font_sizes {
		font := rl.LoadFontFromMemory(".ttf", raw_data(embedded_font), i32(len(embedded_font)), i32(size) * 2, nil, 0)
		rl.SetTextureFilter(font.texture, .TRILINEAR)
		assign_at(&raylib_fonts, int(style), Raylib_Font{fontId = u16(style), font = font})
	}
}

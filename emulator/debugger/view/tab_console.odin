package view

import "core:fmt"
import "core:strings"
import rv "../../core"
import ui "../ui"
import state "../state"

// The Console tab: what the program has printed, i.e. every byte it
// stored to the UART's THR register (devices/uart.odin), as text. The
// newest lines are at the bottom and always in view; Prev takes printed
// bytes back off, since undo puts the UART back as it was.

tab_console :: proc(session: ^state.Session) {
	colors := ui.palette()
	uart := session.uart
	if uart == nil || len(uart.output) == 0 {
		wrapped_text(
			fmt.tprintf(
				"Nothing printed yet. A program prints by storing bytes to the UART at 0x%x (lesson 19).",
				rv.UART_BASE,
			),
			ui.text_config(.Code_Small, colors.text_dim),
		)
		return
	}
	wrapped_text(
		fmt.tprintf("%d %s sent to the UART at 0x%x:", len(uart.output), "byte" if len(uart.output) == 1 else "bytes", rv.UART_BASE),
		ui.text_config(.Code_Small, colors.text_dim),
	)
	for line in last_lines(uart.output[:], visible_lines(SOURCE_LINE_HEIGHT) - 1) {
		// An empty line still takes its row.
		wrapped_text(line if line != "" else " ", ui.text_config(.Code, colors.text))
	}
}

// The last `count` lines of `output`, printable: the font only has ASCII,
// so other bytes show as '?', tabs as a space, and carriage returns are
// left out. A final newline doesn't start an empty line.
@(private)
last_lines :: proc(output: []u8, count: int) -> []string {
	end := len(output)
	if end > 0 && output[end - 1] == '\n' {
		end -= 1
	}
	// Walk back over `count` newlines: only the tail is ever drawn, however
	// much has been printed.
	start := end
	found := 0
	for start > 0 && found < max(count, 1) {
		start -= 1
		if output[start] == '\n' {
			found += 1
			if found == max(count, 1) {
				start += 1
				break
			}
		}
	}
	lines := make([dynamic]string, context.temp_allocator)
	builder := strings.builder_make(context.temp_allocator)
	for character in output[start:end] {
		switch character {
		case '\n':
			append(&lines, strings.clone(strings.to_string(builder), context.temp_allocator))
			strings.builder_reset(&builder)
		case '\r':
		case '\t':
			strings.write_byte(&builder, ' ')
		case ' ' ..= '~':
			strings.write_byte(&builder, character)
		case:
			strings.write_byte(&builder, '?')
		}
	}
	append(&lines, strings.to_string(builder))
	return lines[:]
}

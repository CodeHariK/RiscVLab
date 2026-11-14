package rvdbg

import "core:os"
import "core:strconv"
import "core:strings"

// The program's source, for the Source view: the text of the .s file and
// which line each instruction came from.
//
// The build writes a `.lines` file next to each program (see
// tests/programs/Makefile):
//
//   source /path/to/program.s
//   80000000 16          <- instruction address (hex), source line
//   80000004 17
//
// A line that produces several instructions (e.g. `li` with a big value)
// is listed once, at its first instruction; later instructions belong to
// the closest entry before them.
//
// Programs without one (raw binaries, files built elsewhere) simply have
// no Source view.

Line_Entry :: struct {
	address: u64,
	line:    int,
}

Source_Map :: struct {
	path:    string,
	lines:   []string, // the source text, one entry per line (line 1 = lines[0])
	entries: [dynamic]Line_Entry, // sorted by address, as in the file
	// Backing storage the strings above point into.
	text:    []u8,
	map_text: []u8,
}

// Loads the source map for the program at `program_path`. ok = false if
// there is no `.lines` file or its source can't be read.
source_load :: proc(program_path: string) -> (source: Source_Map, ok: bool) {
	map_text, map_error := os.read_entire_file(lines_file_path(program_path), context.allocator)
	if map_error != nil {
		return {}, false
	}
	source.map_text = map_text

	for line in strings.split_lines(string(map_text), context.temp_allocator) {
		if strings.has_prefix(line, "source ") {
			source.path = strings.trim_prefix(line, "source ")
			continue
		}
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) != 2 {
			continue
		}
		address, address_ok := strconv.parse_u64_of_base(fields[0], 16)
		line_number, line_ok := strconv.parse_int(fields[1])
		if address_ok && line_ok {
			append(&source.entries, Line_Entry{address, line_number})
		}
	}

	text, text_error := os.read_entire_file(source.path, context.allocator)
	if text_error != nil {
		source_destroy(&source)
		return {}, false
	}
	make_printable(text)
	source.text = text
	source.lines = strings.split_lines(string(text))
	return source, true
}

source_destroy :: proc(source: ^Source_Map) {
	delete(source.lines)
	delete(source.entries)
	delete(source.text)
	delete(source.map_text)
	source^ = {}
}

// The source line of the instruction at `address`: the entry with the
// highest address not above it (binary search). ok = false before the
// first entry.
source_line_at :: proc(source: ^Source_Map, address: u64) -> (line: int, ok: bool) {
	low, high := 0, len(source.entries)
	for low < high {
		middle := (low + high) / 2
		if source.entries[middle].address <= address {
			low = middle + 1
		} else {
			high = middle
		}
	}
	if low == 0 {
		return 0, false
	}
	return source.entries[low - 1].line, true
}

// The font only has printable ASCII glyphs, so tabs and carriage returns
// become spaces and any other non-printable byte becomes '?'.
@(private = "file")
make_printable :: proc(text: []u8) {
	for &character in text {
		switch character {
		case '\n', ' ' ..= '~':
		case '\t', '\r':
			character = ' '
		case:
			character = '?'
		}
	}
}

// program.elf -> program.lines; a file without .elf gets .lines appended.
@(private = "file")
lines_file_path :: proc(program_path: string) -> string {
	stem := strings.trim_suffix(program_path, ".elf")
	return strings.concatenate({stem, ".lines"}, context.temp_allocator)
}

package state

import "core:os"
import "core:slice"
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
// The assembler only lists instructions: a data directive in the code
// (`.word 0xffffffff`, an instruction that doesn't exist, in lesson 14)
// gets no entry, so its address would show as part of the line before.
// source_load adds those entries itself (add_data_entries).
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
	entries: [dynamic]Line_Entry, // sorted by address (source_line_at searches them)
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

	// The build writes them in address order, but a program with several
	// code sections might not: the lookup needs them sorted. (A stable
	// sort keeps the first line listed for an address first.)
	slice.stable_sort_by(source.entries[:], proc(a, b: Line_Entry) -> bool {
		return a.address < b.address
	})

	text, text_error := os.read_entire_file(source.path, context.allocator)
	if text_error != nil {
		source_destroy(&source)
		return {}, false
	}
	make_printable(text)
	source.text = text
	source.lines = strings.split_lines(string(text))
	add_data_entries(&source)
	return source, true
}

// Adds entries for the data directives between two listed lines. Their
// bytes sit at the end of the gap between the two entries' addresses,
// just before the next entry: the line before may have used the start of
// it for more instructions (a pseudo-instruction).
//
//   80000010 20   li   s1, 0             4 bytes: 0x10
//   (none)   21   .word 0xffffffff       4 bytes: 0x14 = 0x18 - 4
//   80000018 22   li   t1, 0x1000
@(private = "file")
add_data_entries :: proc(source: ^Source_Map) {
	listed := len(source.entries)
	for index in 0 ..< listed - 1 {
		this, next := source.entries[index], source.entries[index + 1]
		if next.line <= this.line + 1 {
			continue // nothing between them (or out of order)
		}
		total: u64
		for line in this.line + 1 ..< next.line {
			total += data_directive_size(source_line_text(source, line))
		}
		if total == 0 || total >= next.address - this.address {
			continue // no data, or it doesn't fit after the line before
		}
		address := next.address - total
		for line in this.line + 1 ..< next.line {
			size := data_directive_size(source_line_text(source, line))
			if size > 0 {
				append(&source.entries, Line_Entry{address, line})
				address += size
			}
		}
	}
	if len(source.entries) > listed {
		slice.stable_sort_by(source.entries[:], proc(a, b: Line_Entry) -> bool {
			return a.address < b.address
		})
	}
}

// The text of source line `line` (counted from 1), or "".
@(private = "file")
source_line_text :: proc(source: ^Source_Map, line: int) -> string {
	if line < 1 || line > len(source.lines) {
		return ""
	}
	return source.lines[line - 1]
}

// How many bytes a data directive line puts in memory: the size of one
// value times how many values it lists (`.word 1, 2` is 8). 0 for any
// other line: an instruction, a label alone, a comment, other directives.
@(private = "file")
data_directive_size :: proc(text: string) -> u64 {
	line := text
	if comment := strings.index_byte(line, '#'); comment >= 0 {
		line = line[:comment]
	}
	line = strings.trim_space(line)
	if colon := strings.index_byte(line, ':'); colon >= 0 {
		line = strings.trim_space(line[colon + 1:]) // after a label: "bad: .word 0"
	}
	directive, _, values := strings.partition(line, " ")
	size: u64
	switch directive {
	case ".byte":
		size = 1
	case ".half", ".2byte", ".short":
		size = 2
	case ".word", ".4byte", ".long":
		size = 4
	case ".dword", ".8byte", ".quad":
		size = 8
	case:
		return 0
	}
	if strings.trim_space(values) == "" {
		return 0
	}
	return size * u64(strings.count(values, ",") + 1)
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

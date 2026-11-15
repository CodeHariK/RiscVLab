package rv

// Minimal ELF64 loader for bare-metal RISC-V executables (what riscv-tests,
// our test programs and later xv6's kernel are).
//
// Only what's needed to run a program: check the header, copy each
// PT_LOAD segment to its physical address (zero-filling the rest of the
// segment, e.g. .bss), report the entry point, and look up a few symbols
// in the symbol table (riscv-tests report results through `tohost`).
//
// Layout references: the System V ABI "ELF-64 Object File Format".
// All multi-byte fields are little-endian (checked in the header).

Elf_Error :: enum {
	None,
	Too_Small,
	Not_Elf,
	Not_64_Bit,
	Not_Little_Endian,
	Not_Executable,
	Not_Risc_V,
	Truncated,            // a header or segment points past the end of the file
	Segment_Outside_Ram,  // a segment's address range isn't inside RAM
}

Elf_Program :: struct {
	entry:      u64,
	// The executable segment's address range (for disassembly views).
	code_start: u64,
	code_end:   u64,
	// The first loadable segment that isn't executable: the program's data
	// (.data / .bss). Zero size if there is none.
	data_start: u64,
	data_end:   u64,
	// Address of the `tohost` symbol, if the program has one.
	tohost:     Maybe(u64),
}

// ELF constants used below.
@(private = "file")
ELF_CLASS_64 :: 2
@(private = "file")
ELF_DATA_LITTLE_ENDIAN :: 1
@(private = "file")
ELF_TYPE_EXECUTABLE :: 2
@(private = "file")
ELF_MACHINE_RISC_V :: 243
@(private = "file")
SEGMENT_TYPE_LOAD :: 1
@(private = "file")
SEGMENT_FLAG_EXECUTE :: 1
@(private = "file")
SECTION_TYPE_SYMBOL_TABLE :: 2

// Sizes of the fixed-layout records.
@(private = "file")
ELF_HEADER_SIZE :: 64
@(private = "file")
SYMBOL_SIZE :: 24

// True if the image starts with the ELF magic number (0x7F 'E' 'L' 'F').
is_elf :: proc(image: []u8) -> bool {
	return len(image) >= 4 && image[0] == 0x7F && image[1] == 'E' && image[2] == 'L' && image[3] == 'F'
}

// Copies the program's loadable segments into RAM and describes it.
load_elf :: proc(bus: ^Bus, image: []u8) -> (program: Elf_Program, error: Elf_Error) {
	header := parse_header(image) or_return

	for index in 0 ..< u64(header.segment_count) {
		segment := read_segment(image, header, index) or_return
		if segment.kind != SEGMENT_TYPE_LOAD || segment.memory_size == 0 {
			continue
		}
		load_segment(bus, image, segment) or_return
		if segment.flags & SEGMENT_FLAG_EXECUTE != 0 {
			if program.code_end == 0 {
				program.code_start = segment.address
				program.code_end = segment.address + segment.file_size
			}
		} else if program.data_end == 0 {
			program.data_start = segment.address
			program.data_end = segment.address + segment.memory_size
		}
	}

	program.entry = header.entry
	program.tohost = find_symbol(image, header, "tohost")
	return program, .None
}

// ------------------------------------------------------------- header

@(private = "file")
Elf_Header :: struct {
	entry:          u64,
	segment_offset: u64, // e_phoff
	segment_size:   u16, // e_phentsize
	segment_count:  u16, // e_phnum
	section_offset: u64, // e_shoff
	section_size:   u16, // e_shentsize
	section_count:  u16, // e_shnum
}

@(private = "file")
parse_header :: proc(image: []u8) -> (header: Elf_Header, error: Elf_Error) {
	if len(image) < ELF_HEADER_SIZE {
		return {}, .Too_Small
	}
	if !is_elf(image) {
		return {}, .Not_Elf
	}
	if image[4] != ELF_CLASS_64 {
		return {}, .Not_64_Bit
	}
	if image[5] != ELF_DATA_LITTLE_ENDIAN {
		return {}, .Not_Little_Endian
	}
	if read_u16(image, 16) != ELF_TYPE_EXECUTABLE {
		return {}, .Not_Executable
	}
	if read_u16(image, 18) != ELF_MACHINE_RISC_V {
		return {}, .Not_Risc_V
	}

	header = Elf_Header {
		entry          = read_u64(image, 24),
		segment_offset = read_u64(image, 32),
		section_offset = read_u64(image, 40),
		segment_size   = read_u16(image, 54),
		segment_count  = read_u16(image, 56),
		section_size   = read_u16(image, 58),
		section_count  = read_u16(image, 60),
	}
	return header, .None
}

// ------------------------------------------------------------- segments

@(private = "file")
Elf_Segment :: struct {
	kind:        u32, // p_type
	flags:       u32, // p_flags
	file_offset: u64, // p_offset
	address:     u64, // p_paddr: where it goes in physical memory
	file_size:   u64, // p_filesz: bytes present in the file
	memory_size: u64, // p_memsz: bytes in memory (the rest is zero)
}

@(private = "file")
read_segment :: proc(image: []u8, header: Elf_Header, index: u64) -> (segment: Elf_Segment, error: Elf_Error) {
	base := header.segment_offset + index * u64(header.segment_size)
	if !in_bounds(image, base, 56) {
		return {}, .Truncated
	}
	segment = Elf_Segment {
		kind        = read_u32(image, base + 0),
		flags       = read_u32(image, base + 4),
		file_offset = read_u64(image, base + 8),
		address     = read_u64(image, base + 24),
		file_size   = read_u64(image, base + 32),
		memory_size = read_u64(image, base + 40),
	}
	return segment, .None
}

@(private = "file")
load_segment :: proc(bus: ^Bus, image: []u8, segment: Elf_Segment) -> Elf_Error {
	if segment.file_size > segment.memory_size || !in_bounds(image, segment.file_offset, segment.file_size) {
		return .Truncated
	}
	destination, inside_ram := bus_ram_slice(bus, segment.address, segment.memory_size)
	if !inside_ram {
		return .Segment_Outside_Ram
	}
	file_end := segment.file_offset + segment.file_size
	copy(destination, image[segment.file_offset:file_end])
	for i in segment.file_size ..< segment.memory_size {
		destination[i] = 0
	}
	return .None
}

// ------------------------------------------------------------- symbols

// Address of the symbol called `name`, searching every symbol table.
@(private = "file")
find_symbol :: proc(image: []u8, header: Elf_Header, name: string) -> Maybe(u64) {
	for index in 0 ..< u64(header.section_count) {
		section := header.section_offset + index * u64(header.section_size)
		if !in_bounds(image, section, 64) || read_u32(image, section + 4) != SECTION_TYPE_SYMBOL_TABLE {
			continue
		}
		symbols_offset := read_u64(image, section + 24)
		symbols_size := read_u64(image, section + 32)
		// sh_link of a symbol table is the index of its string table.
		strings_section := header.section_offset + u64(read_u32(image, section + 40)) * u64(header.section_size)
		if !in_bounds(image, strings_section, 64) || !in_bounds(image, symbols_offset, symbols_size) {
			continue
		}
		strings_offset := read_u64(image, strings_section + 24)

		for symbol := symbols_offset; symbol + SYMBOL_SIZE <= symbols_offset + symbols_size; symbol += SYMBOL_SIZE {
			name_offset := strings_offset + u64(read_u32(image, symbol))
			if symbol_name_is(image, name_offset, name) {
				return read_u64(image, symbol + 8)
			}
		}
	}
	return nil
}

// Compares the zero-terminated string at `offset` with `name`.
@(private = "file")
symbol_name_is :: proc(image: []u8, offset: u64, name: string) -> bool {
	length := u64(len(name))
	if !in_bounds(image, offset, length + 1) {
		return false
	}
	return string(image[offset:offset + length]) == name && image[offset + length] == 0
}

// ------------------------------------------------------------- symbol list

// A named address from the symbol table: a label in the code or a
// variable in the data.
Symbol :: struct {
	name:    string, // points into the image bytes
	address: u64,
}

// Every label and variable in the program, sorted by address, for showing
// names in the debugger. Leaves out what isn't a real program location:
// section and file entries, undefined symbols, the assembler's local
// ".L..." labels and RISC-V "$x" / "$d" mapping symbols. The names point
// into `image`, so it must outlive the result. Empty if `image` isn't an
// ELF.
elf_symbols :: proc(image: []u8, allocator := context.allocator) -> []Symbol {
	header, error := parse_header(image)
	if error != .None {
		return nil
	}
	symbols := make([dynamic]Symbol, allocator)
	for index in 0 ..< u64(header.section_count) {
		section := header.section_offset + index * u64(header.section_size)
		if !in_bounds(image, section, 64) || read_u32(image, section + 4) != SECTION_TYPE_SYMBOL_TABLE {
			continue
		}
		symbols_offset := read_u64(image, section + 24)
		symbols_size := read_u64(image, section + 32)
		strings_section := header.section_offset + u64(read_u32(image, section + 40)) * u64(header.section_size)
		if !in_bounds(image, strings_section, 64) || !in_bounds(image, symbols_offset, symbols_size) {
			continue
		}
		strings_offset := read_u64(image, strings_section + 24)

		for symbol := symbols_offset; symbol + SYMBOL_SIZE <= symbols_offset + symbols_size; symbol += SYMBOL_SIZE {
			kind := image[symbol + 4] & 0xF // st_info: 0 none, 1 object, 2 function, 3 section, 4 file
			section_index := read_u16(image, symbol + 6) // 0 = undefined
			if kind > 2 || section_index == 0 {
				continue
			}
			name := symbol_name(image, strings_offset + u64(read_u32(image, symbol)))
			if name == "" || name[0] == '$' || (len(name) > 1 && name[0] == '.' && name[1] == 'L') {
				continue
			}
			append(&symbols, Symbol{name, read_u64(image, symbol + 8)})
		}
	}
	sort_symbols(symbols[:])
	return symbols[:]
}

// The zero-terminated string at `offset`, or "" if it runs off the end.
@(private = "file")
symbol_name :: proc(image: []u8, offset: u64) -> string {
	for end := offset; end < u64(len(image)); end += 1 {
		if image[end] == 0 {
			return string(image[offset:end])
		}
	}
	return ""
}

// Insertion sort by address: symbol tables are small and mostly sorted.
@(private = "file")
sort_symbols :: proc(symbols: []Symbol) {
	for i in 1 ..< len(symbols) {
		for j := i; j > 0 && symbols[j - 1].address > symbols[j].address; j -= 1 {
			symbols[j - 1], symbols[j] = symbols[j], symbols[j - 1]
		}
	}
}

// ------------------------------------------------------------- reading

@(private = "file")
in_bounds :: proc(image: []u8, offset: u64, size: u64) -> bool {
	file_size := u64(len(image))
	return size <= file_size && offset <= file_size - size
}

@(private = "file")
read_u16 :: proc(image: []u8, offset: u64) -> u16 {
	return u16(image[offset]) | u16(image[offset + 1]) << 8
}

@(private = "file")
read_u32 :: proc(image: []u8, offset: u64) -> u32 {
	return u32(read_u16(image, offset)) | u32(read_u16(image, offset + 2)) << 16
}

@(private = "file")
read_u64 :: proc(image: []u8, offset: u64) -> u64 {
	return u64(read_u32(image, offset)) | u64(read_u32(image, offset + 4)) << 32
}

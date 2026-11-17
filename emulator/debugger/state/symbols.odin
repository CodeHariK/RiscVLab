package state

import "core:fmt"
import "core:strings"

// Looking up the program's symbol names (session.symbols, sorted by
// address) for the code and memory views.

// Names of every symbol at exactly `address`, e.g. "tdat, tdat1"; "" if none.
symbol_names_at :: proc(session: ^Session, address: u64) -> string {
	return symbol_names_in(session, address, address + 1, false)
}

// Names of the symbols in [start, end). With `show_address`, each name is
// followed by its address: "tdat1 @80002000".
symbol_names_in :: proc(session: ^Session, start: u64, end: u64, show_address: bool) -> string {
	builder := strings.builder_make(context.temp_allocator)
	for symbol in session.symbols {
		if symbol.address < start {
			continue
		}
		if symbol.address >= end {
			break
		}
		if strings.builder_len(builder) > 0 {
			strings.write_string(&builder, ", ")
		}
		strings.write_string(&builder, symbol.name)
		if show_address {
			strings.write_string(&builder, " @")
			strings.write_u64(&builder, symbol.address, 16)
		}
	}
	return strings.to_string(builder)
}



// The address of the symbol called `name`.
symbol_address :: proc(session: ^Session, name: string) -> (address: u64, ok: bool) {
	for symbol in session.symbols {
		if symbol.name == name {
			return symbol.address, true
		}
	}
	return 0, false
}

// " (numbers+0x4)": the variable or label an address falls in, in
// brackets, for the step details. "" if symbol_place finds nothing.
symbol_label :: proc(session: ^Session, address: u64) -> string {
	place := symbol_place(session, address)
	if place == "" {
		return ""
	}
	return fmt.tprintf(" (%s)", place)
}

// "numbers+0x4" (or just "numbers" at its start): the variable or label an
// address falls in. "" if the address is outside the program's code and
// data or before its first symbol.
symbol_place :: proc(session: ^Session, address: u64) -> string {
	program := session.program
	in_code := address >= program.code_start && address < program.code_end
	in_data := address >= program.data_start && address < program.data_end
	if !in_code && !in_data {
		return ""
	}
	found := -1
	for symbol, index in session.symbols {
		if symbol.address > address {
			break
		}
		found = index
	}
	if found < 0 {
		return ""
	}
	symbol := session.symbols[found]
	if symbol.address == address {
		return symbol.name
	}
	return fmt.tprintf("%s+0x%x", symbol.name, address - symbol.address)
}

package rvdbg

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



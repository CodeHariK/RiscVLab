package rvemu

import "core:fmt"
import "core:os"
import rv "../core"

// Reads a program file from disk. The core only takes bytes, so file
// access lives here in the front end.
read_program :: proc(path: string) -> (image: []u8, ok: bool) {
	data, error := os.read_entire_file(path, context.allocator)
	if error != nil {
		fmt.eprintfln("error: cannot read %s: %v", path, error)
		return nil, false
	}
	return data, true
}

print_load_error :: proc(path: string, error: rv.Load_Error) {
	fmt.eprintfln("error: cannot load %s: %v", path, error)
}

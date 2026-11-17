package state

import "core:fmt"
import "core:os"

// Reads the program to debug from disk. (The core only takes bytes.)
read_program :: proc(path: string) -> (image: []u8, ok: bool) {
	data, error := os.read_entire_file(path, context.allocator)
	if error != nil {
		fmt.eprintfln("error: cannot read %s: %v", path, error)
		return nil, false
	}
	return data, true
}

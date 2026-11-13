package rvemu

import "core:fmt"
import "core:os"

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

print_image_too_large :: proc(path: string, image_size: int, ram_size: int) {
	fmt.eprintfln("error: %s is %d bytes, larger than RAM (%d bytes)", path, image_size, ram_size)
}

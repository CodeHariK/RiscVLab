#+build !js
#+build !freestanding
package rv

import "core:mem/virtual"

// Big zero-filled buffers (the RAM, the undo history) straight from the OS.
//
// mmap gives pages that read as zero and only take physical memory once
// something is written to them, so a machine with 128 MiB of RAM costs
// only what the program touches. calloc does the same the first time, but
// when it hands back a block that was just freed (every Reset or program
// open in the debugger), it must write zeros over all of it, which makes
// every page physical: 128 MiB for a ten-instruction lesson.
//
// WebAssembly has no mmap: zeroed_pages_wasm.odin uses the normal
// allocator there instead.

zeroed_pages_alloc :: proc(size: int) -> []u8 {
	if size == 0 {
		return nil
	}
	data, error := virtual.reserve_and_commit(uint(size))
	if error != nil {
		panic("out of memory: cannot map the machine's memory")
	}
	return data
}

zeroed_pages_free :: proc(data: []u8) {
	if data != nil {
		virtual.release(raw_data(data), uint(len(data)))
	}
}

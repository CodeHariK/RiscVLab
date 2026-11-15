#+build js, freestanding
package rv

// WebAssembly version of zeroed_pages.odin: no mmap, so a normal zeroed
// allocation (a browser's fresh memory is zero anyway).

zeroed_pages_alloc :: proc(size: int) -> []u8 {
	return make([]u8, size)
}

zeroed_pages_free :: proc(data: []u8) {
	delete(data)
}

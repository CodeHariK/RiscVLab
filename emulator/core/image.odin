package rv

// Copies a raw program image (as made by `objcopy -O binary`) into RAM,
// starting at RAM_BASE. The core never touches files: front ends read the
// file (from disk, or from the browser later) and pass the bytes here.
// Returns false if the image is larger than RAM.
load_image :: proc(bus: ^Bus, image: []u8) -> bool {
	if len(image) > len(bus.ram) {
		return false
	}
	copy(bus.ram, image)
	return true
}

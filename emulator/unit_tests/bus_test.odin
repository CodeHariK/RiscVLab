package rv_unit_tests

import "core:testing"
import rv "../core"

// Unit tests for the bus (core/bus.odin): attaching devices.

// A device range that ends at the very top of the address space: the
// overlap check must not overflow (base + size wraps round to 0).
@(test)
devices_at_the_top_of_the_address_space :: proc(t: ^testing.T) {
	machine := rv.machine_create(4096, 0)
	defer rv.machine_destroy(&machine)
	// Only the address range matters to bus_attach, so the devices have
	// no procedures. `top` covers the last 0x100 bytes of the address
	// space: its end, base + size, would be 2^64, which wraps to 0.
	top := rv.Device {
		name = "top",
		base = max(u64) - 0xff,
		size = 0x100,
	}
	testing.expect(t, rv.bus_attach(&machine.bus, top))
	// One byte too long: its last byte is top's first byte, so refused.
	overlapping := rv.Device {
		name = "overlapping",
		base = max(u64) - 0x1ff,
		size = 0x101,
	}
	testing.expect(t, !rv.bus_attach(&machine.bus, overlapping))
	// Ends exactly where top starts: touching, not overlapping, so it fits.
	// (ranges_overlap measures from the lower start, so nothing wraps.)
	below := rv.Device {
		name = "below",
		base = max(u64) - 0x1ff,
		size = 0x100,
	}
	testing.expect(t, rv.bus_attach(&machine.bus, below))
}

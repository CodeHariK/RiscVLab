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
	top := rv.Device {
		name = "top",
		base = max(u64) - 0xff,
		size = 0x100,
	}
	testing.expect(t, rv.bus_attach(&machine.bus, top))
	overlapping := rv.Device {
		name = "overlapping",
		base = max(u64) - 0x1ff,
		size = 0x101,
	}
	testing.expect(t, !rv.bus_attach(&machine.bus, overlapping))
	below := rv.Device {
		name = "below",
		base = max(u64) - 0x1ff,
		size = 0x100,
	}
	testing.expect(t, rv.bus_attach(&machine.bus, below))
}

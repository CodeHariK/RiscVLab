package rv

// Physical memory map.
//
// It matches QEMU's `virt` machine, so the same binaries (and later xv6)
// run unchanged on both QEMU and this emulator. Device addresses are
// added here as each device is implemented (UART so far; CLINT, PLIC and
// virtio to come). Anything that isn't RAM or a device is empty: an
// access there faults.

// The CLINT (core-local interruptor: the timer, and software interrupts
// between harts). devices/clint.odin.
CLINT_BASE :: u64(0x0200_0000)
CLINT_SIZE :: u64(0x1_0000)

// The UART (serial port, an NS16550A as on QEMU): 8 byte-wide registers
// at the start of a 256-byte range. devices/uart.odin.
UART_BASE :: u64(0x1000_0000)
UART_SIZE :: u64(0x100)

// Start of main RAM. QEMU `virt` places the kernel here and jumps to it.
RAM_BASE :: u64(0x8000_0000)

// Default RAM size: 128 MiB, the same amount xv6's Makefile gives QEMU.
RAM_SIZE_DEFAULT :: u64(128 * 1024 * 1024)

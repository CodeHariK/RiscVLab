package emulator

// Physical memory map.
//
// It matches QEMU's `virt` machine, so the same binaries (and later xv6)
// run unchanged on both QEMU and this emulator. Device addresses (UART,
// CLINT, PLIC, virtio) will be added here as each device is implemented.

// Start of main RAM. QEMU `virt` places the kernel here and jumps to it.
RAM_BASE :: u64(0x8000_0000)

// Default RAM size: 128 MiB, the same amount xv6's Makefile gives QEMU.
RAM_SIZE_DEFAULT :: u64(128 * 1024 * 1024)

# emulator (RiscVOdin)

RISC-V (RV64IMA) emulator in Odin, modelled on QEMU's `virt` machine so it can boot xv6.

Planned layout: one file per extension or device (`rv64i`, `rv64m`, `rv64a`, `csr`, `mmu`, `uart`, `clint`, `plic`, `virtio_blk`), plus a step debugger and an instruction trace log.

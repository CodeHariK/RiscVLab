# RiscVLab

A learning project: a RISC-V emulator and an xv6 port, both written in [Odin](https://odin-lang.org).

| Folder | What it is | Runs on |
|---|---|---|
| `emulator/` | RISC-V emulator modelled on QEMU's `virt` board | macOS (host) |
| `Xv6Odin/` | Port of MIT's xv6-riscv kernel and user programs | riscv64, freestanding |
| `tests/` | ISA conformance (`riscv-tests`) runner and trace-diff scripts | host |
| `docs/` | Notes per milestone | — |

## Emulator target

- RV64IMA + Zicsr + Zifencei (C extension optional, later)
- M / S / U privilege modes, traps, interrupts, delegation
- Sv39 virtual memory
- Devices: CLINT (timer), PLIC, 16550 UART, virtio-mmio block disk

## Milestones

1. **Emulator core:** a simple step-by-step interpreter, RV64I first.
2. **Conformance:** pass `riscv-tests` (unprivileged + privileged).
3. **Boot stock xv6-riscv (C)** on RiscVOdin, reaching a shell prompt.
4. **Odin freestanding test:** "hello" over the UART on QEMU `virt`.
5. **Port xv6 to Odin, one subsystem at a time:** console/UART → traps → allocator → virtual memory → processes/scheduler → syscalls → file system → virtio disk.
   Each step runs on both QEMU and RiscVOdin. Works on QEMU but not RiscVOdin = emulator bug; fails on both = kernel bug.

## References

- [RISC-V Unprivileged ISA](https://docs.riscv.org/reference/isa/unpriv/intro.html)
- [RISC-V Privileged ISA](https://docs.riscv.org/reference/isa/priv/priv-intro.html)
- [xv6-riscv](https://github.com/mit-pdos/xv6-riscv) and the [xv6 book](https://pdos.csail.mit.edu/6.1810/2024/xv6/book-riscv-rev4.pdf)
- [riscv-tests](https://github.com/riscv-software-src/riscv-tests)
- [Spike](https://github.com/riscv-software-src/riscv-isa-sim) (reference simulator for trace diffing)

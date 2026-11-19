# RiscVLab

A learning project: a RISC-V emulator and an xv6 port, both written in [Odin](https://odin-lang.org).

| Folder | What it is | Runs on |
|---|---|---|
| `emulator/` | RISC-V emulator modelled on QEMU's `virt` board | macOS (host) |
| `Xv6Odin/` | Port of MIT's xv6-riscv kernel and user programs | riscv64, freestanding |
| `tests/` | Lessons, our own test programs, the official `riscv-tests` runner | host |
| `docs/` | How the emulator is built, and reference pages (also in the debugger's Docs window) | - |

## Emulator target

- RV64IMA + Zicsr + Zifencei (C extension optional, later)
- M / S / U privilege modes, traps, interrupts, delegation
- Sv39 virtual memory
- Devices: CLINT (timer), PLIC, 16550 UART, virtio-mmio block disk

## Milestones

1. **Emulator core:** a simple step-by-step interpreter. *Done: RV64IMA, Zicsr, Zifencei, machine-mode traps and interrupts, ELF loading, undo (step back), the UART and the CLINT timer, a step debugger with 21 lessons and reference docs.*
2. **Conformance:** pass `riscv-tests` (unprivileged + privileged). *rv64ui-p, rv64um-p, rv64ua-p: all 86 pass. Privileged suites come with supervisor mode.*
3. **Boot stock xv6-riscv (C)** on RiscVOdin, reaching a shell prompt. Still needed: supervisor and user modes, Sv39 paging, the PLIC, the virtio disk (see [TODO.md](TODO.md)).
4. **Odin freestanding test:** "hello" over the UART on QEMU `virt`.
5. **Port xv6 to Odin, one subsystem at a time:** console/UART -> traps -> allocator -> virtual memory -> processes/scheduler -> syscalls -> file system -> virtio disk.
   Each step runs on both QEMU and RiscVOdin. Works on QEMU but not RiscVOdin = emulator bug; fails on both = kernel bug.

## References

- [RISC-V Unprivileged ISA (PDF)](https://docs.riscv.org/reference/isa/_attachments/riscv-unprivileged.pdf): RV64I, M, A, Zicsr
- [RISC-V Privileged ISA (PDF)](https://docs.riscv.org/reference/isa/_attachments/riscv-privileged.pdf): machine/supervisor mode, CSRs, traps, Sv39
- [xv6 RISC-V book (online)](https://mit-pdos.github.io/xv6-riscv-book/): traps, page tables, processes, as xv6 uses them
- [xv6-riscv source](https://github.com/mit-pdos/xv6-riscv)
- [riscv-tests](https://github.com/riscv-software-src/riscv-tests)
- [Spike](https://github.com/riscv-software-src/riscv-isa-sim): reference simulator for trace diffing

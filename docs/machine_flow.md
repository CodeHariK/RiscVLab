# How the machine works

Flowcharts of the emulator, grouped by file and function. Each box
named `file : function` is a subgraph; a diamond is a condition; an
edge label says which way the condition went. Red boxes are traps.

1. Start-up (cli)
2. The run loop (machine_run)
3. One step (machine_step)
4. One instruction (cpu_step, execute and the handlers)
5. The bus (load, store, fetch, peek)
6. Interrupts (CLINT -> mip -> interrupt_to_take)
7. Trap entry and mret
8. Step back (undo)

---

## 1. Start-up

```mermaid
flowchart TD
  subgraph CLI["cli/main.odin : run"]
    direction TB
    A["parse_options"] --> A1{"options ok and fit this build?<br/>options_fit_build: no --trace or --check-undo<br/>when DEBUG_RECORD_STEPS is off"}
    A1 -- no --> AX["exit 2"]
    A1 -- yes --> B["read_program (program_file.odin)"]
    B --> C["rv.machine_create"]
    C --> D["devices.clint_attach<br/>devices.uart_attach"]
    D --> E["loader.load_program"]
    E --> F{"options.mode"}
    F -- Run --> G["run_with_console (console.odin)"]
    F -- Check_Undo --> H["check_undo (undo_check.odin)"]
    F -- Disassemble --> I["print_disassembly"]
  end

  subgraph MC["core/machine.odin : machine_create"]

    direction TB
    C1["bus_create: RAM straight from the OS (zeroed_pages)<br/>history_create: ring buffer (0 = no undo)<br/>pc = RAM_BASE, privilege = Machine<br/>mstatus = MSTATUS_RESET (MPP = Machine)"]
  end
  C --> C1

  subgraph ATT["devices/*.odin : *_attach"]

    direction TB
    D1["fill a Device {base, size, load, peek, store,<br/>interrupts, save, restore, destroy}<br/>CLINT at 0x0200_0000, UART at 0x1000_0000"]
    D1 --> D2["core/bus.odin : bus_attach"]
    D2 --> D3{"room left, size > 0,<br/>no overlap with RAM or another device?"}
    D3 -- no --> D4["false: not attached"]
    D3 -- yes --> D5["added to bus.devices"]
  end
  D --> D1

  subgraph LD["loader/program.odin : load_program"]

    direction TB
    L1{"is_elf(image)?"}
    L1 -- yes --> L2["load_elf (elf.odin): copy the segments,<br/>find the tohost symbol"]
    L1 -- no --> L3["load_image (image.odin): copy the bytes to RAM_BASE"]
    L2 --> L4["cpu.pc = entry<br/>machine.tohost = tohost (ELF only)"]
    L3 --> L4
  end
  E --> L1

  subgraph CON["cli/console.odin : run_with_console"]

    direction TB
    G1["loop: rv.machine_run in chunks<br/>(100000 steps, or 1 with --trace)"]
    G1 --> G2["write_console: print new uart.output bytes"]
    G2 --> G3{"stopped for a reason other than<br/>Step_Limit, or max_steps reached?"}
    G3 -- no --> G1
    G3 -- yes --> G4["report_result (report.odin)"]
  end
  G --> G1
```

---

## 2. The run loop

The debugger doesn't use machine_run: its Next button calls
machine_step once, and Prev calls machine_step_back.

```mermaid
flowchart TD
  subgraph RUN["core/machine.odin : machine_run"]
    direction TB
    R0{"max_steps == 0 or steps < max_steps?"}
    R0 -- no --> RSL["return Step_Limit"]
    R0 -- yes --> R1["result = machine_step"]
    R1 --> R2["steps += 1<br/>observer(machine, pc, result)<br/>(--trace prints a line here)"]
    R2 --> R3{"result is a trap?<br/>(only when there was no handler)"}
    R3 -- "yes, cause = Breakpoint" --> RBP["return Breakpoint"]
    R3 -- "yes, any other cause" --> RTR["return Trap"]
    R3 -- no --> R4["machine_host_exit"]
    R4 --> R5{"tohost known and<br/>bit 0 of the value there = 1?"}
    R5 -- yes --> RHX["return Host_Exit<br/>exit_code = value >> 1"]
    R5 -- no --> R0
  end

  style RBP fill:#fdd
  style RTR fill:#fdd
```

---

## 3. One step

A step is either one instruction or one interrupt taken. A trap with
a handler is a normal step (the pc moves to mtvec); a trap with no
handler (mtvec = 0) stops the machine and changes nothing.

```mermaid
flowchart TD
  subgraph STEP["core/machine.odin : machine_step"]
    direction TB
    S0["when DEBUG_RECORD_STEPS:<br/>cpu.debug_undo = {pc, minstret, mcycle, privilege}"]
    S0 --> S1["debug_last_trap = nil<br/>bus.device_accessed = false"]
    S1 --> S2{"step_clock >= bus.interrupts_change_at?<br/>(the CLINT alarm time has come)"}
    S2 -- yes --> S3["machine_update_interrupts<br/>(section 6)"]
    S2 -- no --> S4
    S3 --> S4{"mip & mie != 0?"}
    S4 -- yes --> S5["interrupt_to_take (section 6)"]
    S4 -- no --> S7
    S5 --> S6{"take?"}
    S6 -- yes --> S6a["result = trap_make(cause, 0)<br/>the instruction at pc doesn't run"]
    S6 -- no --> S7["result = cpu_step (section 4)"]
    S6a --> S8
    S7 --> S8{"when DEBUG_RECORD_STEPS:<br/>bus.device_accessed?"}
    S8 -- yes --> S8a["undo.device_state = bus.debug_touched:<br/>the device's state from before (note_touch)"]
    S8 -- no --> S9
    S8a --> S9{"result is a trap?"}
    S9 -- no --> S12
    S9 -- yes --> S10{"trap_has_handler?<br/>mtvec base != 0"}
    S10 -- no --> SSTOP["return the trap: the machine stops<br/>nothing recorded, nothing changed"]
    S10 -- yes --> S11["undo: save mstatus, mepc, mcause, mtval<br/>trap_enter (section 7)<br/>debug_last_trap = trap<br/>mcycle += 1 (the trap's step)"]
    S11 --> S12["when DEBUG_RECORD_STEPS:<br/>history_push(cpu.debug_undo) if history enabled"]
    S12 --> S13{"bus.device_accessed, or<br/>step_clock >= interrupts_change_at?"}
    S13 -- yes --> S14["machine_update_interrupts"]
    S13 -- no --> SOK["return nil"]
    S14 --> SOK
  end

  style SSTOP fill:#fdd
```

---

## 4. One instruction

```mermaid
flowchart TD
  subgraph CPU["core/cpu.odin : cpu_step"]
    direction TB
    C0["minstret_written = mcycle_written = false"]
    C0 --> C1["bus_fetch_instruction(pc) (section 5)"]
    C1 --> C2{"fetched?<br/>(pc in RAM)"}
    C2 -- no --> CIAF["Instruction_Access_Fault, value = pc"]
    C2 -- yes --> C3["next_pc = pc + 4"]
    C3 --> C4["execute(instruction)"]
    C4 --> C5{"handler returned a trap?"}
    C5 -- yes --> C6["return the trap<br/>pc, registers, memory unchanged"]
    C5 -- no --> C7["pc = next_pc<br/>minstret += 1 unless a csrw wrote it<br/>mcycle += 1 unless a csrw wrote it"]
  end

  subgraph EX["core/execute.odin : execute (switch on opcode)"]

    direction TB
    E0{"opcode"}
  end
  C4 --> E0

  subgraph UP["rv64i_upper.odin"]

    direction TB
    U1["exec_lui, exec_auipc"]
  end
  subgraph CT["rv64i_control.odin"]
    direction TB
    J1["exec_jal, exec_jalr, exec_branch"]
    J1 --> J2{"jalr with funct3 != 0?"}
    J2 -- yes --> JILL["Illegal_Instruction"]
    J2 -- no --> J3{"jump or taken branch:<br/>target & 3 != 0?"}
    J3 -- yes --> JMIS["Instruction_Address_Misaligned,<br/>value = target"]
    J3 -- no --> J4["next_pc = target<br/>jal / jalr: rd = pc + 4"]
  end
  subgraph LS["rv64i_load_store.odin"]
    direction TB
    L1["exec_load: address = rs1 + imm"]
    L1 --> L2{"bus_load ok?"}
    L2 -- no --> LLAF["Load_Access_Fault, value = address"]
    L2 -- yes --> L3["sign-extend (lb, lh, lw)<br/>reg_write rd"]
    S1["exec_store: address = rs1 + imm<br/>undo: bus_peek the old bytes"]
    S1 --> S2{"bus_store ok?"}
    S2 -- no --> SSAF["Store_Access_Fault, value = address"]
    S2 -- yes --> S3["undo: memory address, size, old value"]
  end
  subgraph ALU["rv64i_alu.odin, rv64i_alu_word.odin"]
    direction TB
    A1["exec_op_imm, exec_op_imm_32"]
    A2["exec_op, exec_op_32"]
    A2 --> A3{"funct7 = 0000001?"}
    A3 -- yes --> M1["rv64m.odin: exec_muldiv, exec_muldiv_32<br/>(divide by 0 gives -1 / the dividend, no trap)"]
    A3 -- no --> A4["add, sub, shifts, compares, logic"]
  end
  subgraph AMO["rv64a.odin : exec_amo"]
    direction TB
    X1{"address % size != 0?"}
    X1 -- yes --> XMIS["lr: Load_Address_Misaligned<br/>sc, amo*: Store_Address_Misaligned"]
    X1 -- no --> X2{"bus_is_ram?"}
    X2 -- no --> XAF["lr: Load_Access_Fault<br/>sc, amo*: Store_Access_Fault"]
    X2 -- yes --> X3{"which"}
    X3 -- lr --> X4["load, reservation_set(address, size)"]
    X3 -- sc --> X5{"reservation holds<br/>this address and size?"}
    X5 -- yes --> X6["store, rd = 0"]
    X5 -- no --> X7["no store, rd = 1"]
    X6 --> X8["reservation cleared"]
    X7 --> X8
    X3 -- "amoswap, amoadd, ..." --> X9["load, combine, store, rd = old value"]
  end
  subgraph SYS["rv64i_system.odin : exec_system, exec_misc_mem"]
    direction TB
    Y0{"funct3 != 0?"}
    Y0 -- yes --> YZ["exec_zicsr"]
    Y0 -- no --> Y1{"which instruction"}
    Y1 -- ecall --> YEC["ecall_cause(privilege):<br/>Ecall_From_U_Mode or Ecall_From_M_Mode"]
    Y1 -- ebreak --> YBP["Breakpoint"]
    Y1 -- mret --> YMR["exec_mret (section 7)"]
    Y1 -- wfi --> YW["nothing (a nop)"]
    Y1 -- other --> YILL["Illegal_Instruction"]
    F1["fence, fence.i: nothing"]
  end
  subgraph ZI["zicsr.odin : exec_zicsr"]
    direction TB
    Z0{"csr_allowed?<br/>(privilege >= the CSR's level)"}
    Z0 -- no --> ZILL["Illegal_Instruction"]
    Z0 -- yes --> Z1{"csr_read ok?<br/>(csrrw with rd = x0 needn't read)"}
    Z1 -- no --> ZILL
    Z1 -- yes --> Z2{"writes?<br/>(csrrs / csrrc with rs1 = x0 don't)"}
    Z2 -- yes --> Z3{"csr_write ok? (csr.odin)<br/>not read-only, exists"}
    Z3 -- no --> ZILL
    Z3 -- yes --> Z4["rd = old value"]
    Z2 -- no --> Z4
  end

  E0 -- "LUI, AUIPC" --> U1
  E0 -- "JAL, JALR, BRANCH" --> J1
  E0 -- LOAD --> L1
  E0 -- STORE --> S1
  E0 -- "OP_IMM, OP_IMM_32" --> A1
  E0 -- "OP, OP_32" --> A2
  E0 -- AMO --> X1
  E0 -- SYSTEM --> Y0
  E0 -- MISC_MEM --> F1
  YZ --> Z0
  E0 -- "anything else" --> EILL["Illegal_Instruction"]

  style CIAF fill:#fdd
  style JILL fill:#fdd
  style JMIS fill:#fdd
  style LLAF fill:#fdd
  style SSAF fill:#fdd
  style XMIS fill:#fdd
  style XAF fill:#fdd
  style YEC fill:#fdd
  style YBP fill:#fdd
  style YILL fill:#fdd
  style ZILL fill:#fdd
  style EILL fill:#fdd
```

Every handler checks first and writes last, so a handler that returns
a trap has changed nothing. Registers change only through reg_write
(which drops writes to x0), memory only through the bus.

---

## 5. The bus

```mermaid
flowchart TD
  subgraph LOAD["core/bus.odin : bus_load(addr, size, now)"]
    direction TB
    B0["ram_load: ram_offset"] --> B1{"all of [addr, addr+size) in RAM?<br/>size is 1, 2, 4 or 8?"}
    B1 -- yes --> B2["value = little-endian bytes,<br/>zero-extended (misaligned is fine)"]
    B1 -- no --> B3["bus_device_at"]
    B3 --> B4{"one device's range holds<br/>all of [addr, addr+size)?"}
    B4 -- no --> B5["ok = false<br/>(caller raises an access fault)"]
    B4 -- yes --> B6["note_touch: first device access this step?<br/>device_accessed = true; when DEBUG_RECORD_STEPS,<br/>save its state in debug_touched"]
    B6 --> B7["device.load(offset = addr - base, size, now)<br/>ok = false if the device doesn't take that size"]
  end

  subgraph STORE["core/bus.odin : bus_store(addr, size, value, now)"]

    direction TB
    W0{"in RAM?"}
    W0 -- yes --> W1["write the low size bytes, little-endian"]
    W0 -- no --> W2{"bus_device_at found one?"}
    W2 -- no --> W3["false"]
    W2 -- yes --> W4["note_touch, then device.store"]
  end

  subgraph FETCH["core/bus.odin : bus_fetch_instruction(addr)"]

    direction TB
    F0{"4 bytes in RAM?"}
    F0 -- yes --> F1["instruction"]
    F0 -- no --> F2["false: devices are never executed"]
  end

  subgraph PEEK["core/bus.odin : bus_peek (debugger, undo, tohost)"]

    direction TB
    P0{"in RAM?"}
    P0 -- yes --> P1["value"]
    P0 -- no --> P2{"device found and has peek?"}
    P2 -- no --> P3["false"]
    P2 -- yes --> P4{"device.peek ok for this size?"}
    P4 -- yes --> P5["value (no side effects)"]
    P4 -- no --> P6["peek one byte at a time and join them"]
  end

  subgraph RAMQ["core/bus.odin : bus_is_ram"]

    direction TB
    Q0["used by atomics: true only if all in RAM"]
  end
```

---

## 6. Interrupts

mip is not stored by software: it is recomputed from the devices
(machine_update_interrupts), and only when something could have
changed it.

```mermaid
flowchart TD
  subgraph WHEN["when machine_update_interrupts runs (core/machine.odin)"]
    direction TB
    T1["start of machine_step:<br/>step_clock >= interrupts_change_at"]
    T2["end of machine_step:<br/>a device was accessed, or the alarm time came"]
    T3["machine_step_back: always"]
    T4["machine_load / machine_store from a front end<br/>that touched a device"]
  end

  subgraph MUI["core/machine.odin : machine_update_interrupts"]

    direction TB
    M0["mip, interrupts_change_at =<br/>bus_interrupt_lines(bus, step_clock)"]
  end
  T1 --> M0
  T2 --> M0
  T3 --> M0
  T4 --> M0

  subgraph BIL["core/interrupts.odin : bus_interrupt_lines"]

    direction TB
    I0["for each device with .interrupts:<br/>lines |= its lines<br/>changes_at = min(changes_at, its time)"]
    I0 --> I1["return lines & MACHINE_INTERRUPT_BITS"]
  end
  M0 --> I0

  subgraph CLI["devices/clint.odin : clint_interrupts"]

    direction TB
    K0{"msip bit 0 = 1?"}
    K0 -- yes --> K1["lines |= MIP_MSIP"]
    K0 -- no --> K2
    K1 --> K2{"mtime >= mtimecmp?<br/>mtime = step_clock * TICKS + mtime_offset"}
    K2 -- yes --> K3["lines |= MIP_MTIP<br/>changes_at = never (only a store changes it)"]
    K2 -- no --> K4["changes_at = now + steps until mtime reaches mtimecmp<br/>(clint_steps_to_alarm, saturating)"]
  end
  I0 --> K0

  subgraph ITT["core/interrupts.odin : interrupt_to_take (from machine_step)"]

    direction TB
    N0["ready = mip & mie"]
    N0 --> N1{"ready == 0?"}
    N1 -- yes --> NNO["take = false"]
    N1 -- no --> N2{"privilege = Machine and mstatus.MIE = 0?<br/>(in User mode, M interrupts are always on)"}
    N2 -- yes --> NNO
    N2 -- no --> N3{"priority"}
    N3 -- "MEIP set" --> NE["Machine_External_Interrupt"]
    N3 -- "else MSIP set" --> NS["Machine_Software_Interrupt"]
    N3 -- "else MTIP set" --> NT["Machine_Timer_Interrupt"]
  end

  style NE fill:#fdd
  style NS fill:#fdd
  style NT fill:#fdd
```

---

## 7. Trap entry and mret

```mermaid
flowchart TD
  subgraph TE["core/trap_entry.odin : trap_enter (from machine_step)"]
    direction TB
    E1["mepc = pc (the instruction that trapped,<br/>or the one an interrupt came before)<br/>mcause = cause, mtval = value"]
    E1 --> E2["mstatus.MPIE = mstatus.MIE<br/>mstatus.MIE = 0"]
    E2 --> E3["mstatus.MPP = privilege (User or Machine)<br/>privilege = Machine"]
    E3 --> E4["pc = mtvec base"]
    E4 --> E5{"mtvec mode = 1 (vectored)<br/>and the cause is an interrupt?"}
    E5 -- yes --> E6["pc += 4 * cause number"]
    E5 -- no --> E7
    E6 --> E7["reservation cleared (an sc after this fails)"]
  end

  subgraph MR["core/trap_return.odin : exec_mret (an instruction, via exec_system)"]

    direction TB
    R0{"privilege == Machine?"}
    R0 -- no --> RILL["Illegal_Instruction"]
    R0 -- yes --> R1["mstatus.MIE = mstatus.MPIE<br/>mstatus.MPIE = 1"]
    R1 --> R2["privilege = mstatus.MPP<br/>mstatus.MPP = User (the least privileged mode)"]
    R2 --> R3["next_pc = mepc<br/>(cpu_step then sets pc = next_pc)"]
  end

  subgraph CSRW["core/csr.odin : csr_write side rules"]

    direction TB
    W1["mstatus: only MIE, MPIE, MPP kept;<br/>MPP = 1 or 2 leaves MPP as it was (WARL)"]
    W2["mie: only MSIP, MTIP, MEIP bits"]
    W3["mip: writes ignored (wires from devices)"]
    W4["mtvec: bit 1 cleared; mepc: low 2 bits cleared"]
    W5["mcycle: step_clock_offset absorbs the jump,<br/>so the CLINT's time doesn't move"]
  end

  style RILL fill:#fdd
```

---

## 8. Step back (undo)

Only in builds with DEBUG_RECORD_STEPS (the debugger, rvemu-check).

```mermaid
flowchart TD
  subgraph SB["core/machine.odin : machine_step_back"]
    direction TB
    U0["history_pop (history.odin)"]
    U0 --> U1{"a record?"}
    U1 -- no --> UNO["return false<br/>(at the start, or the oldest was forgotten)"]
    U1 -- yes --> U2{"device_changed?"}
    U2 -- yes --> U3["device.restore(saved state)"]
    U2 -- no --> U4{"memory_changed?"}
    U4 -- yes --> U5["bus_store the old bytes"]
    U4 -- no --> U6
    U3 --> U6{"register_changed?"}
    U5 --> U6
    U6 -- yes --> U7["regs[index] = old"]
    U6 -- no --> U8
    U7 --> U8{"csr_changed?"}
    U8 -- yes --> U9["csr_restore (csr.odin):<br/>also puts step_clock_offset back for mcycle"]
    U8 -- no --> U10
    U9 --> U10{"reservation_changed?"}
    U10 -- yes --> U11["reservation = old"]
    U10 -- no --> U12
    U11 --> U12{"trap_taken?"}
    U12 -- yes --> U13["mstatus, mepc, mcause, mtval = saved"]
    U12 -- no --> U14
    U13 --> U14["pc, minstret, mcycle, privilege = saved<br/>debug_last_write = {}, debug_last_trap = nil"]
    U14 --> U15["machine_update_interrupts<br/>(mip isn't recorded: it is worked out again)"]
  end
```

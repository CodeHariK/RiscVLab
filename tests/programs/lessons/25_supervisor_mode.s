# Lesson 25: Supervisor mode
# Three levels, as xv6 uses them: firmware in machine mode, a kernel in supervisor mode, a program in user mode. The program's system calls go straight to the kernel (medeleg), which answers them and returns with sret.
# Expect: exit 4
# Docs: privilege, medeleg, stvec, sstatus, sret, system-call, Ecall_From_S_Mode
#
# Lesson 24 had two levels: every trap went up to machine mode. A real OS
# has three. Machine mode is the firmware, which starts the machine and
# then mostly sleeps; the kernel runs in supervisor mode; programs run in
# user mode. medeleg (machine exception delegation) lets machine mode
# hand chosen exceptions to the kernel, so they skip the firmware:
#
#   machine (firmware)      supervisor (kernel)       user (program)
#   ------------------      -------------------       --------------
#   mtvec, stvec, medeleg
#   MPP = S, mret  -------> kernel_main:
#                             SPP = U, sret  -------> user_main:
#                           kernel_trap:   <--------    ecall (8): add 10
#                             a0 += 10, sret ------->
#                           kernel_trap:   <--------    ecall (8): exit
#   machine_trap:  <-------   ecall (9)
#     check, ebreak
#
# Each level goes down with its own return: mret to the mode in
# mstatus.MPP (2 bits: 00 user, 01 supervisor, 11 machine), sret to the
# mode in sstatus.SPP (1 bit: 0 user, 1 supervisor; a supervisor trap
# never comes from machine mode). The kernel has its own copies of the
# trap CSRs, an s instead of the m: stvec, sepc, scause.
#
# MPP and SPP are return slots, like ra, not the level the hart runs at.
# Writing MPP = supervisor leaves the hart in machine mode; only the mret
# that reads it moves down. No CSR holds the current level: the CSRs tab
# shows it on its "privilege" line. And there is no way back up by
# writing them: mstatus is machine only (0x300) and sstatus supervisor
# only (0x100), so a user program touching either gets Illegal_Instruction.
# Up is only ever a trap, into the handler the higher level chose.
#
# The user's ecall is cause 8 (Ecall_From_U_Mode), and medeleg's bit 8 is
# set, so the kernel takes it. When the kernel itself makes an ecall,
# that is cause 9 (Ecall_From_S_Mode), not delegated: it goes up to the
# firmware. That is how a kernel asks firmware for things (OpenSBI's
# services work this way); here it asks to stop.
#
# Registers: s2 is the scause the kernel saw. The handlers use t0 and t1,
# so the program doesn't.
#
# Watch the privilege level at the top of the CSRs tab: machine, then
# supervisor, then user, and back up to supervisor at each ecall. mcause
# stays "no trap yet" until the very end: the user's ecalls never reach
# machine mode.

    .section .text
    .globl _start
_start:                         # machine mode (the firmware), as after reset
    la    t0, machine_trap
    csrw  mtvec, t0             # traps that stay in machine mode
    la    t0, kernel_trap
    csrw  stvec, t0             # the kernel's handler, for delegated traps
    li    t0, 0x100             # bit 8: Ecall_From_U_Mode
    csrw  medeleg, t0           # user system calls go straight to the kernel

    # Down to supervisor mode at kernel_main: mret goes to the level in
    # MPP and the address in mepc, as if returning from a trap that came
    # from the kernel. MPP is two bits (12..11): clear both, then set 01.
    li    t0, 0x1800            # MPP's two bits
    csrc  mstatus, t0           # MPP = 00
    li    t0, 0x800             # 01 << 11
    csrs  mstatus, t0           # MPP = 01: mret will go to supervisor mode
                                # (still machine mode here: MPP is where to go)
    la    t0, kernel_main
    csrw  mepc, t0              # ... at kernel_main
    mret                        # now supervisor mode; MPP is reset to 00

kernel_main:                    # supervisor mode: the kernel
    # Down to user mode at user_main, the same way one level lower: sret
    # goes to the level in SPP and the address in sepc. The kernel can't
    # touch mstatus any more (machine only), so it uses sstatus, its own
    # view of the same register's supervisor fields.
    li    t0, 0x100             # SPP, sstatus bit 8
    csrc  sstatus, t0           # SPP = 0: sret will go to user mode
    la    t0, user_main
    csrw  sepc, t0              # ... at user_main
    sret                        # now user mode

user_main:                      # user mode: the program. No CSRs here:
                                # even csrr t0, sstatus would trap.
    li    a0, 32
    li    a7, 1                 # system call 1: add 10 to a0
    ecall                       # to the kernel: a0 = 42
    li    a7, 93                # system call 93: exit
    ecall                       # doesn't come back

    .balign 4                   # stvec's low 2 bits are its mode
kernel_trap:                    # supervisor mode: delegated traps arrive here.
                                # The trap set SPP = 0 (it came from user mode)
                                # and raised the level to supervisor.
    csrr  s2, scause            # 8: Ecall_From_U_Mode
    li    t1, 93
    beq   a7, t1, kernel_exit
    addi  a0, a0, 10            # system call 1: the answer goes back in a0
    csrr  t0, sepc
    addi  t0, t0, 4             # past the ecall
    csrw  sepc, t0
    sret                        # back down to user mode: SPP, saved by the trap

kernel_exit:
    ecall                       # Ecall_From_S_Mode (9): up to the firmware

    .balign 4                   # mtvec's low 2 bits are its mode
machine_trap:                   # machine mode: check what happened
    addi  t0, a0, -42
    seqz  t0, t0                # 1: the kernel answered the system call
    addi  t1, s2, -8
    seqz  t1, t1                # 1: the kernel took the user's ecall (8)
    add   t0, t0, t1
    csrr  t1, mcause
    addi  t1, t1, -9
    seqz  t1, t1                # 1: this is the kernel's ecall (9), the
    add   t0, t0, t1            #    first trap machine mode has seen
    csrr  t1, mstatus
    srli  t1, t1, 11
    andi  t1, t1, 3             # MPP, which the trap set: the mode it came from
    addi  t1, t1, -1
    seqz  t1, t1                # 1: supervisor mode (01)
    add   a0, t0, t1            # a0 = 4
    csrw  mtvec, zero           # no handler, so ebreak stops the machine
    ebreak

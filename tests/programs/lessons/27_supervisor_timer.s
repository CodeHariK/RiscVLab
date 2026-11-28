# Lesson 27: The supervisor timer
# The kernel's own clock tick (Sstc): it sets an alarm in stimecmp against time, takes the timer interrupt when the alarm comes, and sets the next one. Machine mode only switches it on at boot.
# Expect: exit 4
# Docs: stimecmp, menvcfg, time, mcounteren, mideleg, interrupt
#
# Lesson 21's timer belongs to machine mode: its alarm (mtimecmp) is a
# CLINT register, and its interrupt (MTIP) can't be delegated. A kernel
# in supervisor mode needs a tick too, to take the CPU back from a
# program and run another. With the Sstc extension it has its own alarm,
# a CSR: stimecmp. The supervisor timer interrupt (STIP) is pending while
# time >= stimecmp; the kernel lowers it by setting a later stimecmp.
#
# Machine mode only switches things on, once, as xv6's start.c does:
#
#   firmware, at boot                kernel
#   -----------------                ------
#   menvcfg.STCE = 1   Sstc on
#   mcounteren.TM = 1  may read time
#   mideleg bit 5      STI is the kernel's
#   mret  ------------------------>  sie.STIE on
#                                    stimecmp = time + 10
#                                    SIE on
#                                    work: count in s3 ...
#                                    tick (time >= stimecmp):
#                                      stimecmp = time + 10   STIP falls
#                                      sret                   back to work
#                                    ... three ticks, then:
#   check  <-----------------------  ecall
#
# Unlike lesson 26's SSIP, the handler doesn't clear STIP in sip (it
# can't: STIP belongs to the timer). Setting the next alarm is what
# lowers it. Forgetting would bring the interrupt back right after sret,
# forever.
#
# time counts steps here (one tick per step), so "time + 10" is 10 steps
# away. On QEMU's virt board time ticks at 10 MHz: xv6's 1000000 is a
# tenth of a second.
#
# Registers: s1 counts ticks, s2 is scause, s3 counts loop rounds, s4 is
# 3, the number of ticks to wait for. The handler uses t0.
#
# Watch stimecmp in the CSRs tab: it counts down "STIP in N steps", and
# jumps 10 ahead at each tick.

    .section .text
    .globl _start
_start:                         # machine mode (the firmware)
    la    t0, machine_trap
    csrw  mtvec, t0
    la    t0, kernel_trap
    csrw  stvec, t0
    li    t0, 1
    slli  t0, t0, 63            # bit 63: STCE
    csrs  menvcfg, t0           # Sstc on: stimecmp drives STIP
    li    t0, 2                 # bit 1: TM (time)
    csrs  mcounteren, t0        # the kernel may read time
    li    t0, 0x20              # bit 5: STIP, the supervisor timer interrupt
    csrw  mideleg, t0           # it goes to the kernel

    li    t0, 0x1800
    csrc  mstatus, t0
    li    t0, 0x800
    csrs  mstatus, t0           # MPP = 01: supervisor
    la    t0, kernel_main
    csrw  mepc, t0
    mret                        # down to the kernel, for good

kernel_main:                    # supervisor mode
    li    t0, 0x20
    csrs  sie, t0               # STIE: the kernel wants timer interrupts
    rdtime t0
    addi  t0, t0, 10
    csrw  stimecmp, t0          # first tick: 10 ticks from now
    csrsi sstatus, 2            # SIE on
    li    s4, 3
work:                           # the "program": count, until three ticks
    addi  s3, s3, 1
    blt   s1, s4, work
    ecall                       # Ecall_From_S_Mode: up to the firmware

    .balign 4                   # stvec's low 2 bits are its mode
kernel_trap:                    # supervisor mode: a tick
    csrr  s2, scause            # bit 63 (interrupt) + 5 (timer)
    addi  s1, s1, 1
    rdtime t0
    addi  t0, t0, 10
    csrw  stimecmp, t0          # next tick; STIP falls now
    sret                        # back to work, at the instruction not run yet

    .balign 4                   # mtvec's low 2 bits are its mode
machine_trap:                   # machine mode: check what happened
    addi  t0, s1, -3
    seqz  t0, t0                # 1: three ticks
    li    t1, 1
    slli  t1, t1, 63
    addi  t1, t1, 5             # 0x8000000000000005
    sub   t1, s2, t1
    seqz  t1, t1                # 1: scause was the supervisor timer
    add   t0, t0, t1
    snez  t1, s3                # 1: the loop ran between the ticks
    add   t0, t0, t1
    csrr  t1, mcause
    addi  t1, t1, -9
    seqz  t1, t1                # 1: the kernel's ecall is machine mode's
    add   a0, t0, t1            #    first trap: no tick ever woke it; a0 = 4
    csrw  mtvec, zero           # no handler, so ebreak stops the machine
    ebreak

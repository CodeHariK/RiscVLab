# Lesson 24: User mode
# Drop from machine mode into user mode with mret, find out what user code may not do, and come back up with ecall: a system call, then exit.
# Expect: exit 4
# Docs: privilege, mret, csr-addresses, mcounteren, Illegal_Instruction, Ecall_From_U_Mode, system-call
#
# Until now every lesson ran in machine mode, which may do anything. An
# OS runs programs in user mode instead, where they can only compute and
# ask the kernel for everything else:
#
#   machine mode                         user mode
#   ------------                         ---------
#   set mtvec, allow cycle,
#   MPP = user, mepc
#   mret  -----------------------------> user_main:
#                                          csrr cycle     allowed
#   handler: Illegal_Instruction <-------  csrr mstatus   not allowed
#     skip it, mret  ------------------->
#   handler: ecall from U (8)    <-------  ecall          a7 = 1: add 10
#     a0 += 10, mret  ------------------>
#   handler: ecall from U (8)    <-------  ecall          a7 = 93: exit
#     check the results, ebreak
#
# The only ways between the modes: mret goes down to the mode in
# mstatus.MPP (bits 12..11: 00 user, 11 machine), and every trap goes up
# to machine mode, saving the mode it came from in MPP. That's why the
# handler's mret returns to user mode without being told: the trap set
# MPP = user. The system calls work like lesson 13's: request number in
# a7, argument and answer in a0 (93 is Linux's number for exit).
#
# What user mode may touch is written in each CSR's address: bits 9:8
# are the lowest mode allowed. mstatus is 0x300 (bits 9:8 = 11: machine
# only); cycle is 0xc00 (00: anyone, read-only). The counters (cycle,
# time, instret) also need machine mode's permission: their bit in
# mcounteren and scounteren, which start at 0.
#
# Registers: s1 counts the illegal instructions the handler skipped; s2
# is what user mode read from cycle. The handler uses t0 and t1, so the
# user code doesn't (a real handler saves and restores every register it
# touches).
#
# Watch the privilege level at the top of the CSRs tab, and mstatus.MPP
# under it: each trap switches up to machine, each mret back down.

    .section .text
    .globl _start
_start:                         # machine mode, as after reset
    la    t0, handler
    csrw  mtvec, t0             # where traps go
    li    s1, 0

    # Let user mode read cycle. Permission goes down one mode at a time:
    # mcounteren lets supervisor mode read it, scounteren passes it on to
    # user mode. Bit 0 is cycle (1 time, 2 instret). Without these two
    # lines, csrr cycle below would trap like csrr mstatus.
    li    t0, 1                 # bit 0: cycle
    csrs  mcounteren, t0        # supervisor mode may read cycle...
    csrs  scounteren, t0        # ...and so may user mode

    # No instruction just switches to user mode (a program could use it
    # to escape). The only way down is mret, "return from a trap". So we
    # set things up as if a trap had come from user_main in user mode,
    # and "return" there: a place we never came from. Every OS starts its
    # first user program this way (xv6 does it with sret).
    li    t0, 0x1800            # mstatus.MPP: bits 12..11
    csrc  mstatus, t0           # MPP = 00: "the trap came from user mode"
    la    t0, user_main
    csrw  mepc, t0              # "the trap happened at user_main"
    mret                        # down to user mode, at user_main

user_main:                      # user mode from here
    csrr  s2, cycle             # allowed: 0xc00 is readable by anyone, and we allowed it
    csrr  s3, mstatus           # machine only: traps, the handler skips it
    li    a0, 32
    li    a7, 1                 # system call 1: add 10 to a0
    ecall                       # a0 = 42
    li    a7, 93                # system call 93: exit
    ecall                       # doesn't come back

    .balign 4                   # mtvec's low 2 bits are its mode
handler:                        # machine mode: every trap arrives here
    csrr  t0, mcause
    li    t1, 2
    beq   t0, t1, illegal       # 2: Illegal_Instruction
    li    t1, 8
    beq   t0, t1, system_call   # 8: ecall from user mode
    csrw  mtvec, zero           # anything else is a bug: stop
    ebreak

illegal:
    addi  s1, s1, 1             # count it, then skip the instruction
    j     skip

system_call:
    li    t1, 93
    beq   a7, t1, exit
    addi  a0, a0, 10            # system call 1: the answer goes back in a0

skip:
    csrr  t0, mepc
    addi  t0, t0, 4             # past the instruction that trapped
    csrw  mepc, t0
    mret                        # back down: MPP = user, saved by the trap

exit:                           # machine mode for good: check what happened
    addi  t0, s1, -1
    seqz  t0, t0                # 1: exactly one instruction was illegal
    addi  t1, a0, -42
    seqz  t1, t1                # 1: the system call added 10
    add   t0, t0, t1
    csrr  t1, mstatus
    srli  t1, t1, 11
    andi  t1, t1, 3             # MPP: the mode the exit ecall came from
    seqz  t1, t1                # 1: user mode
    add   t0, t0, t1
    snez  t1, s2                # 1: user mode read cycle
    add   a0, t0, t1            # a0 = 4
    csrw  mtvec, zero           # no handler, so ebreak stops the machine
    ebreak

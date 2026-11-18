# Lesson 21: A timer interrupt
# Set the CLINT's alarm, turn timer interrupts on, and keep counting: the interrupt arrives between two instructions, the handler runs, and the count carries on.
# Expect: exit 9
# Docs: clint, interrupt, mie, mtvec, mret
#
# Lessons 12-14 had traps the program caused itself (ecall, a bad
# instruction). An interrupt comes from outside: here the CLINT, the
# timer, at 0x02000000. This lesson uses two of its registers:
#
#   0x0200bff8  mtime     read  (ld)  the clock: here it goes up by one
#                                     per instruction
#   0x02004000  mtimecmp  write (sd)  the alarm: once mtime reaches it,
#                                     mip.MTIP = 1 (timer interrupt pending)
#   not used:   msip (software interrupts between harts)
#
# A pending interrupt is only taken when it is enabled twice over:
#   mie.MTIE (bit 7)      this kind of interrupt is wanted
#   mstatus.MIE (bit 3)   interrupts are on at all
# Then, at the next instruction boundary, the hart traps to mtvec with
# mcause = 0x8000000000000007 (bit 63: an interrupt; 7: the timer), and
# mepc = the instruction that hadn't run yet. The handler returns with
# mret and that instruction runs as if nothing had happened.
#
# The handler must move the alarm on (or turn MTIE off): MTIP stays 1
# while mtime >= mtimecmp, so returning without doing so would take the
# same interrupt again at once. Here it sets mtimecmp to all ones: no
# more alarms.
#
# Watch the Devices tab count down "timer interrupt pending in N steps",
# the CSRs tab show mip's timer bit turn on, and the Steps tab mark the
# step that was "interrupted before it ran". Because time counts
# instructions here, the interrupt lands on the same instruction every
# run (on real hardware it would vary a little).
# a0 = how many times the count loop went round before the alarm: 9.

    .section .text
    .globl _start
_start:
    la    t0, handler
    csrw  mtvec, t0             # where traps (and interrupts) go

    li    s0, 0x02000000        # the CLINT
    li    t1, 0x4000
    add   s1, s0, t1            # s1 = the address of mtimecmp
    li    t1, 0xbff8
    add   s2, s0, t1            # s2 = the address of mtime

    ld    t0, 0(s2)             # now
    addi  t0, t0, 25            # the alarm: 25 ticks (instructions) from now
    sd    t0, 0(s1)             # mtimecmp = now + 25

    li    t0, 0x80
    csrs  mie, t0               # mie.MTIE: timer interrupts wanted
    csrsi mstatus, 8            # mstatus.MIE: interrupts on

    li    a0, 0                 # times round the loop
    li    a1, 0                 # set to 1 by the handler
count:
    addi  a0, a0, 1             # the interrupt arrives between two of
    beqz  a1, count             # these instructions, not at a chosen one
    csrw  mtvec, zero           # no handler, so ebreak stops the machine
    ebreak                      # the handler ran: stop; exit code a0

handler:
    li    a1, 1                 # tell the loop the interrupt happened
    li    t0, -1
    sd    t0, 0(s1)             # mtimecmp = all ones: no more alarms (MTIP = 0)
    mret                        # back to the instruction that was interrupted

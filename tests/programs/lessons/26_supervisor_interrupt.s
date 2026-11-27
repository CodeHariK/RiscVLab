# Lesson 26: A supervisor interrupt
# Machine mode hands the software interrupt to the kernel (mideleg). The kernel turns it on (sie), raises one (sip), and sees it wait until supervisor interrupts are on (sstatus.SIE), then arrive between two instructions.
# Expect: exit 5
# Docs: interrupt, mideleg, sie, sstatus, sret, interrupt-sources
#
# Lesson 21 took a machine timer interrupt in machine mode. Here the
# kernel takes an interrupt itself, in supervisor mode, without machine
# mode waking up. Three switches must be on, as for machine interrupts,
# but the kernel's own ones:
#
#   switch           set by     meaning
#   mideleg bit 1    machine    this interrupt is the kernel's, not the firmware's
#   sie bit 1        kernel     the kernel wants it (SSIE)
#   sstatus.SIE      kernel     the kernel may be interrupted now
#   sip bit 1        anyone     it is pending (SSIP)
#
# The supervisor software interrupt (SSIP, bit 1) is the simplest: no
# device raises it, software does, by writing sip. Here the kernel
# raises its own, while SIE is still off, so it waits:
#
#   kernel_main                      kernel_trap
#   -----------                      -----------
#   csrs sie, 2       SSIE on
#   csrs sip, 2       SSIP pending: waits (SIE = 0)
#   addi s3, s3, 1    runs
#   csrsi sstatus, 2  SIE on  ------>  scause = interrupt 1
#                                      csrc sip, 2   clear SSIP
#   addi s3, s3, 1  <-----------------  sret
#   ecall: up to the firmware, which checks
#
# Two things differ from an ecall. sepc is the instruction that hadn't
# run yet (the second addi), so the handler returns there with no
# sepc + 4. And the handler must clear SSIP: the bit stays pending until
# software clears it, and with it still set, the interrupt would be taken
# again the moment sret turns SIE back on.
#
# Registers: s1 counts interrupts taken; s2 is scause and s4 sepc as the
# handler saw them; s3 counts the addis that ran.
#
# Watch sip in the CSRs tab ("pending (delegated only)"): it turns on two
# steps before the interrupt is taken.

    .section .text
    .globl _start
_start:                         # machine mode (the firmware)
    la    t0, machine_trap
    csrw  mtvec, t0
    la    t0, kernel_trap
    csrw  stvec, t0
    li    t0, 2                 # bit 1: SSIP, the supervisor software interrupt
    csrw  mideleg, t0           # it goes to the kernel

    li    t0, 0x1800
    csrc  mstatus, t0
    li    t0, 0x800
    csrs  mstatus, t0           # MPP = 01: supervisor
    la    t0, kernel_main
    csrw  mepc, t0
    mret                        # down to the kernel

kernel_main:                    # supervisor mode
    li    t1, 2                 # bit 1: SSIE in sie, SSIP in sip
    csrs  sie, t1               # the kernel wants software interrupts
    csrs  sip, t1               # raise one: pending, but SIE is 0
    addi  s3, s3, 1             # so this still runs
    csrsi sstatus, 2            # SIE on: taken before the next instruction
after_enable:
    addi  s3, s3, 1             # runs after the handler returns
    ecall                       # Ecall_From_S_Mode: up to the firmware

    .balign 4                   # stvec's low 2 bits are its mode
kernel_trap:                    # supervisor mode: the interrupt
    csrr  s2, scause            # bit 63 (interrupt) + 1 (software)
    csrr  s4, sepc              # after_enable: the instruction not run yet
    csrc  sip, t1               # handled: clear SSIP, or it comes back
    addi  s1, s1, 1
    sret                        # SIE back on, pc = sepc (no + 4)

    .balign 4                   # mtvec's low 2 bits are its mode
machine_trap:                   # machine mode: check what happened
    addi  t0, s1, -1
    seqz  t0, t0                # 1: exactly one interrupt
    li    t1, 1
    slli  t1, t1, 63
    addi  t1, t1, 1             # 0x8000000000000001
    sub   t1, s2, t1
    seqz  t1, t1                # 1: scause was the software interrupt
    add   t0, t0, t1
    addi  t1, s3, -2
    seqz  t1, t1                # 1: both addis ran, each once
    add   t0, t0, t1
    la    t1, after_enable
    sub   t1, s4, t1
    seqz  t1, t1                # 1: sepc was the instruction not run yet
    add   t0, t0, t1
    csrr  t1, mcause
    addi  t1, t1, -9
    seqz  t1, t1                # 1: the kernel's ecall is machine mode's
    add   a0, t0, t1            #    first trap; a0 = 5
    csrw  mtvec, zero           # no handler, so ebreak stops the machine
    ebreak

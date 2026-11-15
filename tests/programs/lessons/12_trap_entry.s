# Lesson 12: Traps: ecall and a handler
# Install a trap handler in mtvec; ecall jumps to it, and the CPU records why (mcause) and where (mepc).
# Expect: exit 11
#
# WHAT A TRAP IS
# A trap is the CPU stopping what it is doing and jumping to one fixed
# place, the trap handler, whose address software put in the mtvec CSR.
# Here the trap is caused on purpose with ecall. On a trap the CPU itself,
# with no instruction asking for it:
#   1. mepc   = the address of the instruction that trapped (the ecall)
#   2. mcause = why: 11 (0xb) = Ecall_From_M_Mode
#   3. mtval  = extra detail (a bad address, bad instruction bits; 0 here)
#   4. mstatus: MPIE = MIE, MIE = 0 (interrupts off), MPP = the old privilege
#   5. pc     = mtvec, so the next instruction is the handler's first
# Watch the CSRs tab as you step over the ecall: all of these change at once.
#
# WHY NOT JUST CALL A FUNCTION?
# Here a trap looks like a function call, because this one program makes
# the trap and handles it. Traps exist for the cases where that is not so:
# - A trap can come unplanned: a bad load, an invalid instruction, a timer
#   tick between two instructions (lesson 14). The interrupted code saved
#   nothing and may be using every register, ra too, so the CPU can't put
#   the return address or the reason in x0..x31. It puts them in CSRs.
# - A trap changes privilege. A user program must not jal into the kernel:
#   it could jump into the middle of kernel code and run it with kernel
#   power. A trap enters only through the one door the kernel chose
#   (mtvec), and raises the privilege level on the way in.
# - The door must be locked: if a user program could write mtvec, it could
#   send traps to its own code. So mtvec and the other trap CSRs can only
#   be changed by more privileged code.
# An OS needs traps for system calls (ecall: a user program asks the
# kernel to write a file), for protection (a buggy program faults and the
# kernel kills just that program), for sharing the CPU (a timer interrupt
# takes the CPU back from a program stuck in a loop), and for devices
# (the disk interrupts when it is done). Everything here runs in machine
# mode, so the lessons show the mechanism; the protection comes with user
# and supervisor mode, on the way to xv6.
#
# THE HANDLER
# There is one handler for every kind of trap, so it starts by asking why
# (mcause) and where from (mepc). mepc points at the ecall itself:
# returning there would run the ecall again and trap forever, so the
# handler returns to mepc + 4. It returns with a plain jump (jr), which is
# only enough here; lesson 13 shows the proper way back, mret.
#
# Removing the handler at the end matters too: ebreak is also a trap, and
# with mtvec still set it would jump to the handler instead of ending the
# program. (Emulator rule: mtvec = 0 means no handler, so a trap stops.)

    .section .text
    .globl _start
_start:
    la   t0, handler
    csrw mtvec, t0          # traps now go to `handler`
    ecall                   # a system call: trap!
    addi a0, s0, 0          # back here: the handler saved mcause in s0 (11)
    csrw mtvec, zero        # remove the handler, so the ebreak below stops the program
    ebreak                  # (with a handler set, ebreak would trap to it instead)

    .balign 4
handler:
    csrr s0, mcause         # why: 11 = Ecall_From_M_Mode
    csrr s1, mepc           # where: the address of the ecall
    addi s1, s1, 4          # skip over it
    jr   s1                 # return by jumping there (lesson 13 uses mret)

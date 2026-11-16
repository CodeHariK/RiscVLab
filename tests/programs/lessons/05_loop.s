# Lesson 05: Branches and a loop
# Add up 1..5 with a loop, and watch the PC jump back until the counter reaches the end.
# Expect: exit 15
# Docs: beq, blt, labels
#
# A branch compares two registers and, if the comparison holds, jumps to a
# label (the assembler turns the label into an offset from the branch):
#
#   beq / bne    equal / not equal
#   blt / bge    less than / greater or equal (signed)
#
# Taken: the PC moves to the label. Not taken: execution falls through to
# the next instruction. The explanation line says which will happen.

    .section .text
    .globl _start
_start:
    addi a0, zero, 0        # a0 = sum = 0
    addi t0, zero, 1        # t0 = i = 1
    addi t1, zero, 6        # t1 = 6: the loop ends when i reaches it
loop:
    add  a0, a0, t0         # sum = sum + i
    addi t0, t0, 1          # i = i + 1
    blt  t0, t1, loop       # if i < 6, jump back to loop; otherwise fall through
    ebreak                  # a0 = 1 + 2 + 3 + 4 + 5 = 15

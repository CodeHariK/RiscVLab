# Lesson 07: Memory: load and store
# Add up an array from the program's data with lw, store the total with sw, and compare lb with lbu.
# Expect: exit 110
#
# The .data section holds the program's variables. It is loaded into
# memory with the code (here at 0x80001000; see the ELF and Memory tabs).
#
#   lw rd, off(rs1)    rd = the 32-bit word at address rs1 + off
#   sw rs2, off(rs1)   store the low 32 bits of rs2 at address rs1 + off
#   lb / lbu           load one byte, sign-extended / zero-extended
#
# Open the Memory tab: the word about to be loaded turns purple, and the
# word the store writes turns blue, then gets the "changed" background.

    .section .text
    .globl _start
_start:
    la   t0, numbers        # t0 = address of the array (la: auipc + addi)
    addi t1, zero, 4        # t1 = how many numbers are left
    addi a0, zero, 0        # a0 = sum
loop:
    lw   t2, 0(t0)          # t2 = the number at address t0
    add  a0, a0, t2         # sum += number
    addi t0, t0, 4          # move to the next word (4 bytes on)
    addi t1, t1, -1         # one fewer left
    bnez t1, loop           # repeat while some are left (bnez = bne with zero)
    la   t3, total
    sw   a0, 0(t3)          # store the sum into the variable `total`
    la   t4, byte_ff
    lb   t5, 0(t4)          # the byte 0xff, sign-extended:  t5 = -1
    lbu  t6, 0(t4)          # the same byte, zero-extended:  t6 = 255
    ebreak                  # a0 = 10 + 20 + 30 + 50 = 110

    .section .data
numbers: .word 10, 20, 30, 50
total:   .word 0
byte_ff: .byte 0xff

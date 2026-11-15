# Lesson 08: Calling a function
# jal jumps to a function and saves the return address in ra; jalr (ret) jumps back to it.
# Expect: exit 42
#
#   jal  ra, label     ra = address of the next instruction; jump to label
#   jalr zero, 0(ra)   jump to the address in ra (the "ret" shorthand)
#
# By convention, arguments go in a0, a1, ... and the result comes back in
# a0. Watch ra get the return address, and the PC come back after each call.

    .section .text
    .globl _start
_start:
    addi a0, zero, 10       # first argument
    addi a1, zero, 11       # second argument
    jal  ra, add_two        # call add_two(10, 11): a0 = 21
    addi a1, a0, 0          # a1 = 21
    jal  ra, add_two        # call add_two(21, 21): a0 = 42
    ebreak                  # a0 = 42

# add_two(a0, a1) returns a0 + a1
add_two:
    add  a0, a0, a1         # the result goes in a0
    jalr zero, 0(ra)        # return to the caller (rd = zero: nothing saved)

# Assembler directives: instructions to the assembler

Directives start with a dot. They are not instructions for the CPU: they
tell the assembler where to put things (sections), which names other
files may use, and what data to place in memory. Labels (`name:`) and
comments (`#`) are here too. None of them become instructions, so the
debugger never stops on them.

Same format as instructions.md.

## .section .text .data .bss .rodata .pushsection .popsection - Sections

*directive*

Does: chooses which section the following code or data goes into.
- `.text`: code.
- `.data`: variables with starting values.
- `.bss`: variables that start as zero.
- `.rodata`: constants (read-only data).

`.section .text` and plain `.text` mean the same. `.pushsection` / `.popsection` switch to a section and back again.

How it works: the assembler collects everything for each section separately, even when the source switches back and forth. The linker script (`link.ld`) then gives each section its address: here `.text` starts at 0x80000000 and `.data` at the next 4 KiB page, 0x80001000. The ELF tab shows where everything ended up.

For: keeping code and data apart, so code can later be made read-only and data non-executable (with paging).

Watch out: `.bss` takes no space in the file. The ELF only records its size, and the loader fills that memory with zeros. A variable with a starting value must go in `.data`.

Related: .globl, labels

Example:
```
    .section .text
_start:
    la   t0, numbers
    .section .data
numbers: .word 0xa, 0x14
```

## .globl .global .weak - Visible to the linker

*directive*

Does:
- `.globl name` (or `.global`) makes a label visible outside this file, so the linker and other files can use it.
- `.weak name` does the same, but another file may define the name again, and that definition wins.

For: `_start` must be global, because the linker script's `ENTRY(_start)` looks it up to set the ELF's entry point. Functions that other files call must be global too.

Watch out: labels are local to their file unless made global, so two files can each have their own `loop:` without a clash.

Related: labels, .section

Example:
```
    .globl _start
_start:
```

## .byte .half .word .dword - Data values

*directive*

Does: places numbers in memory, one after another.
- `.byte`: 1 byte each.
- `.half`: 2 bytes.
- `.word`: 4 bytes.
- `.dword`: 8 bytes.

How it works: `.word 0xa, 0x14` places 8 bytes: 0a 00 00 00 14 00 00 00. Each value is stored lowest byte first (little-endian). A label just before them names the address of the first one.

For: variables with starting values, and tables of numbers.

Watch out:
- In RISC-V a "word" is 4 bytes and a "double word" 8. (On x86 a word is 2 bytes.)
- A value can be a label: `.dword handler` stores that address.

Related: .section, labels, lw, ld

Example:
```
numbers: .word 0xa, 0x14, 0x1e, 0x32   # four 4-byte numbers (lesson 07)
total:   .word 0x0
byte_ff: .byte 0xff
```

## .ascii .asciz .string - Text

*directive*

Does: places the characters of a string in memory, one byte each. `.asciz` and `.string` add a zero byte at the end; `.ascii` does not.

For: messages to print. C strings end with a zero byte, which is how code finds the end.

Watch out: without the zero (`.ascii`), a printing loop runs on into whatever comes next in memory.

Related: .byte, lbu

Example:
```
message: .asciz "hello\n"    # 7 bytes: h e l l o \n 0
```

## .space .zero - Reserve bytes

*directive*

Does: `.space n` reserves n bytes, filled with zeros (or with a second argument's value). `.zero n` is the same with zeros.

How it works: the stack grows down, from high addresses to low ones. So reserve the space first and put a label after it: that label is the top, where sp starts.

For: arrays without starting values, and stacks.

Watch out: in `.bss` the bytes take no room in the file; in `.data` they do.

Related: .section, .balign, labels

Example:
```
    .section .bss
    .balign 16
stack:     .space 512      # 512 bytes for the stack (lesson 09)
stack_top:                 # sp starts here and moves down
```

## .align .balign .p2align - Alignment

*directive*

Does: pads with zeros (or nops in code) until the address is a multiple of a number.
- `.balign n`: a multiple of n bytes.
- `.p2align n`: a multiple of 2^n bytes.
- `.align n`: on RISC-V, the same as `.p2align`.

For: hardware that needs aligned addresses.
- The trap handler in mtvec must be 4-byte aligned: mtvec's low 2 bits hold the mode.
- sp should stay 16-byte aligned.
- 8-byte variables load fastest from 8-byte aligned addresses.

Watch out: `.align 4` aligns to 16 bytes, not 4. `.balign` takes the number of bytes directly, which is why the lessons use it.

Related: mtvec, .space

Example:
```
    .balign 4
handler:                   # safe to put in mtvec
```

## .equ .set - Named constants

*directive*

Does: `.equ name, value` (or `.set`) gives a number a name. It takes no memory: the assembler puts the number wherever the name is used.

For: readable constants such as device addresses, sizes and bit masks.

Related: li

Example:
```
.equ UART_BASE, 0x10000000
    li t0, UART_BASE
```

## .macro .endm - Macros

*directive*

Does: `.macro name args` ... `.endm` defines a piece of assembly. Wherever `name` is used, the assembler copies the piece in with the arguments filled in.

For: repeated boilerplate. The riscv-tests use macros for their setup and for every test case, which is why one source line there can stand for many instructions.

Related: .equ

Example:
```
.macro push reg
    addi sp, sp, -0x8
    sd   \reg, 0(sp)
.endm
    push ra                # becomes the addi and the sd
```

## labels - Labels and comments

*not a directive, but also no instruction*

Does:
- `name:` gives a name to the current address. It produces no bytes.
- Numbered labels (`1:`) can repeat; `1b` / `1f` refer to the nearest one backwards / forwards.
- `#` starts a comment that runs to the end of the line.

For: branch and jump targets, function names and variable names. Labels end up in the ELF's symbol table, which is how the debugger shows names in the Disassembly and Memory tabs and in the step details (`numbers+0x4`).

Related: .globl, .section

Example:
```
loop:                      # the address of the next instruction
    addi t1, t1, -0x1
    bnez t1, loop
```

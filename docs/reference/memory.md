# Memory: the map, copying, filling and allocating

Where things are in the physical address space, what programs do with
memory beyond a single load or store (copying and filling it with loops
of loads and stores), and where a program's memory comes from. Lesson 22
counts what a copy costs; lesson 23 builds a full memcpy and memset. Same
format as instructions.md.

## memory-map - Physical memory map

*where things are*

Does: which physical addresses hold RAM and which hold devices. This emulator copies QEMU's `virt` board, so the same programs (and later xv6) run on both.

How it works:
| Address | What | In this emulator |
|---|---|---|
| 0x00001000 | boot ROM on QEMU | no |
| 0x02000000 | CLINT: timer and software interrupts (see clint) | yes |
| 0x0c000000 | PLIC: device interrupt controller | coming |
| 0x10000000 | UART: serial port, for printing (see uart) | yes |
| 0x10001000 | virtio disk | coming |
| 0x80000000-0x87ffffff | RAM, 128 MiB: programs are loaded here | yes |
Anything else is empty: a load or store there raises an access fault.

For: devices are used with ordinary loads and stores to their addresses (memory-mapped I/O, see mmio); the bus decides whether an address means RAM or a device.

Related: link.ld, Load_Access_Fault Store_Access_Fault, segment, mmio, uart, clint

## memcpy memset - Copying and filling memory

*how memory is copied*

Does: memcpy copies n bytes from one place to another; memset fills n bytes with one value. RISC-V has no instruction for either: both are loops of loads and stores, and a load or store moves 1, 2, 4 or 8 bytes. So the question is how many bytes each trip round the loop moves.

How it works: the simplest loop moves one byte per trip; the fast one moves 8, the most RV64I can move at once (a register is 64 bits). Both are the same six instructions:
```
# a0 = dst, a1 = src, a2 = n        # a0 = dst, a1 = src, a2 = n (a multiple of 8)
copy_bytes:                         copy_dwords:
    lbu  t0, 0(a1)  # 1 byte in         ld   t0, 0(a1)  # 8 bytes in
    sb   t0, 0(a0)  # 1 byte out        sd   t0, 0(a0)  # 8 bytes out
    addi a1, a1, 1                      addi a1, a1, 8
    addi a0, a0, 1                      addi a0, a0, 8
    addi a2, a2, -1                     addi a2, a2, -8
    bnez a2, copy_bytes                 bnez a2, copy_dwords
```
What copying one 4096-byte page costs:
| Loop | Trips | Instructions, roughly |
|---|---|---|
| a byte per trip | 4096 | 24,600 |
| 8 bytes per trip | 512 | 3,100 |
| 8 bytes, unrolled 4 times (4 ld + 4 sd, then each pointer moved once by 32) | 128 | 1,500 |
A real memcpy (libc's) works in three parts: single bytes until dst is 8-byte aligned, 8 bytes at a time for the middle, and single bytes for the last 0 to 7. The middle needs dst and src aligned at the same time, so their low 3 bits must match: (dst ^ src) & 7 == 0. When they don't, a simple memcpy copies every byte singly; libc instead loads aligned 8-byte words from src and shifts and merges each pair into place, so even then each store moves 8 bytes. Unrolling cuts the branches and pointer updates per byte. Chips with the V (vector) extension move 16 to 64 or more bytes per instruction instead.

memset is the same loop with a store and no load. To store 8 bytes at a time, it first repeats the byte across a register: for c = 0xab, c * 0x0101010101010101 = 0xabababababababab, then `sd` of that. A big memset(p, 0, n) can use `cbo.zero` (the Zicboz extension), which zeroes a whole 64-byte cache block in one instruction.

For: every program that moves data: copying a string or a struct, a kernel copying a page or a system call's arguments, zeroing a new buffer. xv6 keeps its own memmove and memset simple: one byte per trip (kernel/string.c). Lesson 22 compares the two loops (385 instructions against 49); lesson 23 builds the full memcpy and memset, where 47 bytes with matching alignment cost 111 instructions and with mismatched alignment 342.

Emulator: each load or store is one bus access of 1, 2, 4 or 8 bytes. Misaligned ones just work, as on QEMU (a real chip may be slower, or trap so software does the access in pieces). An instruction stores at most once, 8 bytes at most, which is why one undo record per step can hold what it overwrote.

Watch out: memcpy's two ranges must not overlap; copying forwards over itself would overwrite bytes before reading them. memmove handles overlap by copying backwards when dst is after src.

Related: malloc, word, little-endian, lb lh lw ld, sb sh sw sd, minstret

Example:
```
li   t1, 0xab
li   t2, 0x0101010101010101
mul  t1, t1, t2          # t1 = 0xabababababababab
sd   t1, 0(a0)           # memset of 8 bytes in one store
```

## malloc - Where a program's memory comes from

*heap memory*

Does: malloc(n) hands out the address of n bytes the program may use until it calls free. It copies nothing and clears nothing: it only decides which addresses are yours.

How it works: two levels, one inside the program and one in the kernel:
| Level | Hands out | In xv6 |
|---|---|---|
| the kernel | whole pages (4096 bytes), mapped into the process | sbrk, then growproc, then kalloc |
| malloc, in the program | small blocks, carved out of those pages | user/umalloc.c (the K&R malloc) |
- The kernel keeps a list of free physical pages (kalloc). The sbrk system call takes some and maps them into the process's page table, so the process's memory grows.
- malloc puts a hidden header just before each address it returns, holding the block's size. free puts the block on a free list, and joins it with free neighbours. When the list has nothing big enough, malloc asks sbrk for more (xv6's morecore asks for at least 4096 units at a time).
So most calls to malloc are a walk down the free list and maybe a split, with no system call; only running out of memory goes to the kernel.

What new memory holds:
| From | Starts as |
|---|---|
| malloc | whatever its last user left there |
| calloc | zeros (calloc clears it) |
| a fresh page from the OS | zeros, so one program can't read another's old data |
| xv6's kalloc | junk bytes (5) on purpose, so kernel code that forgets to set memory fails loudly |

For: memory whose size or lifetime isn't known when the program is written: a line typed by the user, a list that grows, a buffer returned from a function. The stack only holds memory until the function returns.

Emulator: there is no OS yet, so the lessons use fixed buffers in .data instead. RAM starts as zeros because it comes straight from the host OS (mmap, zeroed_pages.odin), the same trick an OS uses for fresh pages.

Watch out: reading malloc memory before writing it gives leftovers, not zeros; and the block header sits just before your pointer, so writing past the end of one block can break the next.

Related: memcpy, stack, memory-map

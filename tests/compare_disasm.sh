#!/bin/sh
# Compares the emulator's disassembler with objdump's, for one program.
#
#   compare_disasm.sh <rvemu> <program.bin> <program.dis>
#
# <program.dis> is `objdump -d -M no-aliases` output (made by
# tests/programs/Makefile). Both listings are normalised to
#   <address> <bits> <mnemonic> <operands>
# (objdump's labels like "<fail>" and "# ..." comments are dropped).

emulator=$1
binary=$2
listing=$3
name=$(basename "$binary")

expected=$(mktemp)
actual=$(mktemp)
trap 'rm -f "$expected" "$actual"' EXIT

awk -F'\t' '/^ +[0-9a-f]+:\t/ {
    address = $1; gsub(/[ :]/, "", address)
    bits = $2; gsub(/ /, "", bits)
    text = $3
    if ($4 != "") text = text " " $4
    sub(/ #.*/, "", text)
    sub(/ <.*/, "", text)
    print address, bits, text
}' "$listing" > "$expected"

"$emulator" "$binary" --disasm > "$actual"

if diff -u "$expected" "$actual"; then
    echo "PASS disasm $name"
else
    echo "FAIL disasm $name"
    exit 1
fi

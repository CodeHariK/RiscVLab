# Puts each ';'-separated statement of a preprocessed riscv-test on its
# own line, so every instruction gets its own source line. Text after '#'
# is a comment and is left alone (comments can contain ';').
{
    hash = index($0, "#")
    if (hash > 0) {
        code = substr($0, 1, hash - 1)
        comment = substr($0, hash)
    } else {
        code = $0
        comment = ""
    }
    gsub(/;[ \t]*/, "\n", code)
    print code comment
}

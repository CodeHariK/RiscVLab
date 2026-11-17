#!/bin/sh
# Runs every lesson program and checks the exit code its header promises
# ("# Expect: exit N"), and what it prints, if its header says
# ("# Expect output: text": the program's stdout, without the final
# newline), so the lessons keep working as the emulator grows. Also checks
# that every lesson can be stepped all the way back (undo).
#
#   run_lessons.sh <rvemu> <lessons source dir> <lessons build dir>

emulator=$1
sources=$2
build=$3
status=0

for source in "$sources"/*.s; do
    name=$(basename "$source" .s)
    expected=$(sed -n 's/^# Expect: exit \([0-9]*\).*/\1/p' "$source")
    expected_output=$(sed -n 's/^# Expect output: //p' "$source")
    output=$("$emulator" "$build/$name.elf" 2> /dev/null)
    actual=$?
    # (A lesson without the line must print nothing: both are empty.)
    if [ "$actual" = "$expected" ] && [ "$output" = "$expected_output" ] && "$emulator" "$build/$name.elf" --check-undo > /dev/null 2>&1; then
        echo "PASS lesson $name"
    else
        echo "FAIL lesson $name (exit $actual, expected $expected; printed \"$output\", expected \"$expected_output\"; or undo check failed)"
        status=1
    fi
done
exit $status

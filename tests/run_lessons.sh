#!/bin/sh
# Runs every lesson program and checks the exit code its header promises
# ("# Expect: exit N"), so the lessons keep working as the emulator grows.
# Also checks that every lesson can be stepped all the way back (undo).
#
#   run_lessons.sh <rvemu> <lessons source dir> <lessons build dir>

emulator=$1
sources=$2
build=$3
status=0

for source in "$sources"/*.s; do
    name=$(basename "$source" .s)
    expected=$(sed -n 's/^# Expect: exit \([0-9]*\).*/\1/p' "$source")
    "$emulator" "$build/$name.elf" > /dev/null
    actual=$?
    if [ "$actual" = "$expected" ] && "$emulator" "$build/$name.elf" --check-undo > /dev/null; then
        echo "PASS lesson $name"
    else
        echo "FAIL lesson $name (exit $actual, expected $expected, or undo check failed)"
        status=1
    fi
done
exit $status

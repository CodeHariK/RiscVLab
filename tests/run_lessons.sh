#!/bin/sh
# Runs every lesson program and checks the exit code its header promises
# ("# Expect: exit N"), so the lessons keep working as the emulator grows.
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
    if [ "$actual" = "$expected" ]; then
        echo "PASS lesson $name"
    else
        echo "FAIL lesson $name (exit $actual, expected $expected)"
        status=1
    fi
done
exit $status

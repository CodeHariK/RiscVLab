#!/bin/sh
# Runs every built riscv-test through the emulator and prints a summary.
#
#   run.sh <rvemu> [build dir]
#
# A test passes when the emulator exits with code 0 (the test wrote
# "exit 0" to tohost). Exit status: 0 if every test passed.

emulator=$1
build=${2:-$(dirname "$0")/build}

passed=0
failed=0
failures=""
for test in "$build"/rv64ui-p-*; do
    case "$test" in *.dis) continue ;; esac
    name=$(basename "$test")
    if output=$("$emulator" "$test" --max-steps 1000000 2>&1); then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        failures="$failures\n  $name: $output"
    fi
done

echo "riscv-tests: $passed passed, $failed failed"
if [ $failed -ne 0 ]; then
    printf "%b\n" "$failures"
    exit 1
fi

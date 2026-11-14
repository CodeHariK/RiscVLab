#!/bin/sh
# Downloads the official riscv-tests (and their test environment) into
# src/, at the commits this project was checked against. src/ is not
# committed (see .gitignore); run this once before `make`.

set -e
cd "$(dirname "$0")"

RISCV_TESTS_URL=https://github.com/riscv-software-src/riscv-tests.git
RISCV_TESTS_COMMIT=3df703cd52d5f0d8224e3c50bf03c6cb70efff98

if [ ! -d src/.git ]; then
    git clone "$RISCV_TESTS_URL" src
fi
cd src
git checkout --quiet "$RISCV_TESTS_COMMIT"
# Only the `env` submodule is needed: the startup code, linker script and
# pass / fail macros the tests are built with.
git submodule update --init env
echo "riscv-tests ready at $(pwd) ($(git rev-parse --short HEAD))"

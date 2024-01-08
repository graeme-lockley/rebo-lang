#!/bin/bash

which zig 2>&1 > /dev/null

HAS_ZIG=$?

if [[ "$HAS_ZIG" != "0" ]]; then
    echo "Error: zig is not installed or in the path. Please install and path correctly."
    exit 1
fi

echo "info: running unit tests"
zig build test || exit 1

echo "info: building debug binary"
zig build install || exit 1

echo "info: running all unit tests"
zig build run -- ./bin/rebo-test || exit 1

echo "info: building release binary"
zig build-exe ./src/main.zig -O ReleaseFast -fstrip || exit 1

mv main ./bin/rebo-fast || exit 1
rm main.o || exit 1

rm -f ./bin/rebo || exit 1

ln -s ./rebo-fast ./bin/rebo || exit 1

echo "Success: rebo-fast built and linked to ./bin/rebo-fast"
echo "Success: rebo linked to ./bin/rebo"

echo "Update path to include ./bin"
echo "# export PATH=\"\$PATH:$PWD/bin\""

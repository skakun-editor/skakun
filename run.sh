#!/bin/sh

FLAGS=-Doptimize=ReleaseSafe
zig build $FLAGS || exit 1
zig build $FLAGS run -- "$@" || reset
./last-log.sh

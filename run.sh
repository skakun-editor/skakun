#!/usr/bin/bash

FLAGS="-Doptimize=ReleaseSafe ${term/#/-Dterm=}"
zig build $FLAGS || exit 1
zig build $FLAGS run -- "$@" || reset
./last-log.sh

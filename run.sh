#!/bin/sh

zig build run -Doptimize=ReleaseSafe -- "$@"
reset
./last-log.sh

#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
for test in tests/test_*.lua; do
    "${LUA:-lua}" "$test"
done

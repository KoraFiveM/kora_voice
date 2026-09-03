#!/usr/bin/env bash
# Runs every qbvoice smoke test with plain Lua (no busted, no FXServer, no
# Mumble, no database). Exits non-zero on any failure.
#
# Each file loads only the realm it exercises: the server suites dofile
# server/*.lua, the client suites dofile client/*.lua, and neither mocks the
# other's natives. A file that reached across the realm boundary would fail here
# with an undefined global rather than passing and then breaking in game.
set -uo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lua_bin="${LUA:-lua}"
status=0
headers=0

for file in "$dir"/smoke/*.lua; do
    echo "== $(basename "$file" .lua) =="
    headers=$((headers + 1))
    if ! ( cd "$dir/.." && "$lua_bin" "$file" ); then status=1; fi
    echo
done

# A test file that dies mid-load still prints its header, so "0 failed" alone
# does not mean everything ran -- compare the header count against the summary
# count. This is not hypothetical here: a CFX backtick hash literal anywhere in
# a dofile'd file kills plain lua SILENTLY, printing the header and no summary.
# Deliberately NOT prefixed with "== ", which would make this line look like a
# suite header and inflate the very count it exists to report.
echo "-- ran $headers suite(s) --"
exit "$status"

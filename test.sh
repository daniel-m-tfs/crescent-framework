#!/usr/bin/env bash
set -eu

cd "$(dirname "$0")"
export LUA_PATH="./?.lua;./?/init.lua;;"

lua cli.lua test

if [ -x "${OPENRESTY_BIN:-/opt/homebrew/opt/openresty/bin/openresty}" ]; then
	lua cli.lua test:http
fi

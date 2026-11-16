#!/usr/bin/env bash
set -eu

cd "$(dirname "$0")"

lua cli.lua test "$@"

if [ -x "${OPENRESTY_BIN:-/opt/homebrew/opt/openresty/bin/openresty}" ] && [ $# -eq 0 ]; then
	lua cli.lua test:http
fi

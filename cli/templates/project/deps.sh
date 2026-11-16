#!/usr/bin/env bash
# Installs the project's LuaRocks dependencies for OpenResty's LuaJIT into
# ./lua_modules (picked up by nginx.conf and the test runner).
set -eu
cd "$(dirname "$0")"
luajit_dir="${OPENRESTY_LUAJIT:-/opt/homebrew/opt/openresty/luajit}"
for rock in etlua lua-resty-http lua-resty-mail; do
	luarocks --lua-version=5.1 --lua-dir="$luajit_dir" --tree=lua_modules install "$rock"
done

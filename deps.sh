#!/usr/bin/env bash
# Installs the project's LuaRocks dependencies for OpenResty's LuaJIT into
# ./lua_modules (picked up by nginx.conf and the test runner). Override the
# LuaJIT directory with OPENRESTY_LUAJIT.
set -eu
cd "$(dirname "$0")"

luajit_dir="${OPENRESTY_LUAJIT:-}"
if [ -z "$luajit_dir" ]; then
	# Same search order as bin/crescent and `crescent server`, then PATH.
	candidates=(/opt/homebrew/opt/openresty/luajit /usr/local/openresty/luajit /opt/openresty/luajit)
	if command -v openresty >/dev/null 2>&1; then
		prefix="$(dirname "$(dirname "$(command -v openresty)")")"
		candidates+=("$prefix/luajit")
	fi
	for candidate in "${candidates[@]}"; do
		if [ -d "$candidate/include" ]; then luajit_dir="$candidate"; break; fi
	done
fi
if [ -z "$luajit_dir" ]; then
	echo "OpenResty LuaJIT not found; set OPENRESTY_LUAJIT=/path/to/openresty/luajit" >&2
	exit 1
fi
echo "Using LuaJIT from $luajit_dir"

for rock in etlua lua-resty-http lua-resty-mail; do
	luarocks --lua-version=5.1 --lua-dir="$luajit_dir" --tree=lua_modules install "$rock"
done

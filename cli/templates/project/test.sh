#!/usr/bin/env bash
# Unit tests run on OpenResty's LuaJIT (bin/crescent uses `resty`). Inside the
# container: docker compose exec app bin/crescent test
set -eu

cd "$(dirname "$0")"

./bin/crescent test "$@"

if [ -x "${OPENRESTY_BIN:-/opt/homebrew/opt/openresty/bin/openresty}" ] && [ $# -eq 0 ] && [ -f tests/test-http.sh ]; then
	./bin/crescent test:http
fi

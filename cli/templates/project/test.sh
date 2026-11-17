#!/usr/bin/env bash
# Unit tests run on OpenResty's LuaJIT (bin/crescent uses `resty`). Inside the
# container: docker compose exec app bin/crescent test
set -eu

cd "$(dirname "$0")"

./bin/crescent test "$@"

# The HTTP test starts its own OpenResty on APP_PORT; skipped in the container,
# where the app already listens there.
if [ $# -eq 0 ] && [ -f tests/test-http.sh ] && [ ! -f /.dockerenv ]; then
	./bin/crescent test:http
fi

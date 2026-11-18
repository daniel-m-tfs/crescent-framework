#!/usr/bin/env bash
# HTTP smoke test against a real OpenResty: starts nginx.conf with
# APP_ENV=test, checks a few routes and stops it. Run: lua cli.lua test:http
set -eu

cd "$(dirname "$0")/.."

openresty_bin="${OPENRESTY_BIN:-}"
if [ -z "$openresty_bin" ]; then
	for candidate in /opt/homebrew/opt/openresty/bin/openresty /usr/local/openresty/bin/openresty /opt/openresty/bin/openresty; do
		if [ -x "$candidate" ]; then openresty_bin="$candidate"; break; fi
	done
fi
openresty_bin="${openresty_bin:-openresty}"
if ! command -v "$openresty_bin" >/dev/null 2>&1; then
	echo "OpenResty executable not found: $openresty_bin (set OPENRESTY_BIN)" >&2
	exit 2
fi

base_url="http://127.0.0.1:${APP_PORT:-8080}"
tmp_dir="$(mktemp -d)"
trap '"$openresty_bin" -p "$PWD/" -c nginx.conf -s stop >/dev/null 2>&1 || true; rm -rf "$tmp_dir"' EXIT

APP_ENV=test "$openresty_bin" -p "$PWD/" -c nginx.conf

# expect <status> <path> [text the body must contain]
expect() {
	local status
	status="$(curl -sS --retry 20 --retry-delay 0 --retry-connrefused -o "$tmp_dir/body" -w '%{http_code}' "$base_url$2")"
	if [ "$status" != "$1" ]; then
		echo "✗ GET $2: expected $1, got $status" >&2
		cat "$tmp_dir/body" >&2
		exit 1
	fi
	if [ $# -ge 3 ] && ! grep -q "$3" "$tmp_dir/body"; then
		echo "✗ GET $2: body does not contain $3" >&2
		exit 1
	fi
	echo "✓ GET $2 -> $1"
}

expect 200 /health '"status":"ok"'
expect 200 / 'Hello, World!'
expect 200 '/api/hello?name=Ada' 'Hello, Ada!'
expect 422 "/api/hello?name=$(printf 'x%.0s' $(seq 1 51))"
expect 404 /missing

# Static files need a real Content-Type (conf/mime.types): browsers ignore a
# stylesheet served as application/octet-stream.
css_type="$(curl -sS -o /dev/null -w '%{content_type}' "$base_url/public/css/app.css")"
case "$css_type" in
	text/css*) echo "✓ GET /public/css/app.css -> $css_type" ;;
	*) echo "✗ GET /public/css/app.css: expected text/css, got $css_type" >&2; exit 1 ;;
esac

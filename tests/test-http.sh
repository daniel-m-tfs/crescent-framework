#!/usr/bin/env bash
set -eu

cd "$(dirname "$0")/.."

openresty_bin="${OPENRESTY_BIN:-/opt/homebrew/opt/openresty/bin/openresty}"
if ! command -v "$openresty_bin" >/dev/null 2>&1; then
    echo "OpenResty executable not found: $openresty_bin" >&2
    exit 2
fi

base_url="http://127.0.0.1:8080"
tmp_dir="$(mktemp -d)"
trap '"$openresty_bin" -p "$PWD/" -c nginx.conf -s stop >/dev/null 2>&1 || true; rm -rf "$tmp_dir"' EXIT

"$openresty_bin" -p "$PWD/" -c nginx.conf

health_body="$tmp_dir/health.body"
health_headers="$tmp_dir/health.headers"
health_status="$(curl -sS --retry 20 --retry-delay 0 --retry-connrefused \
    -D "$health_headers" -o "$health_body" -w '%{http_code}' "$base_url/health")"
test "$health_status" = "200"
grep -q '"status":"ok"' "$health_body"
grep -qi '^X-Request-Id: ' "$health_headers"

missing_status="$(curl -sS -o /dev/null -w '%{http_code}' "$base_url/missing")"
test "$missing_status" = "404"

method_headers="$tmp_dir/method.headers"
method_status="$(curl -sS -X POST -D "$method_headers" -o /dev/null -w '%{http_code}' "$base_url/health")"
test "$method_status" = "405"
grep -qi '^Allow: GET' "$method_headers"

echo "HTTP integration: OK"
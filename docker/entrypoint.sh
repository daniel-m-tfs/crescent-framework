#!/bin/sh
# Optionally runs pending migrations, then starts OpenResty in the foreground
# (logs go to stdout/stderr, see conf/nginx.docker*.conf).
set -eu
cd /app

if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
    attempts=0
    until bin/crescent db:migrate; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 10 ]; then
            echo "entrypoint: migrations failed after $attempts attempts" >&2
            exit 1
        fi
        echo "entrypoint: database not ready, retrying in 3s ($attempts/10)" >&2
        sleep 3
    done
fi

if [ "$#" -gt 0 ]; then
    exec "$@"
fi
exec openresty -p /app/ -c "${NGINX_CONF:-conf/nginx.docker.conf}" -g 'daemon off;'

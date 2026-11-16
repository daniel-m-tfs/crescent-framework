# Crescent on OpenResty. The alpine-fat variant ships resty (needs perl) and
# luarocks, which the CLI (bin/crescent) and dependency install use.
FROM openresty/openresty:1.31.8.1-alpine-fat

WORKDIR /app

# Pure-Lua dependencies, installed in their own layer so code changes do not
# reinstall them. Keep this list in sync with deps.sh.
RUN luarocks install --tree=/app/lua_modules etlua \
 && luarocks install --tree=/app/lua_modules lua-resty-http \
 && luarocks install --tree=/app/lua_modules lua-resty-mail \
 && apk add --no-cache curl

COPY . /app

# Run as an unprivileged user; nginx only needs to write logs/ and tmp/.
RUN addgroup -S crescent && adduser -S -G crescent -H -h /app crescent \
 && mkdir -p logs tmp \
 && chown -R crescent:crescent logs tmp \
 && chmod +x docker/entrypoint.sh bin/crescent

USER crescent

ENV APP_ENV=production \
    NGINX_CONF=conf/nginx.docker.conf \
    RUN_MIGRATIONS=false

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/health >/dev/null || exit 1

ENTRYPOINT ["docker/entrypoint.sh"]

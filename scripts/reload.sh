#!/usr/bin/env bash
set -euo pipefail

ssh foxii '
  cd /srv/foxii &&
  docker compose config >/dev/null &&
  docker compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile &&
  docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
'

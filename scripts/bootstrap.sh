#!/usr/bin/env bash
set -euo pipefail

ssh foxii '
  docker network inspect foxii-edge >/dev/null 2>&1 ||
    docker network create foxii-edge
  docker volume inspect foxii-caddy-data >/dev/null 2>&1 ||
    docker volume create foxii-caddy-data
  docker volume inspect foxii-caddy-config >/dev/null 2>&1 ||
    docker volume create foxii-caddy-config
'

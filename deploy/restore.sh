#!/usr/bin/env sh
set -eu
backup=$1
gzip -dc "$backup" | docker compose exec -T db psql -U luohao -d luohao
echo "restored $backup"

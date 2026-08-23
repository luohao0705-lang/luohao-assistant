#!/usr/bin/env sh
set -eu
mkdir -p backups
stamp=$(date -u +%Y%m%dT%H%M%SZ)
docker compose exec -T db pg_dump -U luohao -d luohao | gzip > "backups/luohao-$stamp.sql.gz"
find backups -type f -name "luohao-*.sql.gz" -mtime +14 -delete
echo "created backups/luohao-$stamp.sql.gz"

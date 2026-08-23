#!/usr/bin/env sh
set -eu

APP_DIR="${APP_DIR:-/srv/luohao-assistant}"
BRANCH="${BRANCH:-main}"

git -C "$APP_DIR" pull --ff-only origin "$BRANCH"
cd "$APP_DIR/deploy"
docker compose up -d --build
docker compose ps
sh ./verify.sh "${BASE_URL:-https://luo.hsh6.com}"

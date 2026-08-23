#!/usr/bin/env sh
set -eu

BASE_URL="${1:-https://luo.hsh6.com}"
BASE_URL="${BASE_URL%/}"

curl --fail --silent --show-error "$BASE_URL/health"
printf '\n'
curl --fail --silent --show-error "$BASE_URL/health/ready"
printf '\n'

OPENAPI="$(curl --fail --silent --show-error "$BASE_URL/openapi.json")"
case "$OPENAPI" in
  *'"version":"0.4.0"'*) : ;;
  *) echo "unexpected API version" >&2; exit 1 ;;
esac
for route in '"/finance/accounts"' '"/finance/transactions"' '"/finance/debts"'; do
  case "$OPENAPI" in
    *"$route"*) : ;;
    *) echo "missing route: $route" >&2; exit 1 ;;
  esac
done
echo "public API surface ok"

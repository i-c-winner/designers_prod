#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-env/.env.prod}"
SITE_ARG="${2:-}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: env file not found: $ENV_FILE"
  exit 1
fi

# Read BOOTSTRAP_SITE_NAME from env file if site wasn't passed explicitly.
SITE_FROM_ENV="$(grep -E "^BOOTSTRAP_SITE_NAME=" "$ENV_FILE" | tail -n1 | cut -d= -f2- || true)"
SITE_FROM_ENV="${SITE_FROM_ENV%\"}"
SITE_FROM_ENV="${SITE_FROM_ENV#\"}"

SITE="${SITE_ARG:-${SITE:-${SITE_FROM_ENV:-}}}"
if [[ -z "$SITE" ]]; then
  echo "ERROR: site is empty. Pass it as 2nd arg or set BOOTSTRAP_SITE_NAME in $ENV_FILE"
  exit 1
fi

COMPOSE=(
  docker compose
  --env-file "$ENV_FILE"
  -f compose.yaml
  -f overrides/compose.mariadb.yaml
  -f overrides/compose.redis.yaml
  -f overrides/compose.prod.yaml
)

echo "==> Pull images"
"${COMPOSE[@]}" pull

echo "==> Start/Update containers"
"${COMPOSE[@]}" up -d

echo "==> Migrate site: $SITE"
"${COMPOSE[@]}" exec backend bench --site "$SITE" migrate

echo "==> Clear cache: $SITE"
"${COMPOSE[@]}" exec backend bench --site "$SITE" clear-cache

echo "==> Done"

#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/infra/docker-compose.yml"
COMPOSE_ENV_FILE="$ROOT_DIR/infra/.env.example"
STARTED_COMPOSE=0
export COMPOSE_PROJECT_NAME="studynotes-ci-$$"

cleanup() {
  if [ "$STARTED_COMPOSE" = "1" ]; then
    docker compose -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV_FILE" down -v
  fi
}
trap cleanup EXIT INT TERM

cd "$ROOT_DIR/web"

npm ci

if [ "${CI_DOCKER:-0}" = "1" ]; then
  docker compose -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV_FILE" config --quiet
  docker compose -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV_FILE" up -d --wait mysql
  STARTED_COMPOSE=1
  export DATABASE_URL="mysql://studynotes:studynotes-local-password@127.0.0.1:33066/studynotes"
  export MYSQL_INTEGRATION_TESTS=1
  npm run db:migrate
fi

npm run verify

if [ "${CI:-0}" = "1" ]; then
  npx playwright install chromium
fi
npm run test:e2e

if [ "${CI_DOCKER:-0}" = "1" ]; then
  docker compose -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV_FILE" build web
  docker compose -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV_FILE" up -d --wait web
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if REPO_DIR="$(git -C "$ROOT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  REPO_DIR="$(cd "$ROOT_DIR/.." && pwd)"
fi

command="${1:-status}"

mosaic_port="${MOSAIC_PORT:-${PORT:-3777}}"
if [[ ! "$mosaic_port" =~ ^[0-9]+$ ]]; then
  echo "MOSAIC_PORT must be numeric, got: $mosaic_port" >&2
  exit 2
fi

db_kind="${MOSAIC_DB_KIND:-dev}"
db_offset="${MOSAIC_DB_PORT_OFFSET:-10000}"
if [[ ! "$db_offset" =~ ^[0-9]+$ ]]; then
  echo "MOSAIC_DB_PORT_OFFSET must be numeric, got: $db_offset" >&2
  exit 2
fi

db_port="${MOSAIC_DB_PORT:-$((mosaic_port + db_offset))}"
db_user="${MOSAIC_DB_USER:-mosaic}"
db_password="${MOSAIC_DB_PASSWORD:-mosaic}"
db_name="${MOSAIC_DB_NAME:-mosaic}"

branch="$(git -C "$REPO_DIR" branch --show-current 2>/dev/null || true)"
if [[ -z "$branch" ]]; then
  branch="$(basename "$REPO_DIR")"
fi
slug="$(
  printf '%s' "$branch" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g' \
    | cut -c1-48
)"
if [[ -z "$slug" ]]; then
  slug="worktree"
fi

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-mosaic-db-${slug}-${db_kind}-${mosaic_port}}"
export MOSAIC_DB_CONTAINER_NAME="${MOSAIC_DB_CONTAINER_NAME:-mosaic-postgres-${slug}-${db_kind}-${mosaic_port}}"
export MOSAIC_DB_VOLUME_NAME="${MOSAIC_DB_VOLUME_NAME:-mosaic-postgres-${slug}-${db_kind}-${mosaic_port}}"
export MOSAIC_DB_PORT="$db_port"
export MOSAIC_DB_USER="$db_user"
export MOSAIC_DB_PASSWORD="$db_password"
export MOSAIC_DB_NAME="$db_name"
export DATABASE_URL="${DATABASE_URL:-postgres://${db_user}:${db_password}@localhost:${db_port}/${db_name}}"
export DIRECT_DATABASE_URL="${DIRECT_DATABASE_URL:-$DATABASE_URL}"

compose() {
  docker compose -f "$ROOT_DIR/docker-compose.db.yml" "$@"
}

wait_for_postgres() {
  for _ in $(seq 1 60); do
    if compose exec -T postgres pg_isready -U "$db_user" -d "$db_name" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for Postgres on localhost:${db_port}" >&2
  compose ps >&2 || true
  return 1
}

print_status() {
  local redacted_url
  redacted_url="postgres://${db_user}:<redacted>@localhost:${db_port}/${db_name}"
  cat <<EOF
MOSAIC_PORT=$mosaic_port
MOSAIC_DB_KIND=$db_kind
MOSAIC_DB_PORT=$db_port
COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME
MOSAIC_DB_CONTAINER_NAME=$MOSAIC_DB_CONTAINER_NAME
MOSAIC_DB_VOLUME_NAME=$MOSAIC_DB_VOLUME_NAME
DATABASE_URL=$redacted_url
EOF
}

case "$command" in
  up)
    compose up -d
    wait_for_postgres
    print_status
    ;;
  down)
    compose down
    ;;
  reset)
    compose down -v
    compose up -d
    wait_for_postgres
    print_status
    ;;
  status)
    print_status
    compose ps
    ;;
  migrate)
    "$0" up >/dev/null
    bunx drizzle-kit migrate --config "$ROOT_DIR/drizzle.config.ts"
    ;;
  ready)
    compose exec -T postgres pg_isready -U "$db_user" -d "$db_name" >/dev/null
    ;;
  test)
    env \
      -u COMPOSE_PROJECT_NAME \
      -u MOSAIC_DB_CONTAINER_NAME \
      -u MOSAIC_DB_VOLUME_NAME \
      -u MOSAIC_DB_PORT \
      -u DATABASE_URL \
      -u DIRECT_DATABASE_URL \
      MOSAIC_DB_KIND=test \
      MOSAIC_DB_PORT_OFFSET="${MOSAIC_TEST_DB_PORT_OFFSET:-30000}" \
      MOSAIC_DB_NAME="${MOSAIC_TEST_DB_NAME:-mosaic_test}" \
      "$0" up >/dev/null
    export MOSAIC_DB_TEST=1
    export MOSAIC_DB_KIND=test
    export MOSAIC_DB_PORT_OFFSET="${MOSAIC_TEST_DB_PORT_OFFSET:-30000}"
    export MOSAIC_DB_NAME="${MOSAIC_TEST_DB_NAME:-mosaic_test}"
    export MOSAIC_DB_PORT="$((mosaic_port + ${MOSAIC_TEST_DB_PORT_OFFSET:-30000}))"
    export DATABASE_URL="postgres://${db_user}:${db_password}@localhost:${MOSAIC_DB_PORT}/${MOSAIC_DB_NAME}"
    export DIRECT_DATABASE_URL="$DATABASE_URL"
    bunx drizzle-kit migrate --config "$ROOT_DIR/drizzle.config.ts"
    bunx drizzle-kit migrate --config "$ROOT_DIR/drizzle.config.ts"
    bash "$ROOT_DIR/scripts/run-db-behavior-tests.sh"
    ;;
  url)
    printf '%s\n' "$DATABASE_URL"
    ;;
  *)
    echo "Usage: bun db:{up,down,reset,status,migrate,ready,test}" >&2
    exit 2
    ;;
esac

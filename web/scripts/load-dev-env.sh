#!/usr/bin/env bash

# Source this file from direnv or dev scripts. It intentionally keeps local dev
# database URLs derived from MOSAIC_PORT so parallel worktrees cannot hit the same
# Postgres instance by accident.

mosaic_web_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mosaic_existing_mosaic_port_set="${MOSAIC_PORT+x}"
mosaic_existing_mosaic_port="${MOSAIC_PORT-}"
mosaic_existing_port_set="${PORT+x}"
mosaic_existing_port="${PORT-}"
mosaic_existing_db_port_offset_set="${MOSAIC_DB_PORT_OFFSET+x}"
mosaic_existing_db_port_offset="${MOSAIC_DB_PORT_OFFSET-}"
mosaic_existing_db_port_set="${MOSAIC_DB_PORT+x}"
mosaic_existing_db_port="${MOSAIC_DB_PORT-}"
mosaic_existing_db_user_set="${MOSAIC_DB_USER+x}"
mosaic_existing_db_user="${MOSAIC_DB_USER-}"
mosaic_existing_db_password_set="${MOSAIC_DB_PASSWORD+x}"
mosaic_existing_db_password="${MOSAIC_DB_PASSWORD-}"
mosaic_existing_db_name_set="${MOSAIC_DB_NAME+x}"
mosaic_existing_db_name="${MOSAIC_DB_NAME-}"

mosaic_extra_secret_file="${MOSAICTERM_EXTRA_ENV_FILE:-${MOSAIC_WEB_EXTRA_ENV_FILE:-}}"
if [[ -z "$mosaic_extra_secret_file" && -f "$HOME/.secrets/mosaic.env" ]]; then
  mosaic_extra_secret_file="$HOME/.secrets/mosaic.env"
fi

mosaic_secret_file="${MOSAICTERM_ENV_FILE:-${MOSAIC_WEB_ENV_FILE:-}}"
if [[ -z "$mosaic_secret_file" ]]; then
  if [[ -f "$HOME/.secrets/mosaicterm-dev.env" ]]; then
    mosaic_secret_file="$HOME/.secrets/mosaicterm-dev.env"
  elif [[ -f "$HOME/.secret/mosaicterm.env" ]]; then
    mosaic_secret_file="$HOME/.secret/mosaicterm.env"
  elif [[ -f "$HOME/.secrets/mosaicterm.env" ]]; then
    mosaic_secret_file="$HOME/.secrets/mosaicterm.env"
  else
    echo "Missing mosaic web secrets. Expected ~/.secrets/mosaicterm-dev.env." >&2
    return 1 2>/dev/null || exit 1
  fi
fi

mosaic_nounset_was_enabled=0
case "$-" in
  *u*) mosaic_nounset_was_enabled=1 ;;
esac
set +u
set -a
if [[ -n "$mosaic_extra_secret_file" ]]; then
  # shellcheck disable=SC1090
  source "$mosaic_extra_secret_file"
fi
# shellcheck disable=SC1090
source "$mosaic_secret_file"
set +a
if ! grep -q '^STACK_SUPER_SECRET_ADMIN_KEY=' "$mosaic_secret_file"; then
  unset STACK_SUPER_SECRET_ADMIN_KEY
fi
if [[ "$mosaic_nounset_was_enabled" == "1" ]]; then
  set -u
fi

if [[ -n "$mosaic_existing_mosaic_port_set" ]]; then export MOSAIC_PORT="$mosaic_existing_mosaic_port"; fi
if [[ -n "$mosaic_existing_port_set" ]]; then export PORT="$mosaic_existing_port"; fi
if [[ -n "$mosaic_existing_db_port_offset_set" ]]; then export MOSAIC_DB_PORT_OFFSET="$mosaic_existing_db_port_offset"; fi
if [[ -n "$mosaic_existing_db_port_set" ]]; then export MOSAIC_DB_PORT="$mosaic_existing_db_port"; fi
if [[ -n "$mosaic_existing_db_user_set" ]]; then export MOSAIC_DB_USER="$mosaic_existing_db_user"; fi
if [[ -n "$mosaic_existing_db_password_set" ]]; then export MOSAIC_DB_PASSWORD="$mosaic_existing_db_password"; fi
if [[ -n "$mosaic_existing_db_name_set" ]]; then export MOSAIC_DB_NAME="$mosaic_existing_db_name"; fi

mosaic_port="${MOSAIC_PORT:-${PORT:-3777}}"
if [[ ! "$mosaic_port" =~ ^[0-9]+$ ]]; then
  echo "MOSAIC_PORT must be numeric, got: $mosaic_port" >&2
  return 2 2>/dev/null || exit 2
fi
export MOSAIC_PORT="$mosaic_port"

mosaic_db_offset="${MOSAIC_DB_PORT_OFFSET:-10000}"
if [[ ! "$mosaic_db_offset" =~ ^[0-9]+$ ]]; then
  echo "MOSAIC_DB_PORT_OFFSET must be numeric, got: $mosaic_db_offset" >&2
  return 2 2>/dev/null || exit 2
fi
export MOSAIC_DB_PORT_OFFSET="$mosaic_db_offset"

export MOSAIC_DB_USER="${MOSAIC_DB_USER:-mosaic}"
export MOSAIC_DB_PASSWORD="${MOSAIC_DB_PASSWORD:-mosaic}"
export MOSAIC_DB_NAME="${MOSAIC_DB_NAME:-mosaic}"
export MOSAIC_DB_PORT="${MOSAIC_DB_PORT:-$((mosaic_port + mosaic_db_offset))}"

if [[ "${MOSAIC_DEV_USE_EXTERNAL_DATABASE_URL:-0}" != "1" ]]; then
  export DATABASE_URL="postgres://${MOSAIC_DB_USER}:${MOSAIC_DB_PASSWORD}@localhost:${MOSAIC_DB_PORT}/${MOSAIC_DB_NAME}"
  export DIRECT_DATABASE_URL="$DATABASE_URL"
elif [[ -z "${DIRECT_DATABASE_URL:-}" && -n "${DATABASE_URL:-}" ]]; then
  export DIRECT_DATABASE_URL="$DATABASE_URL"
fi

if [[ "${MOSAIC_DEV_USE_EXTERNAL_VM_API_BASE_URL:-0}" != "1" ]]; then
  export MOSAIC_VM_API_BASE_URL="http://localhost:${MOSAIC_PORT}"
fi

# Local dev should not require a checked-in or per-worktree .env.local just to pass
# startup validation for routes the developer is not exercising.
export RESEND_API_KEY="${RESEND_API_KEY:-mosaic-local-dev}"
export MOSAIC_FEEDBACK_FROM_EMAIL="${MOSAIC_FEEDBACK_FROM_EMAIL:-dev@example.invalid}"
export MOSAIC_FEEDBACK_RATE_LIMIT_ID="${MOSAIC_FEEDBACK_RATE_LIMIT_ID:-mosaic-feedback-local}"
export MOSAIC_PUSH_RATE_LIMIT_ID="${MOSAIC_PUSH_RATE_LIMIT_ID:-mosaic-push-local}"

export MOSAIC_WEB_SECRET_ENV_FILE="$mosaic_secret_file"
export MOSAIC_WEB_EXTRA_SECRET_ENV_FILE="$mosaic_extra_secret_file"
export PATH="$mosaic_web_dir/node_modules/.bin:$PATH"

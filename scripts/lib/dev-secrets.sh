# shellcheck shell=bash
# Sourceable helper that loads dogfood/agent Stack credentials for DEBUG dev
# builds and exposes them as MOSAIC_UITEST_STACK_EMAIL / MOSAIC_UITEST_STACK_PASSWORD
# (the env vars the app's existing DEBUG sign-in hook reads).
#
# Precedence MIRRORS the macOS DebugDogfoodCredentialResolver EXACTLY, so a
# `dev-setup.sh --surface both` run signs the Mac and the phone in under the same
# account. A complete email+password pair is resolved from ONE source (never
# mixed across sources). Dogfood account first, then agent; within each account,
# env wins over ~/.secrets/mosaicterm-dev.env, which wins over ~/.secrets/mosaic.env:
#   1. env  MOSAIC_DOGFOOD_STACK_EMAIL / MOSAIC_DOGFOOD_STACK_PASSWORD
#   2. file ~/.secrets/mosaicterm-dev.env  dogfood keys (MOSAIC_DOGFOOD_STACK_*)
#   3. file ~/.secrets/mosaic.env          dogfood keys (MOSAIC_DOGFOOD_STACK_*)
#   4. env  MOSAIC_UITEST_STACK_EMAIL / MOSAIC_UITEST_STACK_PASSWORD
#   5. file ~/.secrets/mosaicterm-dev.env  uitest  keys (MOSAIC_UITEST_STACK_*)
#   6. file ~/.secrets/mosaic.env          uitest  keys (MOSAIC_UITEST_STACK_*)
#
# The dogfood account (a personal dogfood login) is preferred so dev builds sign
# in as the human, not the shared agent.
#
# Usage:
#   source "scripts/lib/dev-secrets.sh"
#   mosaic_dev_secrets_load            # default: dogfood-preferred
#   mosaic_dev_secrets_load --agent    # force the agent account only
#
# After a successful load, MOSAIC_UITEST_STACK_EMAIL / MOSAIC_UITEST_STACK_PASSWORD
# are exported. The email is echoed (so the operator can see who they signed in
# as); the password is NEVER printed.
#
# Returns non-zero (and prints guidance) when no usable credentials are found.

# Read a single KEY=value out of a .env file without sourcing it (so we never
# execute arbitrary secret-file contents). Mirrors DebugDogfoodCredentialResolver.
# parseEnvFile: trims the line, skips blank/`#`-comment lines, trims the key and
# value around the first `=`, and strips ONE layer of matching surrounding single
# or double quotes. Prints the parsed value, or nothing.
mosaic_dev_secrets__read_key() {
  local file="$1" key="$2" line lkey lval
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim leading/trailing whitespace.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == '#'* || "$line" != *'='* ]] && continue
    lkey="${line%%=*}"
    lval="${line#*=}"
    # Trim key and value.
    lkey="${lkey#"${lkey%%[![:space:]]*}"}"; lkey="${lkey%"${lkey##*[![:space:]]}"}"
    lval="${lval#"${lval%%[![:space:]]*}"}"; lval="${lval%"${lval##*[![:space:]]}"}"
    [[ "$lkey" == "$key" ]] || continue
    # Strip one layer of matching surrounding quotes (len >= 2).
    if [[ ${#lval} -ge 2 ]]; then
      if [[ "$lval" == '"'*'"' || "$lval" == "'"*"'" ]]; then
        lval="${lval:1:${#lval}-2}"
      fi
    fi
    printf '%s' "$lval"
    return 0
  done < "$file"
  return 0
}

# Load dev sign-in credentials into MOSAIC_UITEST_STACK_EMAIL / _PASSWORD.
#
#   mosaic_dev_secrets_load [--agent]
#
# Without --agent, the full 6-step chain above runs (dogfood account preferred).
# With --agent, only the agent (uitest) sources are used (env MOSAIC_UITEST_STACK_*,
# then ~/.secrets/mosaic.env uitest keys), for agent-driven flows that must not
# borrow a human's dogfood login.
# Try to resolve a COMPLETE (email + password) credential pair from one source,
# so a partial higher-precedence source never combines with a lower one. Sets
# the caller's `email`/`password` and returns 0 on a full pair, else 1.
#
#   mosaic_dev_secrets__try_pair email_var pw_var <getter...>
#
# The getter is invoked as `<getter> EMAIL` and `<getter> PASSWORD`; it must echo
# the value (or nothing). Both must be non-empty for the pair to be accepted.
mosaic_dev_secrets__try_pair() {
  local email_var="$1" pw_var="$2"; shift 2
  local e p
  e="$("$@" EMAIL)"
  p="$("$@" PASSWORD)"
  if [[ -n "$e" && -n "$p" ]]; then
    printf -v "$email_var" '%s' "$e"
    printf -v "$pw_var" '%s' "$p"
    return 0
  fi
  return 1
}

mosaic_dev_secrets_load() {
  local agent_only=0
  case "${1:-}" in
    --agent) agent_only=1 ;;
  esac

  local home_dir="${HOME:-}"
  local dogfood_file="${home_dir}/.secrets/mosaicterm-dev.env"
  local agent_file="${home_dir}/.secrets/mosaic.env"

  local email="" password=""

  # Per-source getters. Each maps the abstract EMAIL/PASSWORD slot to one
  # source's concrete keys, so a pair always comes from a single source.
  # Invoked indirectly via "$@" in mosaic_dev_secrets__try_pair.
  # shellcheck disable=SC2329
  mosaic_dev_secrets__env_dogfood() {       # step 1
    case "$1" in EMAIL) printf '%s' "${MOSAIC_DOGFOOD_STACK_EMAIL:-}" ;; PASSWORD) printf '%s' "${MOSAIC_DOGFOOD_STACK_PASSWORD:-}" ;; esac
  }
  # shellcheck disable=SC2329
  mosaic_dev_secrets__dev_file_dogfood() {  # step 2: mosaicterm-dev.env dogfood keys
    case "$1" in EMAIL) mosaic_dev_secrets__read_key "$dogfood_file" MOSAIC_DOGFOOD_STACK_EMAIL ;; PASSWORD) mosaic_dev_secrets__read_key "$dogfood_file" MOSAIC_DOGFOOD_STACK_PASSWORD ;; esac
  }
  # shellcheck disable=SC2329
  mosaic_dev_secrets__agent_file_dogfood() {  # step 3: mosaic.env dogfood keys
    case "$1" in EMAIL) mosaic_dev_secrets__read_key "$agent_file" MOSAIC_DOGFOOD_STACK_EMAIL ;; PASSWORD) mosaic_dev_secrets__read_key "$agent_file" MOSAIC_DOGFOOD_STACK_PASSWORD ;; esac
  }
  # shellcheck disable=SC2329
  mosaic_dev_secrets__env_uitest() {        # step 4
    case "$1" in EMAIL) printf '%s' "${MOSAIC_UITEST_STACK_EMAIL:-}" ;; PASSWORD) printf '%s' "${MOSAIC_UITEST_STACK_PASSWORD:-}" ;; esac
  }
  # shellcheck disable=SC2329
  mosaic_dev_secrets__dev_file_uitest() {   # step 5: mosaicterm-dev.env uitest keys
    case "$1" in EMAIL) mosaic_dev_secrets__read_key "$dogfood_file" MOSAIC_UITEST_STACK_EMAIL ;; PASSWORD) mosaic_dev_secrets__read_key "$dogfood_file" MOSAIC_UITEST_STACK_PASSWORD ;; esac
  }
  # shellcheck disable=SC2329
  mosaic_dev_secrets__agent_file_uitest() { # step 6: mosaic.env uitest keys
    case "$1" in EMAIL) mosaic_dev_secrets__read_key "$agent_file" MOSAIC_UITEST_STACK_EMAIL ;; PASSWORD) mosaic_dev_secrets__read_key "$agent_file" MOSAIC_UITEST_STACK_PASSWORD ;; esac
  }

  if [[ "$agent_only" -eq 1 ]]; then
    # Agent flow: only the shared agent (uitest) sources (steps 4 and 6).
    mosaic_dev_secrets__try_pair email password mosaic_dev_secrets__env_uitest \
      || mosaic_dev_secrets__try_pair email password mosaic_dev_secrets__agent_file_uitest
  else
    # Full chain, identical to DebugDogfoodCredentialResolver steps 1..6.
    mosaic_dev_secrets__try_pair email password mosaic_dev_secrets__env_dogfood \
      || mosaic_dev_secrets__try_pair email password mosaic_dev_secrets__dev_file_dogfood \
      || mosaic_dev_secrets__try_pair email password mosaic_dev_secrets__agent_file_dogfood \
      || mosaic_dev_secrets__try_pair email password mosaic_dev_secrets__env_uitest \
      || mosaic_dev_secrets__try_pair email password mosaic_dev_secrets__dev_file_uitest \
      || mosaic_dev_secrets__try_pair email password mosaic_dev_secrets__agent_file_uitest
  fi

  if [[ -z "$email" || -z "$password" ]]; then
    cat >&2 <<EOF
error: no dev sign-in credentials found.

Run the one-time team dogfood setup to store YOUR personal Stack account
(it prompts, verifies, and writes ~/.secrets/mosaicterm-dev.env for you):

  scripts/setup-team-dev.sh

(falls back to the shared agent MOSAIC_UITEST_STACK_* in ~/.secrets/mosaic.env;
pass --agent to force the agent account.)
EOF
    return 2
  fi

  export MOSAIC_UITEST_STACK_EMAIL="$email"
  export MOSAIC_UITEST_STACK_PASSWORD="$password"
  # Email only; never echo the password.
  echo "==> dev sign-in account: $MOSAIC_UITEST_STACK_EMAIL"
  return 0
}

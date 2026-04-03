# Shared helpers for test-unit.sh and test-integration.sh.
# Source this file; do not execute directly.

CONFUSIO_PORT=18080
MOCK_PORT=18081
CONFUSIO_BIN=$(pwd)/confusio.com
MOCK_BIN=$(pwd)/mock-gitea.com
HURL=$(pwd)/hurl
HURL_RETRY="--retry 10 --retry-interval 200 --connect-timeout 5 --max-time 15"

# Start a command in a new session so Redbean's kill(0,SIGTERM) does not
# propagate to the test process group.
start_isolated() {
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" &
  else
    "$@" &
  fi
}

# start_confusio <dir> [extra args...]
# Launches confusio.com from <dir> on $CONFUSIO_PORT.
start_confusio() {
  local dir="$1"; shift
  local args="${*:-}"
  if command -v setsid >/dev/null 2>&1; then
    (cd "$dir" && setsid sh "$CONFUSIO_BIN" -p "$CONFUSIO_PORT" $args) &
  else
    (cd "$dir" && sh "$CONFUSIO_BIN" -p "$CONFUSIO_PORT" $args) &
  fi
}

start_mock() {
  start_isolated sh "$MOCK_BIN" -p "$MOCK_PORT"
}

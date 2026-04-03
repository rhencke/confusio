#!/usr/bin/env bash
set -euo pipefail

PORT=18080

START="sh ./confusio.com -p $PORT"
if command -v setsid >/dev/null 2>&1; then
  setsid $START &
else
  $START &
fi
PID=$!
trap "kill $PID 2>/dev/null || true" EXIT

./hurl --retry 10 --retry-interval 200 --connect-timeout 1 --max-time 5 --variable host=localhost:$PORT test/root.hurl

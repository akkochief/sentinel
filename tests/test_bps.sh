#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  [[ $1 == "$2" ]] || fail "expected '$2', got '$1'"
}

source "$PROJECT_DIR/bps.sh"

PORT_SPEC="80,443,8000-8002,80"
EXCLUDE_PORT_SPEC="8001"
build_ports
assert_eq "${PORTS[*]}" "80 443 8000 8002"

TARGETS=()
TARGET_SET=()
MAX_TARGETS=10
expand_target_spec "192.0.2.0/30"
assert_eq "${TARGETS[*]}" "192.0.2.1 192.0.2.2"

ipv4_to_int "192.0.2.15" || fail "ipv4_to_int failed"
int_to_ipv4 "$REPLY"
assert_eq "$REPLY" "192.0.2.15"

if command -v python3 >/dev/null 2>&1; then
  TEST_DIR=$(mktemp -d)
  HTTP_PORT=18775
  python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 >"$TEST_DIR/http.log" 2>&1 &
  HTTP_PID=$!
  cleanup_test() {
    kill "$HTTP_PID" 2>/dev/null || true
    wait "$HTTP_PID" 2>/dev/null || true
    rm -rf -- "$TEST_DIR"
  }
  trap cleanup_test EXIT
  sleep 0.3
  bash "$PROJECT_DIR/bps.sh" 127.0.0.1 \
    -p "$HTTP_PORT,$((HTTP_PORT + 1))" \
    --include-closed \
    --http-info \
    --probe-all-http \
    --json "$TEST_DIR/result.json" \
    --csv "$TEST_DIR/result.csv" \
    --txt "$TEST_DIR/result.txt" \
    --no-color >/dev/null || fail "CLI scan failed"
  grep -q '"tool": "BPS SH"' "$TEST_DIR/result.json" || fail "JSON tool field missing"
  grep -q '"state":"open"' "$TEST_DIR/result.json" || fail "open result missing"
  grep -q 'HTTP/' "$TEST_DIR/result.json" || fail "HTTP metadata missing"
  grep -q 'target,port,state' "$TEST_DIR/result.csv" || fail "CSV header missing"
  grep -q 'BPS SH 3.0.0' "$TEST_DIR/result.txt" || fail "TXT header missing"
fi

printf 'All BPS SH tests passed.\n'

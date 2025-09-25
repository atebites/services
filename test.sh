#!/usr/bin/env bash
set -euo pipefail

BASE="http://localhost:8000"
ACCEPT_OK="Accept: application/json; version=2"
ACCEPT_DEPRECATED="Accept: application/json; version=1"
ACCEPT_REMOVED="Accept: application/json; version=0"
ACCEPT_INVALID="Accept: application/json; version=99"

# Helper: run curl and capture body + status
call_api() {
  local METHOD=$1
  local URL=$2
  local DATA=${3:-}
  local HEADER=${4:-"$ACCEPT_OK"}

  if [[ -n "$DATA" ]]; then
    RESPONSE=$(curl -i -s -X "$METHOD" "$BASE$URL" -H "$HEADER" -w "\n%{http_code}" -H "Content-Type: application/json" -d "$DATA")
  else
    RESPONSE=$(curl -i -s -X "$METHOD" "$BASE$URL" -H "$HEADER" -w "\n%{http_code}")
  fi

  STATUS=$(echo "$RESPONSE" | tail -n1)
  HEADERS_BODY=$(echo "$RESPONSE" | sed '$d' | tr -d '\r')
  HEADERS=$(echo "$HEADERS_BODY" | sed -n '/^$/q;p')
  BODY=$(echo "$HEADERS_BODY" | sed -n '/^$/,$p' | sed '1d')

  echo ">>> $METHOD $URL ($STATUS)"
  echo "Headers:"
  echo "$HEADERS"
  echo "Body:"
  echo "$BODY"
}

# Helper: assert status
assert_status() {
  local EXPECTED=$1
  if [[ "$STATUS" != "$EXPECTED" ]]; then
    echo "!!! Expected status $EXPECTED but got $STATUS"
    exit 1
  fi
}

assert_headers_contains() {
  local EXPECTED=$1
  if ! grep -q "$EXPECTED" <<<"$HEADERS"; then
    echo "!!! Expected header to contain: $EXPECTED"
    exit 1
  fi
}

# Helper: assert body contains substring
assert_body_contains() {
  local EXPECTED=$1
  if ! grep -q "$EXPECTED" <<<"$BODY"; then
    echo "!!! Expected body to contain: $EXPECTED"
    exit 1
  fi
}

echo "=== Starting API tests ==="

# Root
call_api GET /
assert_status 200
assert_body_contains '"message": "Message service"'

# Version negotiation
call_api GET / "" "Accept: application/json"
assert_status 200

call_api GET / "" "$ACCEPT_DEPRECATED"
assert_status 200
assert_headers_contains "Deprecation"
assert_headers_contains "Sunset"

call_api GET / "" "$ACCEPT_REMOVED"
assert_status 410

call_api GET / "" "$ACCEPT_INVALID"
assert_status 406

# Create message
call_api POST /message '{"content":"Hello world","author":"alice"}'
assert_status 201
assert_body_contains '"content": "Hello world"'
MSG_ID=$(echo "$BODY" | grep -o '"id": [0-9]*' | awk '{print $2}')

# Get all messages
call_api GET /message
assert_status 200
assert_body_contains '"id": '"$MSG_ID"

# Get one
call_api GET /message/$MSG_ID
assert_status 200
assert_body_contains '"id": '"$MSG_ID"

# PUT update
call_api PUT /message/$MSG_ID '{"content":"Hello updated","author":"bob"}'
assert_status 200
assert_body_contains '"author": "bob"'

# PATCH update
call_api PATCH /message/$MSG_ID '{"author":"charlie"}'
assert_status 200
assert_body_contains '"author": "charlie"'

# DELETE
call_api DELETE /message/$MSG_ID
assert_status 204

# Verify deletion
call_api GET /message/$MSG_ID
assert_status 404

# Error cases
call_api GET /wrongpath
assert_status 404

call_api POST /message '{"content":}' 
assert_status 400

call_api POST /message '{"author":"nobody"}'
assert_status 400

call_api GET /message/notanid
assert_status 400

call_api PUT /message/999 '{"content":"foo","author":"bar"}'
assert_status 404

call_api PATCH /message/999 '{"content":"x"}'
assert_status 404

call_api DELETE /message/999
assert_status 404

echo "=== All tests passed successfully ==="

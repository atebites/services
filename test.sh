#!/usr/bin/env bash
set -euo pipefail

# Configuration
readonly API_HOST="${API_HOST:-127.0.0.1}"
readonly API_PORT="${API_PORT:-8000}"
readonly API_URL="http://${API_HOST}:${API_PORT}"
readonly SERVICES_DIR="services"
readonly STARTUP_WAIT=3
readonly SHUTDOWN_WAIT=2

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global state
VERBOSE=0
TARGET_SERVICE=""
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SERVICE_PID=""

# Response globals (set by http_request)
RESP_HEADERS_RAW=""
RESP_HEADERS_JSON=""
RESP_BODY=""
RESP_STATUS=""

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Test HTTP REST services with CRUD operations.

OPTIONS:
    -v, --verbose       Enable verbose output (show all test details)
    -s, --service DIR   Test only the specified service directory
    -h, --help          Show this help message

EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -s|--service)
                TARGET_SERVICE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done
}

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_verbose() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo -e "${NC}[DEBUG]${NC} $*"
    fi
}

# headers_to_json: convert raw header block to a JSON object with lowercase header names.
# Uses jq to robustly handle escaping / special characters.
headers_to_json() {
    local raw="$1"
    raw=$(printf '%s' "$raw" | tr -d '\r')

    IFS=$'\n' read -r -d '' -a lines <<< "$raw"$'\0'

    local json_entries=()
    for line in "${lines[@]}"; do
        [[ "$line" =~ ^HTTP/ ]] && continue
        [[ ! "$line" =~ ^[^:]+:[[:space:]]*.*$ ]] && break
        local name
        name=$(echo "$line" | sed -E 's/:.*$//' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/_/g')
        local value
        value=$(echo "$line" | cut -d':' -f2- | sed 's/^ *//')
        value=$(printf '%s' "$value" | sed 's/"/\\"/g')
        json_entries+=("\"$name\":\"$value\"")
    done

    if (( ${#json_entries[@]} == 0 )); then
        echo "{}"
    else
        printf "{%s}" "$(IFS=,; echo "${json_entries[*]}")"
    fi
}

# Make HTTP request and populate RESP_HEADERS_RAW, RESP_HEADERS_JSON, RESP_BODY, RESP_STATUS
# Usage: http_request METHOD PATH VERSION [BODY] [EXTRA_CURL_ARGS]
http_request() {
    local method=$1
    local path=$2
    local version="${3:-}"
    local body="${4:-}"
    local extra_args="${5:-}"

    local headers_file
    headers_file=$(mktemp)
    local curl_args=( -s -D "$headers_file" -X "$method" )
    [[ -n "$version" ]] && curl_args+=( -H "Accept: application/json; version=${version}" )
    [[ -n "$body" ]] && curl_args+=( -H "Content-Type: application/json" -d "$body" )
    [[ -n "$extra_args" ]] && read -r -a extra_array <<< "$extra_args" && curl_args+=( "${extra_array[@]}" )
    curl_args+=( "${API_URL}${path}" )

    # Get body
    RESP_BODY=$(curl "${curl_args[@]}" 2>/dev/null || echo "")
    # Strip trailing carriage returns
    RESP_BODY=$(printf '%s' "$RESP_BODY" | tr -d '\r')

    # Read headers
    local raw_headers
    raw_headers=$(<"$headers_file")
    rm -f "$headers_file"
    raw_headers=$(printf '%s' "$raw_headers" | tr -d '\r')

    RESP_HEADERS_RAW="$raw_headers"
    RESP_HEADERS_JSON=$(headers_to_json "$RESP_HEADERS_RAW")

    # Extract HTTP status from first line
    RESP_STATUS=$(echo "$RESP_HEADERS_RAW" | head -n1 | awk '{print $2}')
}

# Assertions
assert_status() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ "$actual" == "$expected" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_verbose "✓ $test_name (expected: $expected, got: $actual)"
        return 0
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        if [[ $VERBOSE -eq 1 ]]; then
            log_error "✗ $test_name (expected: $expected, got: $actual)"
            log_verbose "Headers raw:\n$RESP_HEADERS_RAW"
            log_verbose "Body:\n$RESP_BODY"
        fi
        return 1
    fi
}

assert_header() {
    local headers_json="$1"
    local header_name="$2"
    local test_name="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    # header_name lowercased in JSON
    local key
    key=$(echo "$header_name" | tr '[:upper:]' '[:lower:]')
    if echo "$headers_json" | jq -e ".[\"$key\"]" > /dev/null 2>&1; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_verbose "✓ $test_name (header '$header_name' present)"
        return 0
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        if [[ $VERBOSE -eq 1 ]]; then
            log_error "✗ $test_name (header '$header_name' missing)"
            log_verbose "Headers raw:\n$RESP_HEADERS_RAW"
            log_verbose "Headers JSON:\n$headers_json"
        fi
        return 1
    fi
}

assert_no_header() {
    local headers_json="$1"
    local header_name="$2"
    local test_name="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local key
    key=$(echo "$header_name" | tr '[:upper:]' '[:lower:]')
    if echo "$headers_json" | jq -e ".[\"$key\"]" > /dev/null 2>&1; then
        FAILED_TESTS=$((FAILED_TESTS + 1))
        if [[ $VERBOSE -eq 1 ]]; then
            log_error "✗ $test_name (header '$header_name' should not be present)"
            log_verbose "Headers raw:\n$RESP_HEADERS_RAW"
            log_verbose "Headers JSON:\n$headers_json"
        fi
        return 1
    else
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_verbose "✓ $test_name (header '$header_name' correctly absent)"
        return 0
    fi
}

# Start service (uses pixi)
start_service() {
    local service_dir="$1"
    log_info "Starting service in $service_dir..."
    pushd "$service_dir" > /dev/null || { log_warn "Cannot enter $service_dir, skipping"; return 2; }

    if [[ ! -f "pixi.toml" ]]; then
        log_warn "No pixi.toml found in $service_dir, skipping..."
        popd > /dev/null
        return 2
    fi

    log_verbose "Running pixi install..."
    if ! pixi install > /dev/null 2>&1; then
        log_warn "Failed to install dependencies for $service_dir, skipping..."
        popd > /dev/null
        return 2
    fi

    log_verbose "Running pixi run service..."
    pixi run service > /dev/null 2>&1 &
    SERVICE_PID=$!

    popd > /dev/null

    log_verbose "Waiting ${STARTUP_WAIT}s for service to start (PID: $SERVICE_PID)..."
    sleep "$STARTUP_WAIT"

    if [[ -z "$SERVICE_PID" ]] || ! kill -0 "$SERVICE_PID" 2>/dev/null; then
        log_warn "Service process $SERVICE_PID not running, skipping..."
        SERVICE_PID=""
        return 2
    fi

    return 0
}

stop_service() {
    if [[ -n "$SERVICE_PID" ]]; then
        log_verbose "Stopping service (PID: $SERVICE_PID)..."
        kill "$SERVICE_PID" 2>/dev/null || true
        wait "$SERVICE_PID" 2>/dev/null || true
        sleep "$SHUTDOWN_WAIT"
        SERVICE_PID=""
    fi
}

# Test logic (refactored to use http_request and RESP_* globals)
run_tests() {
    local service_name="$1"
    log_info "Testing $service_name..."

    local initial_passed=$PASSED_TESTS
    local initial_failed=$FAILED_TESTS

    # --- Version 0 (should be gone) ---
    log_verbose "Testing Version 0 (removed)..."
    http_request "GET" "/" "0"
    assert_status "410" "$RESP_STATUS" "Version 0: GET / returns 410 Gone"

    http_request "POST" "/message" "0" '{"author":"test","content":"test"}'
    assert_status "410" "$RESP_STATUS" "Version 0: POST /message returns 410 Gone"

    # --- Missing version header ---
    log_verbose "Testing missing version header..."
    # call http_request with empty version to omit Accept header
    http_request "GET" "/" ""
    assert_status "406" "$RESP_STATUS" "Missing version: Returns 406 Not Acceptable"

    # --- Invalid version ---
    log_verbose "Testing invalid version..."
    http_request "GET" "/" "999"
    assert_status "406" "$RESP_STATUS" "Invalid version 999: Returns 406 Not Acceptable"

    # --- Version 1 (deprecated) ---
    log_verbose "Testing Version 1 (deprecated)..."
    http_request "GET" "/" "1"
    assert_status "200" "$RESP_STATUS" "Version 1: GET / returns 200 OK"
    assert_header "$RESP_HEADERS_JSON" "Deprecation" "Version 1: Deprecation header present"
    assert_header "$RESP_HEADERS_JSON" "Sunset" "Version 1: Sunset header present"

    # Create two messages v1
    http_request "POST" "/message" "1" '{"author":"Alice","content":"First message"}'
    assert_status "201" "$RESP_STATUS" "Version 1: Create message returns 201"
    local msg1_id
    msg1_id=$(printf '%s' "$RESP_BODY" | jq -r '.id')

    http_request "POST" "/message" "1" '{"author":"Bob","content":"Second message"}'
    assert_status "201" "$RESP_STATUS" "Version 1: Create second message returns 201"
    local msg2_id
    msg2_id=$(printf '%s' "$RESP_BODY" | jq -r '.id')

    # Get specific message
    http_request "GET" "/message/${msg1_id}" "1"
    assert_status "200" "$RESP_STATUS" "Version 1: GET /message/{id} returns 200"

    # Get non-existent
    http_request "GET" "/message/99999" "1"
    assert_status "404" "$RESP_STATUS" "Version 1: GET non-existent message returns 404"

    # List messages
    http_request "GET" "/message" "1"
    assert_status "200" "$RESP_STATUS" "Version 1: GET /message returns 200"

    # Update (PUT)
    http_request "PUT" "/message/${msg1_id}" "1" '{"author":"Alice Updated","content":"Updated content"}'
    assert_status "200" "$RESP_STATUS" "Version 1: PUT /message/{id} returns 200"

    # Partial update (PATCH)
    http_request "PATCH" "/message/${msg2_id}" "1" '{"content":"Patched content"}'
    assert_status "200" "$RESP_STATUS" "Version 1: PATCH /message/{id} returns 200"

    # --- Version 2 (current) ---
    log_verbose "Testing Version 2 (current)..."
    http_request "GET" "/" "2"
    assert_status "200" "$RESP_STATUS" "Version 2: GET / returns 200 OK"
    assert_no_header "$RESP_HEADERS_JSON" "Deprecation" "Version 2: No Deprecation header"
    assert_no_header "$RESP_HEADERS_JSON" "Sunset" "Version 2: No Sunset header"

    # Create multiple messages for pagination tests
    log_verbose "Creating messages for pagination tests..."
    local -a msg_ids=()
    local i
    for i in $(seq 1 15); do
        http_request "POST" "/message" "2" "{\"author\":\"User${i}\",\"content\":\"Message ${i}\"}"
        assert_status "201" "$RESP_STATUS" "Version 2: Create message $i returns 201"
        local id
        id=$(printf '%s' "$RESP_BODY" | jq -r '.id')
        msg_ids+=("$id")
    done

    # Pagination - first page
    http_request "GET" "/message" "2"
    assert_status "200" "$RESP_STATUS" "Version 2: List first page returns 200"
    local data_count
    data_count=$(printf '%s' "$RESP_BODY" | jq '.data | length')
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ "$data_count" == "10" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_verbose "✓ First page contains 10 messages"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        if [[ $VERBOSE -eq 1 ]]; then
            log_error "✗ First page should contain 10 messages, got $data_count"
        fi
    fi

    local next_id prev_id
    next_id=$(printf '%s' "$RESP_BODY" | jq -r '.next')
    prev_id=$(printf '%s' "$RESP_BODY" | jq -r '.previous')

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ "$next_id" != "null" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_verbose "✓ First page has next pointer"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        if [[ $VERBOSE -eq 1 ]]; then
            log_error "✗ First page should have next pointer"
        fi
    fi

    # Second page
    if [[ "$next_id" != "null" ]]; then
        http_request "GET" "/message?start=${next_id}" "2"
        assert_status "200" "$RESP_STATUS" "Version 2: List second page returns 200"
        local prev_id_page2
        prev_id_page2=$(printf '%s' "$RESP_BODY" | jq -r '.previous')
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        if [[ "$prev_id_page2" != "null" ]]; then
            PASSED_TESTS=$((PASSED_TESTS + 1))
            log_verbose "✓ Second page has previous pointer"
        else
            FAILED_TESTS=$((FAILED_TESTS + 1))
            if [[ $VERBOSE -eq 1 ]]; then
                log_error "✗ Second page should have previous pointer"
            fi
        fi
    fi

    # Pagination after deletion
    log_verbose "Testing pagination after deletion..."
    local mid_id="${msg_ids[5]}"
    http_request "DELETE" "/message/${mid_id}" "2"
    assert_status "200" "$RESP_STATUS" "Version 2: DELETE message returns 200"

    http_request "GET" "/message" "2"
    assert_status "200" "$RESP_STATUS" "Version 2: List after deletion returns 200"

    # DELETE non-existent
    http_request "DELETE" "/message/99999" "2"
    assert_status "404" "$RESP_STATUS" "Version 2: DELETE non-existent message returns 404"

    # PUT non-existent
    http_request "PUT" "/message/99999" "2" '{"author":"Nobody","content":"Nothing"}'
    assert_status "404" "$RESP_STATUS" "Version 2: PUT non-existent message returns 404"

    # PATCH non-existent
    http_request "PATCH" "/message/99999" "2" '{"content":"Nothing"}'
    assert_status "404" "$RESP_STATUS" "Version 2: PATCH non-existent message returns 404"

    # Service-specific result
    local service_tests_passed=$((PASSED_TESTS - initial_passed))
    local service_tests_failed=$((FAILED_TESTS - initial_failed))
    if [[ $service_tests_failed -eq 0 ]]; then
        log_success "$service_name: PASSED ($service_tests_passed/$((service_tests_passed + service_tests_failed)) tests)"
        return 0
    else
        log_error "$service_name: FAILED ($service_tests_passed/$((service_tests_passed + service_tests_failed)) tests passed)"
        return 1
    fi
}

test_service() {
    local service_dir="$1"
    local service_name
    service_name=$(basename "$service_dir")

    SERVICE_PID=""
    local start_result
    start_service "$service_dir" || start_result=$?
    start_result=${start_result:-0}

    if [[ $start_result -eq 2 ]]; then
        log_warn "$service_name: SKIPPED"
        return 2
    elif [[ $start_result -ne 0 ]]; then
        log_error "$service_name: Failed to start"
        return 1
    fi

    local test_result=0
    if ! run_tests "$service_name"; then
        test_result=1
    fi

    stop_service
    return $test_result
}

main() {
    parse_args "$@"

    log_info "Starting service tests..."
    log_info "Target: ${TARGET_SERVICE:-all services}"
    log_info "Verbose: $([[ $VERBOSE -eq 1 ]] && echo "enabled" || echo "disabled")"
    echo

    # Check required tools
    for tool in curl jq pixi; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool '$tool' not found. Please install it first."
            exit 1
        fi
    done

    local services_tested=0
    local services_passed=0
    local services_skipped=0
    local services_failed=0

    local -a service_dirs=()
    if [[ -n "$TARGET_SERVICE" ]]; then
        if [[ -d "${SERVICES_DIR}/${TARGET_SERVICE}" ]]; then
            service_dirs=( "${SERVICES_DIR}/${TARGET_SERVICE}" )
        else
            log_error "Service directory not found: ${SERVICES_DIR}/${TARGET_SERVICE}"
            exit 1
        fi
    else
        while IFS= read -r -d '' dir; do
            service_dirs+=( "$dir" )
        done < <(find "$SERVICES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    fi

    for service_dir in "${service_dirs[@]}"; do
        services_tested=$((services_tested + 1))
        result=0
        test_service "$service_dir" || result=$?
        if [[ $result -eq 0 ]]; then
            services_passed=$((services_passed + 1))
        elif [[ $result -eq 1 ]]; then
            services_failed=$((services_failed + 1))
        elif [[ $result -eq 2 ]]; then
            services_skipped=$((services_skipped + 1))
        fi
        echo
    done

    echo "=================================================="
    log_info "Test Summary"
    echo "=================================================="
    echo "Services tested:  $services_tested"
    echo "Services passed:  $services_passed"
    echo "Services skipped: $services_skipped"
    echo "Services failed:  $services_failed"
    echo
    echo "Total tests:      $TOTAL_TESTS"
    echo "Tests passed:     $PASSED_TESTS"
    echo "Tests failed:     $FAILED_TESTS"
    echo "=================================================="

    if [[ $services_failed -eq 0 ]]; then
        log_success "All tested services passed!"
        exit 0
    else
        log_error "Some services failed!"
        exit 1
    fi
}

cleanup() {
    stop_service
}

trap cleanup EXIT INT TERM

main "$@"

#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_error() { echo -e "${RED}❌ $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_header() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# Configuration
BASE_URL="${1:-http://localhost:${TEST_PORT:-11434}}"
HEALTH_URL="${2:-http://localhost:${PORT_HEALTH:-8080}}"
TIMEOUT=10
REMOTE_TEST="${REMOTE_TEST:-false}"

# Authentication (for Runpod remote endpoints)
AUTH_HEADER=""
if [ -n "$RUNPOD_API_KEY" ]; then
    AUTH_HEADER="-H 'Authorization: Bearer $RUNPOD_API_KEY'"
    print_info "Using authentication (RUNPOD_API_KEY is set)"
fi

if [ "$REMOTE_TEST" = "true" ]; then
    print_warning "Remote serverless test mode: /ping health check will be skipped"
    print_info "RunPod serverless routes external traffic to Ollama on PORT"
fi

echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║   Runpod Ollama Endpoint Test Suite          ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

print_info "Testing API endpoint:    $BASE_URL"
print_info "Testing health endpoint: $HEALTH_URL"
print_info "Timeout: ${TIMEOUT}s per request"
echo ""

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to run tests
run_test() {
    local test_name="$1"
    local method="$2"
    local endpoint="$3"
    local data="$4"
    local expect_stream="${5:-false}"
    local base_url="${6:-$BASE_URL}"

    print_header "Test: $test_name"

    local url="$base_url$endpoint"
    local cmd="curl -s -w '\n%{http_code}' -X $method \"$url\" -m $TIMEOUT"

    # Add auth header if set
    if [ -n "$AUTH_HEADER" ]; then
        cmd="$cmd $AUTH_HEADER"
    fi

    if [ -n "$data" ]; then
        cmd="$cmd -H 'Content-Type: application/json' -d '$data'"
    fi

    print_info "Request: $method $endpoint"
    if [ -n "$data" ]; then
        echo "Data: $data" | head -c 100
        [ ${#data} -gt 100 ] && echo "..." || echo ""
    fi

    # Show full command
    echo "Command: $cmd"

    # Execute request
    local response=$(eval $cmd 2>&1)
    local http_code=$(echo "$response" | tail -n 1)
    local body=$(echo "$response" | sed '$d')

    # Check HTTP status
    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        print_success "HTTP Status: $http_code"

        # Show response (truncated)
        if [ -n "$body" ]; then
            echo "Response:"
            echo "$body" | head -c 200
            [ ${#body} -gt 200 ] && echo "..." || echo ""
        fi

        ((TESTS_PASSED++))
        return 0
    else
        print_error "HTTP Status: $http_code"
        [ -n "$body" ] && echo "Error: $body"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test 1: Health check (only for local testing)
if [ "$REMOTE_TEST" != "true" ]; then
    run_test "Health Check (/ping on PORT_HEALTH)" "GET" "/ping" "" "false" "$HEALTH_URL"
else
    print_header "Test: Health Check (/ping)"
    print_warning "Skipped - /ping only accessible internally on RunPod serverless"
    print_info "RunPod's load balancer checks health internally on PORT_HEALTH"
fi

# Test 2: Reachability check (Ollama - on PORT)
run_test "Reachability Check (HEAD /)" "HEAD" "/" "" "false" "$BASE_URL"

# Test 3: List models
run_test "List Models (GET /api/tags)" "GET" "/api/tags"

# Get model name from response (for subsequent tests)
MODELS_CMD="curl -s \"$BASE_URL/api/tags\" -m $TIMEOUT"
[ -n "$AUTH_HEADER" ] && MODELS_CMD="$MODELS_CMD $AUTH_HEADER"
MODELS_RESPONSE=$(eval $MODELS_CMD 2>/dev/null)
MODEL_NAME=$(echo "$MODELS_RESPONSE" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$MODEL_NAME" ]; then
    print_warning "Could not detect model name from /api/tags"
    print_info "Checking if any GGUF file is specified in environment..."
    MODEL_NAME="test-model"
    print_warning "Using placeholder model name: $MODEL_NAME"
    print_warning "Some tests may fail if model doesn't exist"
fi

print_info "Using model: $MODEL_NAME"

# Test 4: Model info
if [ -n "$MODEL_NAME" ]; then
    run_test "Model Info (POST /api/show)" "POST" "/api/show" \
        "{\"name\":\"$MODEL_NAME\"}"
fi

# Test 5: Generate (non-streaming)
if [ -n "$MODEL_NAME" ]; then
    run_test "Generate Text (POST /api/generate)" "POST" "/api/generate" \
        "{\"model\":\"$MODEL_NAME\",\"prompt\":\"Say 'test'\",\"stream\":false}"
fi

# Test 6: Chat (non-streaming)
if [ -n "$MODEL_NAME" ]; then
    run_test "Chat Completion (POST /api/chat)" "POST" "/api/chat" \
        "{\"model\":\"$MODEL_NAME\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"stream\":false}"
fi

# Test 7: Chat with streaming (verify streaming works)
if [ -n "$MODEL_NAME" ]; then
    print_header "Test: Chat Streaming (POST /api/chat with stream=true)"

    print_info "Request: POST /api/chat (streaming)"
    print_info "Checking for chunked response..."

    local stream_cmd="curl -s -N \"$BASE_URL/api/chat\" -H \"Content-Type: application/json\""
    [ -n "$AUTH_HEADER" ] && stream_cmd="$stream_cmd $AUTH_HEADER"
    stream_cmd="$stream_cmd -d '{\"model\":\"$MODEL_NAME\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}],\"stream\":true}' -m 30"
    local stream_response=$(eval $stream_cmd 2>&1 | head -n 5)

    if [ -n "$stream_response" ]; then
        print_success "Streaming response received"
        echo "First few chunks:"
        echo "$stream_response"
        ((TESTS_PASSED++))
    else
        print_error "No streaming response received"
        ((TESTS_FAILED++))
    fi
fi

# Test 8: Embeddings (optional, model may not support)
if [ -n "$MODEL_NAME" ]; then
    print_header "Test: Embeddings (POST /api/embeddings) [Optional]"

    print_info "Request: POST /api/embeddings"
    print_warning "This may fail if model doesn't support embeddings"

    local embed_cmd="curl -s -w '\n%{http_code}' \"$BASE_URL/api/embeddings\" -H \"Content-Type: application/json\""
    [ -n "$AUTH_HEADER" ] && embed_cmd="$embed_cmd $AUTH_HEADER"
    embed_cmd="$embed_cmd -d '{\"model\":\"$MODEL_NAME\",\"prompt\":\"test\"}' -m $TIMEOUT"
    local embed_response=$(eval $embed_cmd 2>&1)

    local http_code=$(echo "$embed_response" | tail -n 1)

    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        print_success "Embeddings supported (HTTP $http_code)"
        ((TESTS_PASSED++))
    else
        print_warning "Embeddings not supported or failed (HTTP $http_code)"
        # Don't count as failure for optional test
    fi
fi

# Summary
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Test Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "  Total:  $((TESTS_PASSED + TESTS_FAILED))"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    print_success "All tests passed! 🎉"
    echo ""
    print_info "Your endpoint is ready to use with Enchanted!"
    echo ""
    echo "Configure Enchanted with:"
    echo "  Server URL: $BASE_URL"
    echo ""
    exit 0
else
    print_error "Some tests failed"
    echo ""
    print_info "Troubleshooting:"
    echo "  1. Check if container is running: docker ps"
    echo "  2. View logs: docker logs <container-id>"
    echo "  3. Verify Ollama started: curl $BASE_URL/ping"
    echo "  4. Check model loaded: curl $BASE_URL/api/tags"
    echo ""
    exit 1
fi

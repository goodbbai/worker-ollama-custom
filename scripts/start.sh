#!/bin/bash
set -e

echo "============================================"
echo "Starting Runpod Ollama Serverless Handler"
echo "============================================"

# Environment variables inherited from Dockerfile
echo "Model: $CUSTOM_MODEL_NAME"
echo "Ollama Models Path: $OLLAMA_MODELS"
echo "Ollama Port (PORT): ${PORT:-11434}"
echo "Health Port (PORT_HEALTH): ${PORT_HEALTH:-8080}"

# 1. Start Ollama server on PORT (not localhost:11434)
echo ""
echo "[1/5] Starting Ollama server on 0.0.0.0:${PORT}..."
OLLAMA_HOST="0.0.0.0:${PORT}" ollama serve > /tmp/ollama-serve.log 2>&1 &
OLLAMA_PID=$!
echo "  Ollama PID: $OLLAMA_PID"

# Wait for Ollama to be ready
echo "[2/5] Waiting for Ollama server to be ready on port ${PORT}..."
MAX_RETRIES=30
RETRY_COUNT=0
while ! curl -s -f "http://localhost:${PORT}/" > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if ! kill -0 "$OLLAMA_PID" 2>/dev/null; then
        echo "ERROR: Ollama server exited unexpectedly"
        echo "Ollama logs (tail):"
        tail -n 200 /tmp/ollama-serve.log 2>/dev/null || true
        exit 1
    fi
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "ERROR: Ollama server failed to start after $MAX_RETRIES attempts"
        echo "Ollama logs (tail):"
        tail -n 200 /tmp/ollama-serve.log 2>/dev/null || true
        exit 1
    fi
    echo "  Waiting for Ollama... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done
echo "  ✓ Ollama server is ready on port ${PORT}!"

# 2. Verify pre-loaded model exists
echo "[3/5] Verifying pre-loaded model..."
echo "  Model: $CUSTOM_MODEL_NAME"
echo "  Expected location: $OLLAMA_MODELS"

# Check if models directory exists
if [ ! -d "$OLLAMA_MODELS" ]; then
    echo "  ❌ ERROR: Models directory not found at $OLLAMA_MODELS"
    echo "  This likely means the Docker image was not built correctly."
    echo "  Please rebuild the image using: ./scripts/build.sh"
    exit 1
fi

# Check if model blobs and manifests exist
if [ ! -d "$OLLAMA_MODELS/blobs" ] || [ ! -d "$OLLAMA_MODELS/manifests" ]; then
    echo "  ❌ ERROR: Model blobs or manifests directory not found"
    echo "  Expected:"
    echo "    - $OLLAMA_MODELS/blobs/"
    echo "    - $OLLAMA_MODELS/manifests/"
    echo "  Please rebuild the image with pre-processed models."
    exit 1
fi

# Verify model is available in Ollama (using PORT instead of 11434)
if OLLAMA_HOST="http://localhost:${PORT}" ollama list | grep -q "$CUSTOM_MODEL_NAME"; then
    echo "  ✓ Model '$CUSTOM_MODEL_NAME' found and ready"

    # Show model info for debugging
    echo "  Model details:"
    OLLAMA_HOST="http://localhost:${PORT}" ollama list | grep "$CUSTOM_MODEL_NAME" || true
else
    echo "  ❌ ERROR: Model '$CUSTOM_MODEL_NAME' not found in Ollama"
    echo ""
    echo "  Available models:"
    OLLAMA_HOST="http://localhost:${PORT}" ollama list
    echo ""
    echo "  Troubleshooting:"
    echo "  1. Verify model was extracted correctly during build"
    echo "  2. Check extraction cache: ./extracted-models/"
    echo "  3. Rebuild with: ./scripts/build.sh"
    echo "  4. Ensure MODEL_NAME matches the extracted model name"
    exit 1
fi

# 3. Start Health Server on PORT_HEALTH
echo "[4/5] Starting health server on port ${PORT_HEALTH}..."
python3 -u /usr/src/app/health_server.py > /tmp/health-server.log 2>&1 &
HEALTH_PID=$!
echo "  Health server PID: $HEALTH_PID"

# Wait for health server to be ready
echo "  Waiting for health server..."
MAX_HEALTH_RETRIES=10
HEALTH_RETRY_COUNT=0
while ! curl -s -f "http://localhost:${PORT_HEALTH}/ping" > /dev/null 2>&1; do
    HEALTH_RETRY_COUNT=$((HEALTH_RETRY_COUNT + 1))
    if ! kill -0 "$HEALTH_PID" 2>/dev/null; then
        echo "ERROR: Health server exited unexpectedly"
        echo "Health server logs:"
        cat /tmp/health-server.log 2>/dev/null || true
        exit 1
    fi
    if [ $HEALTH_RETRY_COUNT -ge $MAX_HEALTH_RETRIES ]; then
        echo "ERROR: Health server failed to start"
        echo "Health server logs:"
        cat /tmp/health-server.log 2>/dev/null || true
        exit 1
    fi
    sleep 1
done
echo "  ✓ Health server is ready on port ${PORT_HEALTH}!"

# 4. Monitor both processes
echo "[5/5] Both services running!"
echo ""
echo "============================================"
echo "Server Ready!"
echo "============================================"
echo "  Ollama API:    http://0.0.0.0:${PORT} (PID: $OLLAMA_PID)"
echo "  Health Check:  http://0.0.0.0:${PORT_HEALTH} (PID: $HEALTH_PID)"
echo "============================================"

# Keep both processes running and monitor them
while true; do
    # Check if Ollama is still running
    if ! kill -0 "$OLLAMA_PID" 2>/dev/null; then
        echo "ERROR: Ollama process died! Logs:"
        tail -n 100 /tmp/ollama-serve.log
        exit 1
    fi

    # Check if health server is still running
    if ! kill -0 "$HEALTH_PID" 2>/dev/null; then
        echo "ERROR: Health server process died! Logs:"
        tail -n 100 /tmp/health-server.log
        exit 1
    fi

    sleep 10
done

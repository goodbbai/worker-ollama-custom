#!/bin/bash
set -e

# extract-model.sh - Extract GGUF models to Ollama's native blob format
# This script processes GGUF files once and caches the results for faster Docker builds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_error() { echo -e "${RED}❌ ERROR: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Default values
EXTRACTION_CACHE_DIR="${EXTRACTION_CACHE_DIR:-./extracted-models}"
FORCE_EXTRACT=false
MODEL_FILE=""
MODEL_NAME=""
OUTPUT_DIR=""
MODELFILE_TEMPLATE=""

# Usage information
usage() {
    cat << EOF
Usage: $0 --model-file <path> --model-name <name> [options]

Extract GGUF model files to Ollama's native blob format for faster deployment.

Required Arguments:
  --model-file <path>     Path to GGUF model file
  --model-name <name>     Name for the model in Ollama

Optional Arguments:
  --output-dir <path>     Custom output directory (default: auto-calculated from hash)
  --modelfile-template <path>  Custom Modelfile template (default: auto-discover)
  --force                 Force re-extraction even if cache exists
  -h, --help             Show this help message

Environment Variables:
  EXTRACTION_CACHE_DIR    Base cache directory (default: ./extracted-models)

Example:
  $0 --model-file model.gguf --model-name my-model
  $0 --model-file model.gguf --model-name my-model --force

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --model-file)
            MODEL_FILE="$2"
            shift 2
            ;;
        --model-name)
            MODEL_NAME="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --modelfile-template)
            MODELFILE_TEMPLATE="$2"
            shift 2
            ;;
        --force)
            FORCE_EXTRACT=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$MODEL_FILE" ] || [ -z "$MODEL_NAME" ]; then
    print_error "Missing required arguments"
    usage
fi

# Validate model file exists
if [ ! -f "$MODEL_FILE" ]; then
    print_error "Model file not found: $MODEL_FILE"
    exit 1
fi

# Get absolute path
MODEL_FILE=$(cd "$(dirname "$MODEL_FILE")" && pwd)/$(basename "$MODEL_FILE")

# Discover Modelfile template (priority order)
# 1. --modelfile-template <path> (explicit override)
# 2. {model-basename}.Modelfile (per-model template)
# 3. Modelfile.template (default template)
# 4. Auto-generate from script (fallback)
DISCOVERED_TEMPLATE=""
MODEL_BASENAME=$(basename "$MODEL_FILE" .gguf)

if [ -n "$MODELFILE_TEMPLATE" ]; then
    # Explicit override
    if [ ! -f "$MODELFILE_TEMPLATE" ]; then
        print_error "Specified Modelfile template not found: $MODELFILE_TEMPLATE"
        exit 1
    fi
    DISCOVERED_TEMPLATE="$MODELFILE_TEMPLATE"
    print_info "Using explicit Modelfile template: $MODELFILE_TEMPLATE"
elif [ -f "${MODEL_BASENAME}.Modelfile" ]; then
    # Per-model template
    DISCOVERED_TEMPLATE="${MODEL_BASENAME}.Modelfile"
    print_info "Using per-model template: ${MODEL_BASENAME}.Modelfile"
elif [ -f "Modelfile.template" ]; then
    # Default template
    DISCOVERED_TEMPLATE="Modelfile.template"
    print_info "Using default template: Modelfile.template"
else
    # Auto-generate (fallback)
    print_info "No Modelfile template found, will auto-generate with default parameters"
fi

# Calculate GGUF hash for cache key (first 1MB + last 1MB for speed)
# This is much faster than hashing the entire file while still being unique
print_info "Calculating model fingerprint..."
GGUF_HASH=$( (head -c 1048576 "$MODEL_FILE"; tail -c 1048576 "$MODEL_FILE") | shasum -a 256 | cut -d' ' -f1)
print_info "Fingerprint: ${GGUF_HASH:0:16}..."

# Determine output directory
if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$EXTRACTION_CACHE_DIR/$GGUF_HASH"
fi

MODELS_DIR="$OUTPUT_DIR/models"
METADATA_FILE="$OUTPUT_DIR/metadata.json"

# Check if extraction already exists
if [ -d "$MODELS_DIR" ] && [ -f "$METADATA_FILE" ] && [ "$FORCE_EXTRACT" = false ]; then
    print_success "Extraction already exists at: $OUTPUT_DIR"
    print_info "Use --force to re-extract"

    # Display metadata
    if command -v jq &> /dev/null; then
        echo ""
        print_info "Extraction info:"
        jq -r '"  Model: \(.model_name)\n  Extracted: \(.extracted_at)\n  Ollama: \(.ollama_version)\n  Modelfile: \(.modelfile_source)"' "$METADATA_FILE"
    fi

    echo "$MODELS_DIR"
    exit 0
fi

# Check jq is available (required for metadata generation)
if ! command -v jq &> /dev/null; then
    print_error "jq is not installed or not in PATH"
    echo "Install jq:"
    echo "  macOS: brew install jq"
    echo "  Ubuntu/Debian: apt-get install jq"
    echo "  Fedora: dnf install jq"
    exit 1
fi

# Check Docker is available
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed or not in PATH"
    exit 1
fi

# Check Docker daemon is running
if ! docker info &> /dev/null; then
    print_error "Docker daemon is not running"
    exit 1
fi

# Check available disk space
print_info "Checking disk space..."
MODEL_SIZE=$(stat -f%z "$MODEL_FILE" 2>/dev/null || stat -c%s "$MODEL_FILE")
REQUIRED_SPACE=$((MODEL_SIZE * 3))  # Need 3x: original + extraction + safety margin

# Get available space (cross-platform)
if [[ "$OSTYPE" == "darwin"* ]]; then
    AVAILABLE_SPACE=$(df -k "$(dirname "$OUTPUT_DIR")" | tail -1 | awk '{print $4}')
    AVAILABLE_SPACE=$((AVAILABLE_SPACE * 1024))
else
    AVAILABLE_SPACE=$(df -B1 --output=avail "$(dirname "$OUTPUT_DIR")" | tail -1)
fi

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    print_error "Insufficient disk space"
    echo "  Available: $(numfmt --to=iec-i --suffix=B $AVAILABLE_SPACE 2>/dev/null || echo "$AVAILABLE_SPACE bytes")"
    echo "  Required: $(numfmt --to=iec-i --suffix=B $REQUIRED_SPACE 2>/dev/null || echo "$REQUIRED_SPACE bytes")"
    exit 1
fi

# Platform detection
CURRENT_PLATFORM=$(uname -m)
if [[ "$CURRENT_PLATFORM" == "arm64" ]] || [[ "$CURRENT_PLATFORM" == "aarch64" ]]; then
    print_warning "Running on ARM64 ($CURRENT_PLATFORM)"
    print_warning "Extraction will use linux/amd64 platform (may be slower due to emulation)"
fi

# Create temporary extraction directory (atomic write)
TEMP_EXTRACTION="$OUTPUT_DIR.tmp.$$"
mkdir -p "$TEMP_EXTRACTION"

# Cleanup function
cleanup() {
    local exit_code=$?
    print_info "Cleaning up..."

    # Remove container if exists
    docker rm -f model-extractor-$$ 2>/dev/null || true

    # Remove temp directory on failure
    if [ $exit_code -ne 0 ]; then
        rm -rf "$TEMP_EXTRACTION"
        print_error "Extraction failed! Temporary files removed."
    fi

    exit $exit_code
}

trap cleanup EXIT INT TERM

# Start extraction
echo ""
print_info "Starting model extraction..."
print_info "  Model file: $MODEL_FILE"
print_info "  Model name: $MODEL_NAME"
print_info "  Output: $OUTPUT_DIR"
echo ""

# Create container with ollama
print_info "[1/7] Creating temporary Ollama container..."
CONTAINER_NAME="model-extractor-$$"

docker run \
    --platform linux/amd64 \
    -d \
    --name "$CONTAINER_NAME" \
    --entrypoint /bin/sh \
    ollama/ollama:latest \
    -c "while true; do sleep 3600; done"

print_success "Container created: $CONTAINER_NAME"

# Ensure container is actually running (ollama/ollama uses an ENTRYPOINT, so the
# command above must override it via --entrypoint or the container will exit).
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo "false")" != "true" ]; then
    print_error "Temporary container is not running (it likely exited immediately)"
    docker logs "$CONTAINER_NAME" 2>/dev/null || true
    exit 1
fi

# Copy GGUF file into container
print_info "[2/7] Copying GGUF file to container..."
docker cp "$MODEL_FILE" "$CONTAINER_NAME:/tmp/$(basename "$MODEL_FILE")"
print_success "GGUF copied"

# Generate Modelfile from template or auto-generate
print_info "[3/7] Generating Modelfile..."

if [ -n "$DISCOVERED_TEMPLATE" ]; then
    # Use template and replace placeholders
    CONTAINER_GGUF_PATH="/tmp/$(basename "$MODEL_FILE")"

    MODELFILE_CONTENT=$(cat "$DISCOVERED_TEMPLATE" | \
        sed "s|{{GGUF_PATH}}|$CONTAINER_GGUF_PATH|g" | \
        sed "s|{{MODEL_NAME}}|$MODEL_NAME|g")

    print_info "  Template: $DISCOVERED_TEMPLATE"
    print_info "  Placeholders replaced:"
    print_info "    {{GGUF_PATH}} → $CONTAINER_GGUF_PATH"
    print_info "    {{MODEL_NAME}} → $MODEL_NAME"
else
    # Auto-generate with default parameters (fallback)
    MODELFILE_CONTENT="FROM /tmp/$(basename "$MODEL_FILE")

# Generation parameters (defaults)
PARAMETER temperature 0.9
PARAMETER top_p 0.95
PARAMETER top_k 40
PARAMETER min_p 0.025
PARAMETER num_predict 512
PARAMETER num_ctx 16384
"
    print_info "  Using auto-generated Modelfile with default parameters"
fi

if ! echo "$MODELFILE_CONTENT" | docker exec -i "$CONTAINER_NAME" tee /tmp/Modelfile > /dev/null; then
    print_error "Failed to write Modelfile to container"
    docker logs "$CONTAINER_NAME" 2>/dev/null || true
    exit 1
fi
print_success "Modelfile generated"

# Start Ollama server in container
print_info "[4/7] Starting Ollama server..."
docker exec -d "$CONTAINER_NAME" sh -lc "ollama serve > /tmp/ollama-serve.log 2>&1"
sleep 2

# Wait for Ollama to be ready
MAX_RETRIES=30
RETRY_COUNT=0
while ! docker exec "$CONTAINER_NAME" ollama list > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        print_error "Ollama server failed to start after $MAX_RETRIES attempts"
        print_info "Ollama server logs (tail):"
        docker exec "$CONTAINER_NAME" sh -lc "tail -n 200 /tmp/ollama-serve.log 2>/dev/null || echo '  (no /tmp/ollama-serve.log found)'" || true
        exit 1
    fi
    echo "  Waiting for Ollama... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done
print_success "Ollama server ready"

# Create model from GGUF
print_info "[5/7] Creating model (this may take 2-5 minutes)..."
if docker exec "$CONTAINER_NAME" ollama create "$MODEL_NAME" -f /tmp/Modelfile; then
    print_success "Model created successfully"
else
    print_error "Failed to create model"
    docker logs "$CONTAINER_NAME"
    exit 1
fi

# Verify model exists
print_info "[6/7] Verifying model..."
if docker exec "$CONTAINER_NAME" ollama list | grep -q "$MODEL_NAME"; then
    print_success "Model verified in Ollama"
else
    print_error "Model not found in Ollama after creation"
    docker exec "$CONTAINER_NAME" ollama list
    exit 1
fi

# Extract models directory
print_info "[7/7] Extracting model blobs..."
docker cp "$CONTAINER_NAME:/root/.ollama/models/." "$TEMP_EXTRACTION/models/"

# Verify extraction
if [ ! -d "$TEMP_EXTRACTION/models/blobs" ] || [ ! -d "$TEMP_EXTRACTION/models/manifests" ]; then
    print_error "Extraction incomplete - missing blobs or manifests"
    exit 1
fi

BLOB_COUNT=$(find "$TEMP_EXTRACTION/models/blobs" -type f | wc -l)
print_success "Extracted $BLOB_COUNT blob files"

# Get Ollama version
OLLAMA_VERSION=$(docker exec "$CONTAINER_NAME" ollama --version 2>/dev/null | head -1 || echo "unknown")

# Create metadata
print_info "Creating metadata..."
EXTRACTION_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Determine modelfile source for metadata
if [ -n "$DISCOVERED_TEMPLATE" ]; then
    MODELFILE_SOURCE="$DISCOVERED_TEMPLATE"
else
    MODELFILE_SOURCE="auto-generated"
fi

# Create metadata with properly escaped Modelfile content using jq
jq -n \
    --arg model_name "$MODEL_NAME" \
    --arg gguf_file "$MODEL_FILE" \
    --arg gguf_sha256 "$GGUF_HASH" \
    --arg extracted_at "$EXTRACTION_DATE" \
    --arg ollama_version "$OLLAMA_VERSION" \
    --arg modelfile_source "$MODELFILE_SOURCE" \
    --arg modelfile_content "$MODELFILE_CONTENT" \
    '{
        model_name: $model_name,
        gguf_file: $gguf_file,
        gguf_sha256: $gguf_sha256,
        extracted_at: $extracted_at,
        ollama_version: $ollama_version,
        modelfile_source: $modelfile_source,
        modelfile_content: $modelfile_content
    }' > "$TEMP_EXTRACTION/metadata.json"

print_success "Metadata created"

# Atomic move to final location
print_info "Finalizing extraction..."
rm -rf "$OUTPUT_DIR"
mv "$TEMP_EXTRACTION" "$OUTPUT_DIR"

echo ""
print_success "Extraction complete!"
print_info "Cache location: $OUTPUT_DIR"
print_info "Models directory: $MODELS_DIR"

# Display cache info
CACHE_SIZE=$(du -sh "$OUTPUT_DIR" | cut -f1)
print_info "Cache size: $CACHE_SIZE"

echo ""
print_info "This extracted model will be used for Docker builds."
print_info "To clean cache: rm -rf $OUTPUT_DIR"
echo ""

# Output the models directory path (for scripting)
echo "$MODELS_DIR"

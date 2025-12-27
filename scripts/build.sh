#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_error() { echo -e "${RED}❌ ERROR: $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║   Runpod Ollama Docker Build Script          ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Default values
DEFAULT_REGISTRY="your-username"
DEFAULT_IMAGE_NAME="runpod-ollama"
DEFAULT_TAG="latest"

# Function to list GGUF files
list_gguf_files() {
    local gguf_files=(*.gguf)
    if [ -e "${gguf_files[0]}" ]; then
        echo -e "${GREEN}Found GGUF files:${NC}"
        local i=1
        for file in "${gguf_files[@]}"; do
            local size=$(du -h "$file" | cut -f1)
            echo "  [$i] $file ($size)"
            ((i++))
        done
        return 0
    else
        return 1
    fi
}

# Function to select GGUF file
select_gguf_file() {
    local gguf_files=(*.gguf)

    if [ ${#gguf_files[@]} -eq 1 ]; then
        echo "${gguf_files[0]}"
        return 0
    fi

    while true; do
        read -p "Select GGUF file number [1-${#gguf_files[@]}]: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#gguf_files[@]}" ]; then
            echo "${gguf_files[$((selection-1))]}"
            return 0
        else
            print_error "Invalid selection. Please enter a number between 1 and ${#gguf_files[@]}"
        fi
    done
}

# Step 1: Check for GGUF model files
echo -e "\n${BLUE}[Step 1/7] Checking for GGUF model files...${NC}"

if ! list_gguf_files; then
    print_error "No GGUF model files found in current directory!"
    echo ""
    print_info "Please download a GGUF model file first. Examples:"
    echo ""
    echo "  # GLM-4 Vision (8GB)"
    echo "  wget https://huggingface.co/unsloth/GLM-4.6V-Flash-GGUF/resolve/main/GLM-4.6V-Flash.Q5_K_M.gguf"
    echo ""
    echo "  # Llama 3.2 Vision (8GB)"
    echo "  wget https://huggingface.co/unsloth/Llama-3.2-11B-Vision-Instruct-GGUF/resolve/main/Llama-3.2-11B-Vision-Instruct-Q4_K_M.gguf"
    echo ""
    echo "  # Qwen2-VL (4GB)"
    echo "  wget https://huggingface.co/unsloth/Qwen2-VL-7B-Instruct-GGUF/resolve/main/Qwen2-VL-7B-Instruct-Q4_K_M.gguf"
    echo ""
    exit 1
fi

# Select GGUF file
MODEL_FILE=$(select_gguf_file)
print_success "Selected model: $MODEL_FILE"

# Step 2: Configure model name
echo -e "\n${BLUE}[Step 2/7] Configure model name${NC}"

# Extract base name from file (remove .gguf extension)
DEFAULT_MODEL_NAME=$(basename "$MODEL_FILE" .gguf)

read -p "Enter model name [$DEFAULT_MODEL_NAME]: " MODEL_NAME
MODEL_NAME=${MODEL_NAME:-$DEFAULT_MODEL_NAME}
print_success "Model name: $MODEL_NAME"

# Step 2.5: Extract model to native Ollama format
echo -e "\n${BLUE}[Step 2.5/7] Extract model to native Ollama format${NC}"

# Check if extraction already exists
GGUF_HASH=$(shasum -a 256 "$MODEL_FILE" | cut -d' ' -f1)
EXTRACTION_CACHE_DIR="${EXTRACTION_CACHE_DIR:-./extracted-models}"
EXTRACTION_PATH="$EXTRACTION_CACHE_DIR/$GGUF_HASH"

if [ -d "$EXTRACTION_PATH/models" ]; then
    print_success "Found cached extraction at: $EXTRACTION_PATH"

    # Show extraction date
    if [ -f "$EXTRACTION_PATH/metadata.json" ]; then
        if command -v jq &> /dev/null; then
            EXTRACTED_DATE=$(jq -r '.extracted_at' "$EXTRACTION_PATH/metadata.json")
            print_info "Extracted: $EXTRACTED_DATE"
        fi
    fi

    read -p "Use cached extraction? [Y/n]: " USE_CACHE
    USE_CACHE=${USE_CACHE:-Y}

    if [[ "$USE_CACHE" =~ ^[Nn]$ ]]; then
        print_info "Re-extracting model..."
        FORCE_EXTRACT="--force"
    else
        print_success "Using cached extraction"
        FORCE_EXTRACT=""
    fi
else
    print_info "No cached extraction found, extracting model..."
    print_info "This may take 2-5 minutes depending on model size..."
    FORCE_EXTRACT=""
fi

# Call extraction script if needed
if [ -n "$FORCE_EXTRACT" ] || [ ! -d "$EXTRACTION_PATH/models" ]; then
    if ./scripts/extract-model.sh \
        --model-file "$MODEL_FILE" \
        --model-name "$MODEL_NAME" \
        --output-dir "$EXTRACTION_PATH" \
        $FORCE_EXTRACT; then
        print_success "Model extracted successfully!"
        print_info "Cached at: $EXTRACTION_PATH"
    else
        print_error "Model extraction failed!"
        exit 1
    fi
fi

# Store extraction path for Docker build
EXTRACTED_MODELS_PATH="$EXTRACTION_PATH/models"
print_success "Extracted models ready: $EXTRACTED_MODELS_PATH"

# Step 3: Configure Docker registry
echo -e "\n${BLUE}[Step 3/7] Configure Docker registry${NC}"

echo "Enter your container registry:"
echo "  Examples:"
echo "    - Docker Hub: username"
echo "    - GitHub: ghcr.io/username"
echo "    - Google: gcr.io/project-id"
echo ""

read -p "Registry [$DEFAULT_REGISTRY]: " REGISTRY
REGISTRY=${REGISTRY:-$DEFAULT_REGISTRY}

read -p "Image name [$DEFAULT_IMAGE_NAME]: " IMAGE_NAME
IMAGE_NAME=${IMAGE_NAME:-$DEFAULT_IMAGE_NAME}

read -p "Tag(s) - comma-separated [$DEFAULT_TAG]: " TAG_INPUT
TAG_INPUT=${TAG_INPUT:-$DEFAULT_TAG}

# Parse comma-separated tags into array
IFS=',' read -ra TAG_ARRAY <<< "$TAG_INPUT"

# Trim whitespace and validate
TAGS=()
for tag in "${TAG_ARRAY[@]}"; do
    tag=$(echo "$tag" | xargs)  # trim whitespace
    if [ -n "$tag" ]; then
        TAGS+=("$tag")
    fi
done

# Ensure at least one tag
if [ ${#TAGS[@]} -eq 0 ]; then
    TAGS=("$DEFAULT_TAG")
fi

# Build full image names for all tags
FULL_IMAGES=()
for tag in "${TAGS[@]}"; do
    FULL_IMAGES+=("$REGISTRY/$IMAGE_NAME:$tag")
done

# Display all tags
if [ ${#FULL_IMAGES[@]} -eq 1 ]; then
    print_success "Full image name: ${FULL_IMAGES[0]}"
else
    print_success "Full image names (${#FULL_IMAGES[@]} tags):"
    for img in "${FULL_IMAGES[@]}"; do
        echo "  - $img"
    done
fi

# Step 4: Confirm build configuration
echo -e "\n${BLUE}[Step 4/7] Build Configuration Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Model File:    $MODEL_FILE"
echo "  Model Name:    $MODEL_NAME"
if [ ${#FULL_IMAGES[@]} -eq 1 ]; then
    echo "  Docker Image:  ${FULL_IMAGES[0]}"
else
    echo "  Docker Images:"
    for img in "${FULL_IMAGES[@]}"; do
        echo "    - $img"
    done
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Proceed with build? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_warning "Build cancelled by user"
    exit 0
fi

# Step 5: Build Docker image
echo -e "\n${BLUE}[Step 5/7] Building Docker image...${NC}"
print_info "Building for linux/amd64 platform (required for Runpod Serverless)"
print_info "This may take 5-15 minutes depending on model size..."
if [[ "$(uname -m)" == "arm64" ]]; then
    print_warning "Detected ARM64 architecture (Apple Silicon)"
    print_warning "Build will be slower due to emulation for linux/amd64"
fi

# Calculate expected image size
MODEL_SIZE=$(du -h "$MODEL_FILE" | cut -f1)
print_info "Model size: $MODEL_SIZE"
print_info "Expected image size: ~$MODEL_SIZE + 5GB (base image + dependencies)"

# Build command (run from project root)
# IMPORTANT: --platform linux/amd64 is required for Runpod Serverless

# Build -t flags for all tags
TAG_FLAGS=""
for img in "${FULL_IMAGES[@]}"; do
    TAG_FLAGS="$TAG_FLAGS -t \"$img\""
done

BUILD_CMD="docker build \
  --platform linux/amd64 \
  --build-arg MODEL_NAME=\"$MODEL_NAME\" \
  --build-arg EXTRACTED_MODELS_PATH=\"$EXTRACTED_MODELS_PATH\" \
  --build-arg PORT=\"${PORT:-80}\" \
  --build-arg PORT_HEALTH=\"${PORT_HEALTH:-8080}\" \
  -f docker/Dockerfile \
  $TAG_FLAGS \
  ."

echo ""
print_info "Build command:"
echo "  $BUILD_CMD"
echo ""

# Execute build
if eval $BUILD_CMD; then
    print_success "Docker image built successfully!"

    # Show image details
    echo ""
    print_info "Image details:"
    docker images "${FULL_IMAGES[0]}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

    if [ ${#FULL_IMAGES[@]} -gt 1 ]; then
        print_success "All ${#FULL_IMAGES[@]} tags created successfully:"
        for img in "${FULL_IMAGES[@]}"; do
            echo "  ✓ $img"
        done
    fi
else
    print_error "Docker build failed!"
    exit 1
fi

# Step 6: Push to registry (optional)
echo -e "\n${BLUE}[Step 6/7] Push to registry (optional)${NC}"

read -p "Push image(s) to $REGISTRY? [y/N]: " PUSH_CONFIRM
PUSH_CONFIRM=${PUSH_CONFIRM:-N}

if [[ "$PUSH_CONFIRM" =~ ^[Yy]$ ]]; then
    print_info "Checking Docker login status..."

    # Check if logged in (try to get auth)
    if docker info >/dev/null 2>&1; then
        if [ ${#FULL_IMAGES[@]} -gt 1 ]; then
            print_info "Pushing ${#FULL_IMAGES[@]} tags to registry..."
            echo ""
        else
            print_info "Pushing image to registry..."
        fi

        PUSH_SUCCESS=0
        PUSH_FAILED=()

        for i in "${!FULL_IMAGES[@]}"; do
            full_image="${FULL_IMAGES[$i]}"

            if [ ${#FULL_IMAGES[@]} -gt 1 ]; then
                print_info "[$((i+1))/${#FULL_IMAGES[@]}] Pushing $full_image..."
            fi

            if docker push "$full_image"; then
                ((PUSH_SUCCESS++))
            else
                PUSH_FAILED+=("$full_image")
            fi
        done

        echo ""
        # Summary
        if [ ${#PUSH_FAILED[@]} -eq 0 ]; then
            if [ ${#FULL_IMAGES[@]} -eq 1 ]; then
                print_success "Image pushed successfully!"
            else
                print_success "All $PUSH_SUCCESS image(s) pushed successfully!"
            fi
            echo ""
            print_info "Image(s) now available at:"
            for img in "${FULL_IMAGES[@]}"; do
                echo "  - $img"
            done
        else
            print_warning "Pushed $PUSH_SUCCESS/${#FULL_IMAGES[@]} successfully"
            print_error "Failed to push: ${PUSH_FAILED[*]}"
            echo ""
            echo "You may need to login:"
            echo ""
            echo "  # Docker Hub"
            echo "  docker login"
            echo ""
            echo "  # GitHub Container Registry"
            echo "  echo \$GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin"
            echo ""
            echo "  # Google Container Registry"
            echo "  gcloud auth configure-docker"
            echo ""
            exit 1
        fi
    else
        print_error "Docker is not running or not properly configured"
        exit 1
    fi
else
    print_info "Skipping push. You can push later with:"
    for img in "${FULL_IMAGES[@]}"; do
        echo "  docker push $img"
    done
fi

# Final summary
echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║   Build Complete! 🎉                          ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo "Next steps:"
echo ""
echo "1. Test locally (optional):"
echo "   docker run -p \${TEST_PORT:-8080}:80 ${FULL_IMAGES[0]}"
echo "   curl http://localhost:\${TEST_PORT:-8080}/ping"
echo ""
if [ ${#FULL_IMAGES[@]} -gt 1 ]; then
    echo "   Note: You can use any of the ${#FULL_IMAGES[@]} built tags:"
    for img in "${FULL_IMAGES[@]}"; do
        echo "     - $img"
    done
    echo ""
fi
echo "2. Push to registry (if not done):"
for img in "${FULL_IMAGES[@]}"; do
    echo "   docker push $img"
done
echo ""
echo "3. Deploy to Runpod:"
echo "   - Go to https://www.runpod.io/console/serverless"
echo "   - Click '+ New Endpoint'"
echo "   - Choose 'Load Balancer' (NOT Queue!)"
echo "   - Docker Image: ${FULL_IMAGES[0]}"
if [ ${#FULL_IMAGES[@]} -gt 1 ]; then
    echo "     (or any of the other ${#FULL_IMAGES[@]} tags)"
fi
echo "   - Container Disk: $MODEL_SIZE + 10GB"
echo "   - GPU: Select based on model requirements"
echo ""
echo "4. Configure Enchanted:"
echo "   - URL: https://ENDPOINT_ID.api.runpod.ai"
echo "   - Bearer Token: Your Runpod API key"
echo "Cache management:"
echo "  View cached models: ls -lh ./extracted-models/"
echo "  Clean all cache: rm -rf ./extracted-models/"
echo "  Clean this model: rm -rf $EXTRACTION_PATH"
echo ""
print_success "For detailed deployment instructions, see docs/DEPLOYMENT.md"
echo ""

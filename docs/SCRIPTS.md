# Build & Test Scripts

Automation scripts and Makefile commands to simplify development and deployment.

**Recommended Usage:** Use `make` commands for common tasks. Scripts are available for advanced use cases or when you need more control.

## Quick Reference

```bash
# Most common commands (via Makefile)
make build MODEL_FILE=model.gguf    # Build Docker image
make run                             # Run locally
make test                           # Test endpoints
make push                           # Push to registry

# See "Makefile Targets" section below for complete list
```

## Available Scripts

### 🔨 build.sh - Interactive Build Script

**Purpose:** Guides you through building the Docker image with an interactive wizard.

**Features:**
- Auto-detects GGUF files in directory
- Prompts for model name and registry
- Shows build summary before executing
- Displays next steps after completion
- Includes helpful examples for model downloads

**Usage:**
```bash
./build.sh
```

**Interactive prompts:**
1. Select GGUF model file (if multiple found)
2. Enter model name (defaults to filename)
3. Extract model to Ollama's native format (with caching)
4. Configure Docker registry (Docker Hub, GitHub, etc.)
5. Confirm build configuration
6. Choose whether to push to registry

**Example session:**
```
╔═══════════════════════════════════════════════╗
║   Runpod Ollama Docker Build Script          ║
╚═══════════════════════════════════════════════╝

[Step 1/7] Checking for GGUF model files...
Found GGUF files:
  [1] GLM-4.6V-Flash.Q5_K_M.gguf (8.2G)

Select GGUF file number [1]: 1
✅ Selected model: GLM-4.6V-Flash.Q5_K_M.gguf

[Step 2/7] Configure model name
Enter model name [GLM-4.6V-Flash.Q5_K_M]: GLM-4-Vision

[Step 2.5/7] Extract model to native Ollama format
✅ Found cached extraction at: ./extracted-models/abc123...
Use cached extraction? [Y/n]: y
✅ Using cached extraction

[Step 3/7] Configure Docker registry
Registry [your-username]: myusername
Image name [runpod-ollama]:
Tag [latest]:

✅ Full image name: myusername/runpod-ollama:latest

[Step 4/7] Build Configuration Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Model File:    GLM-4.6V-Flash.Q5_K_M.gguf
  Model Name:    GLM-4-Vision
  Docker Image:  myusername/runpod-ollama:latest
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Proceed with build? [Y/n]: y
```

**Key Features:**
- **Smart Caching:** Models are extracted once and cached at `./extracted-models/`
- **Fast Rebuilds:** Subsequent builds reuse cached extractions (saves 2-5 minutes)
- **Platform Detection:** Warns when building on ARM64 (Apple Silicon) due to emulation

### ⚙️ extract-model.sh - Model Extraction Script

**Purpose:** Extracts GGUF models to Ollama's native blob format for faster container startup.

**Features:**
- Converts GGUF files to Ollama's internal format (blobs + manifests)
- Caches extracted models by hash for reuse across builds
- Stores complete Modelfile content in metadata for audit trail
- Atomic cache writes (prevents corruption from interruptions)
- Cross-platform support (macOS, Linux)
- Comprehensive error handling

**Requirements:**
- Docker (running daemon)
- `jq` command-line JSON processor
  - macOS: `brew install jq`
  - Ubuntu/Debian: `apt-get install jq`
  - Fedora: `dnf install jq`

**Usage:**
```bash
# Basic usage
./scripts/extract-model.sh \
  --model-file model.gguf \
  --model-name my-model

# Force re-extraction (ignore cache)
./scripts/extract-model.sh \
  --model-file model.gguf \
  --model-name my-model \
  --force

# Custom output directory
./scripts/extract-model.sh \
  --model-file model.gguf \
  --model-name my-model \
  --output-dir /custom/path

# Use custom Modelfile template
./scripts/extract-model.sh \
  --model-file model.gguf \
  --model-name my-model \
  --modelfile-template path/to/custom.Modelfile

# Show help
./scripts/extract-model.sh --help
```

**Modelfile Templates:**

The script supports customizable Modelfile templates for fine-tuning model behavior, chat formats, and parameters.

**Template Discovery (priority order):**
1. `--modelfile-template <path>` - Explicit override
2. `{model-basename}.Modelfile` - Per-model template (e.g., `llama-3.Modelfile` for `llama-3.gguf`)
3. `Modelfile.template` - Default template in project root
4. Auto-generate - Fallback with default parameters

**Template Placeholders:**
- `{{GGUF_PATH}}` - Replaced with container path to GGUF file (required in `FROM` instruction)
- `{{MODEL_NAME}}` - Replaced with the model name specified via `--model-name`

**Example Template (Modelfile.template):**
```modelfile
FROM {{GGUF_PATH}}

# Generation parameters
PARAMETER temperature 0.9
PARAMETER top_p 0.95
PARAMETER top_k 40
PARAMETER num_ctx 16384

# Custom chat template for Llama 3 format
TEMPLATE """{{ if .System }}<|start_header_id|>system<|end_header_id|>

{{ .System }}<|eot_id|>{{ end }}{{ if .Prompt }}<|start_header_id|>user<|end_header_id|>

{{ .Prompt }}<|eot_id|>{{ end }}<|start_header_id|>assistant<|end_header_id|>

{{ .Response }}<|eot_id|>
"""

SYSTEM """You are a helpful AI assistant."""
```

**Per-Model Templates:**
Create model-specific templates for different chat formats:
```bash
# For llama-3-8b.gguf, create llama-3-8b.Modelfile
# For mistral-7b.gguf, create mistral-7b.Modelfile

./scripts/extract-model.sh \
  --model-file llama-3-8b.gguf \
  --model-name llama3
# Automatically uses llama-3-8b.Modelfile if it exists
```

**Template Examples:**
See `examples/modelfiles/` for ready-to-use templates:
- `llama3-chat.Modelfile` - Llama 3 chat format
- `chatml-format.Modelfile` - ChatML format (Mistral, Qwen, Yi)
- `code-assistant.Modelfile` - Code-focused assistant
- `README.md` - Complete template guide

**Benefits:**
- **Custom Chat Formats:** Define TEMPLATE instructions for model-specific formats
- **Parameter Tuning:** Adjust temperature, context size, etc. per model
- **System Prompts:** Customize model behavior with SYSTEM instructions
- **Multi-Model Support:** Different templates for different models
- **Reusability:** Share templates across projects

**How it works:**
1. Calculates SHA256 hash of GGUF file (for cache key)
2. Checks if extraction exists in cache
3. If not cached or `--force`:
   - Spins up temporary `ollama/ollama:latest` container
   - Copies GGUF file into container
   - Generates Modelfile with model parameters
   - Runs `ollama create` to extract model
   - Copies `/root/.ollama/models/` to cache
   - Saves metadata (model name, hash, date, ollama version)
   - Cleans up temporary container
4. Returns path to extracted models

**Cache Structure:**
```
./extracted-models/
├── abc123def456.../          # SHA256 hash of GGUF
│   ├── models/               # Extracted ollama models
│   │   ├── blobs/           # Model weight blobs & parameters
│   │   │   ├── sha256-xxx... # Model weights
│   │   │   ├── sha256-yyy... # Model parameters (JSON)
│   │   │   └── ...
│   │   └── manifests/       # Model manifest files
│   │       └── registry.ollama.ai/...
│   └── metadata.json         # Extraction info (NOT parameters)
└── xyz789abc012.../
    ├── models/
    └── metadata.json
```

**metadata.json structure:**
```json
{
  "model_name": "my-model",
  "gguf_file": "/path/to/model.gguf",
  "gguf_sha256": "abc123...",
  "extracted_at": "2025-12-26T05:00:23Z",
  "ollama_version": "ollama version is 0.13.5",
  "modelfile_source": "model.Modelfile",
  "modelfile_content": "FROM /tmp/model.gguf\n\nPARAMETER temperature 0.9\nPARAMETER top_p 0.95\n..."
}
```

**metadata.json fields:**
- `model_name` - Name used during `ollama create`
- `gguf_file` - Original GGUF file path
- `gguf_sha256` - Hash used for cache directory name
- `extracted_at` - ISO 8601 timestamp
- `ollama_version` - Ollama version used for extraction
- `modelfile_source` - Which template was used (`*.Modelfile`, `Modelfile.template`, or `auto-generated`)
- `modelfile_content` - **Complete Modelfile content** used for extraction (audit trail)

**Note:** The `modelfile_content` is the complete, unmodified Modelfile (with placeholders already replaced) that was used during `ollama create`. Model parameters are stored in both the metadata (for reference) and in the blobs (source of truth used by Ollama).

**Benefits:**
- **Faster Cold Starts:** Pre-processed models start in 5-15s (vs 60-90s with runtime creation)
- **Build Efficiency:** Reuse extractions across multiple builds
- **Reliability:** No runtime model creation failures
- **Debugging:** Easy to inspect cached models and metadata

**Environment Variables:**
- `EXTRACTION_CACHE_DIR`: Override cache location (default: `./extracted-models`)

### 🧪 test.sh - Endpoint Test Suite

**Purpose:** Comprehensive testing of Ollama API endpoints.

**Features:**
- Tests all major endpoints (health, models, chat, generate, etc.)
- Streaming verification
- Clear pass/fail reporting
- Colored output for easy reading
- Works with local or remote endpoints

**Usage:**
```bash
# Test local container (uses TEST_PORT env var, defaults to 11434)
make test

# Or use script directly
./scripts/test.sh http://localhost:${TEST_PORT:-11434}

# Test Runpod deployment
make test-remote ENDPOINT_ID=your-endpoint-id RUNPOD_API_KEY=your-api-key
```

**Tests performed:**
1. Health check (`GET /ping`)
2. Reachability (`HEAD /`)
3. List models (`GET /api/tags`)
4. Model info (`POST /api/show`)
5. Generate text (`POST /api/generate`)
6. Chat completion (`POST /api/chat`)
7. Chat streaming (verifies chunked responses)
8. Embeddings (optional)

**Example output:**
```
╔═══════════════════════════════════════════════╗
║   Runpod Ollama Endpoint Test Suite          ║
╚═══════════════════════════════════════════════╝

ℹ️  Testing endpoint: http://localhost:8080
ℹ️  Timeout: 10s per request

━━━ Test: Health Check (/ping) ━━━
ℹ️  Request: GET /ping
✅ HTTP Status: 200
Response:
{"status":"healthy","ollama":"reachable"}

━━━ Test: List Models (GET /api/tags) ━━━
ℹ️  Request: GET /api/tags
✅ HTTP Status: 200
Response:
{"models":[{"name":"GLM-4-Vision","modified_at":"2024-12-19T...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Test Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Passed: 8
  Failed: 0
  Total:  8

✅ All tests passed! 🎉
```

## Makefile Targets

**Purpose:** Convenient commands for common Docker operations.

**Available targets:**

### Build Commands
```bash
make extract MODEL_FILE=model.gguf  # Extract model to cache (optional)
make build MODEL_FILE=model.gguf    # Extract + build Docker image
make build-interactive              # Run build.sh script
make push                          # Push to registry
```

### Run Commands
```bash
make run                          # Run container locally (TEST_PORT, default 11434)
make stop                        # Stop container
make logs                        # View container logs
make shell                       # Open shell in container
```

### Test Commands
```bash
make test                              # Test local container
make test-remote ENDPOINT_ID=xxx       # Test remote endpoint
```

### Utility Commands
```bash
make verify                      # Verify variables, files, and Docker setup
make clean                       # Remove container and image
make clean-all                   # Remove all runpod-ollama resources
make list-cache                  # List cached model extractions
make clean-cache                 # Clean all extraction cache
make clean-model-cache MODEL_FILE=model.gguf  # Clean specific model cache
make info                        # Show image/container info
make deploy-info                 # Show deployment instructions
```

**verify** checks:
- Variables (REGISTRY, IMAGE_NAME, MODEL_FILE, etc.)
- File existence (model file, scripts, Dockerfile)
- Docker availability and daemon status
- Extraction cache paths

### Quick Start
```bash
make quick-start                 # Build + run in one command
```

**Configuration:**

Override defaults with environment variables:
```bash
make build \
  REGISTRY=ghcr.io/myorg \
  IMAGE_NAME=ollama-handler \
  TAG=v1.0 \
  MODEL_FILE=my-model.gguf \
  MODEL_NAME=my-model

make run TEST_PORT=9000         # Run on different port
```

**Examples:**

```bash
# Quick start (build + run + test)
make quick-start MODEL_FILE=model.gguf
make test

# Custom registry and tag
make build \
  REGISTRY=ghcr.io/myusername \
  TAG=v1.0 \
  MODEL_FILE=llama-3.2.gguf

# Run and view logs
make run
make logs

# Test remote deployment
make test-remote ENDPOINT_ID=abc123xyz

# Cleanup everything
make clean-all
```

## Docker Compose

**Purpose:** Simplified local development with docker-compose.

**Usage:**

```bash
# Copy environment file
cp .env.example .env

# Edit .env with your settings
vim .env

# Start container
docker-compose up

# Start in background
docker-compose up -d

# View logs
docker-compose logs -f

# Stop
docker-compose down
```

**Configuration (.env file):**

```env
MODEL_FILE=model.gguf
MODEL_NAME=my-model
REGISTRY=your-username
IMAGE_NAME=runpod-ollama
TAG=latest
TEST_PORT=11434
```

## Manual Build (No Scripts)

If you prefer manual control:

```bash
# Build
docker build \
  --build-arg MODEL_NAME="my-model" \
  --build-arg EXTRACTED_MODELS_PATH="/absolute/path/to/extracted/models" \
  -t your-username/runpod-ollama:latest \
  .

# Run (using TEST_PORT, defaults to 11434)
docker run -d -p ${TEST_PORT:-11434}:11434  \
  --name runpod-ollama-local \
  your-username/runpod-ollama:latest

# Test
curl http://localhost:${PORT_HEALTH:-8080}/ping

# Stop
docker stop runpod-ollama-local
docker rm runpod-ollama-local
```

## Troubleshooting Scripts

### build.sh fails

**"No GGUF files found"**
- Download a model first
- Check you're in the correct directory
- Verify file extension is `.gguf`

**"Docker build failed"**
- Check Docker is running: `docker ps`
- Verify enough disk space: `df -h`
- Check model file isn't corrupted: `ls -lh *.gguf`

### test.sh failures

**"Connection refused"**
- Container not running: `docker ps`
- Wrong port: Check with `docker ps` (port mapping)
- Startup not complete: Wait 30-60s after `docker run`

**"Tests failed"**
- View logs: `docker logs runpod-ollama-local`
- Check Ollama started: `curl localhost:${PORT_HEALTH:-8080}/ping`
- Verify model loaded: `curl localhost:${TEST_PORT:-11434}/api/tags`

### Makefile issues

**"make: command not found"**
- Install make: `apt-get install build-essential` (Linux) or use Xcode tools (Mac)
- Use scripts directly instead: `./build.sh`, `./test.sh`

**"Permission denied"**
- Make scripts executable: `chmod +x *.sh`

## Tips & Best Practices

1. **Always test locally first**
   ```bash
   make quick-start MODEL_FILE=model.gguf
   make test
   ```

2. **Use build.sh for interactive builds**
   - Easier than remembering all arguments
   - Validates configuration before building
   - Shows helpful examples

3. **Use Makefile for repetitive tasks**
   - Faster than typing full docker commands
   - Consistent naming and configuration
   - Easy to remember: `make run`, `make test`

4. **Test remote deployments**
   ```bash
   make test-remote ENDPOINT_ID=your-id
   ```

5. **Clean up regularly**
   ```bash
   make clean-all  # Removes unused images/containers
   ```

## Script Permissions

All scripts should be executable:

```bash
chmod +x build.sh test.sh start.sh
```

If you get "Permission denied", run the chmod command above.

## Next Steps

After building and testing locally:

1. Push to registry: `make push`
2. Deploy to Runpod (see DEPLOYMENT.md)
3. Test remote: `make test-remote ENDPOINT_ID=xxx`
4. Configure Ollama Client with endpoint URL

## Support

For issues with scripts:
- Check script output for error messages
- View Docker logs: `make logs`
- Verify container status: `docker ps -a`
- See DEPLOYMENT.md for deployment troubleshooting

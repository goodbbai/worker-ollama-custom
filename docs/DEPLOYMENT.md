# Deployment Guide

Complete step-by-step guide for deploying the Runpod Ollama handler.

## Prerequisites

- [ ] Runpod account ([Sign up](https://runpod.io/))
- [ ] Docker installed locally
- [ ] Container registry account (Docker Hub, GitHub Container Registry, or Runpod Registry)
- [ ] GGUF model file downloaded

## Step-by-Step Deployment

### 1. Obtain a GGUF Model

Choose and download a GGUF model:

**Option A: From Hugging Face**
```bash
# Example: GLM-4 Vision model
wget https://huggingface.co/unsloth/GLM-4.6V-Flash-GGUF/resolve/main/GLM-4.6V-Flash.Q5_K_M.gguf
```

**Option B: From Other Sources**
- Ollama library: https://ollama.ai/library
- TheBloke on Hugging Face: https://huggingface.co/TheBloke
- Local model converted to GGUF format

**Model Size Considerations:**
- 7B models: ~4-8 GB
- 13B models: ~8-16 GB
- 34B+ models: 20+ GB

Select GPU with enough VRAM for your model.

### 2. Prepare the Project

```bash
# Clone or navigate to project directory
cd runpod_ollama

# Copy your GGUF model file here
cp /path/to/your/model.gguf ./my-model.gguf

# Verify file exists
ls -lh *.gguf
```

### 3. Build Docker Image

**Recommended: Use Makefile commands:**

```bash
# Build with automatic model extraction
make build MODEL_FILE=my-model.gguf REGISTRY=your-dockerhub-username

# Or use interactive build wizard
make build-interactive
```

The build process will:
1. Extract the model to Ollama's native format (cached for reuse)
2. Build the Docker image with pre-processed models
3. Tag the image with your registry

**Alternative: Direct script usage (advanced):**

```bash
./scripts/build.sh
```

**Manual build (advanced):**

```bash
# Set your model details
export MODEL_FILE="my-model.gguf"
export MODEL_NAME="my-model"
export REGISTRY="your-dockerhub-username"

# Step 1: Extract model (cached at ./extracted-models/)
./scripts/extract-model.sh \
  --model-file "$MODEL_FILE" \
  --model-name "$MODEL_NAME"

# Step 2: Build image with extracted models
HASH=$(shasum -a 256 "$MODEL_FILE" | cut -d' ' -f1)
EXTRACTED_PATH="./extracted-models/$HASH/models"

docker build \
  --platform linux/amd64 \
  --build-arg MODEL_NAME="$MODEL_NAME" \
  --build-arg EXTRACTED_MODELS_PATH="$EXTRACTED_PATH" \
  -f docker/Dockerfile \
  -t $REGISTRY/runpod-ollama:latest \
  .
```

**Build time:**
- First build: 7-20 minutes (includes model extraction)
- Subsequent builds: 5-10 minutes (uses cached extraction)

### 4. Push to Container Registry

**Docker Hub:**
```bash
docker login
docker push $REGISTRY/runpod-ollama:latest
```

**GitHub Container Registry:**
```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
docker push ghcr.io/$USERNAME/runpod-ollama:latest
```

**Runpod Registry:** (Coming soon)

### 5. Create Runpod Serverless Endpoint

#### Via Web Console

1. Navigate to https://www.runpod.io/console/serverless
2. Click **"+ New Endpoint"**

**Basic Configuration:**
- **Endpoint Name**: `ollama-enchanted` (or your preferred name)
- **Endpoint Type**: ⚠️ **Load Balancer** (NOT Queue!)

**Container Configuration:**
- **Docker Image Name**: `your-registry/runpod-ollama:latest`
- **Container Disk**: Calculate based on model size:
  - Formula: `model_size_gb + 10GB` (for Ollama + OS)
  - Example: 8GB model → 18GB container disk
  - Minimum: 15GB

**GPU Configuration:**
- **GPU Type**: Select based on model requirements
  - 7B models: RTX 3080 (10GB VRAM) or better
  - 13B models: RTX 3090/4090 (24GB VRAM)
  - 34B+ models: A100 (40-80GB VRAM)

**Advanced:**
- **Environment Variables**: (defaults are PORT=11434, PORT_HEALTH=8080)
  ```
  PORT=11434        # Ollama API port (default, optional to set)
  PORT_HEALTH=8080  # Health check port (default, optional to set)
  ```
  **Note:** External requests to `https://ENDPOINT_ID.api.runpod.ai` always route to the container's `PORT` internally (no port needed in URL).
- **Network Volume**: (Optional, for shared data)

3. Click **"Deploy"**

#### Via REST API

```bash
# Set your Runpod API key
export RUNPOD_API_KEY="your-api-key"

# Create endpoint
curl -X POST "https://api.runpod.io/v2/endpoints" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ollama-enchanted",
    "type": "load_balancer",
    "docker_image": "your-registry/runpod-ollama:latest",
    "container_disk_in_gb": 20,
    "gpu_type_id": "NVIDIA RTX A5000",
    "worker_config": {
      "min_workers": 0,
      "max_workers": 1,
      "idle_timeout": 60
    }
  }'
```

### 6. Verify Deployment

Wait for deployment (2-5 minutes). Check status:

1. Go to Runpod console → Serverless → Your endpoint
2. Status should show "Ready"
3. Note your **Endpoint ID**

**Test the endpoint:**

```bash
# Set endpoint ID
export ENDPOINT_ID="your-endpoint-id"
export RUNPOD_API_KEY="your-api-key"

# List models
curl -X GET "https://$ENDPOINT_ID.api.runpod.ai/api/tags" \
  -H "Authorization: Bearer $RUNPOD_API_KEY"

# Expected response:
# {"models":[{"name":"my-model:latest",...}]}

# Test chat (streaming)
curl -X POST "https://$ENDPOINT_ID.api.runpod.ai/api/chat" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "my-model",
    "messages": [{"role": "user", "content": "Say hello!"}],
    "stream": true
  }'
```

### 7. Start Chatting!

You're all set! Start a new conversation in Enchanted.

## Troubleshooting Deployment

### Build fails on Apple Silicon

**Note:** Building for `linux/amd64` on Apple Silicon uses emulation and is slower (2-3x). This is normal and expected for cross-platform builds.

### Build fails with "No such file"

**Cause:** GGUF file not found in build context.

**Fix:**
```bash
# Verify file exists
ls -lh *.gguf

# Use hard link if file is elsewhere on same filesystem
ln /path/to/model.gguf ./model.gguf
```

### Push fails with "denied: access forbidden"

**Cause:** Not logged in or wrong credentials.

**Fix:**
```bash
# Docker Hub
docker login

# GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
```

### Endpoint shows "Unhealthy" status

**Cause:** Container failed to start or model failed to load.

**Fix:**
1. Check logs in Runpod console
2. Verify container disk is large enough
3. Check GPU has enough VRAM
4. Review build logs for errors

### "Server Unreachable" in Enchanted

**Checklist:**
- [ ] Endpoint type is **Load Balancer** (not Queue)
- [ ] Worker is active (not idle/scaled to 0)
- [ ] URL format is correct: `https://ENDPOINT_ID.api.runpod.ai`
- [ ] No `/run` or `/runsync` in URL
- [ ] Bearer token is correct (if using authentication)

**Test endpoint directly:**
```bash
# ✅ Works - routes to Ollama on PORT
curl https://ENDPOINT_ID.api.runpod.ai/api/tags

# ❌ Returns 404 - /ping only accessible internally for health checks
curl https://ENDPOINT_ID.api.runpod.ai/ping
```

**Note:** The `/ping` endpoint is only accessible internally for Runpod's load balancer health checks.

### High cold start time (>2 minutes)

**Causes:**
- Large model file
- Slow GPU initialization
- Container disk pulling

**Optimizations:**
- Keep min_workers=1 for always-ready
- Use faster GPU tier
- Reduce model size (use quantized versions)

### Streaming stops mid-response

**Cause:** Timeout or connection issue.

**Fix:**
- Increase execution timeout in endpoint settings
- Check network stability
- Verify client supports streaming (OllamaKit does)

## Cost Estimation

**Example: RTX 3090 GPU**

- **Idle cost**: $0 (scaled to 0)
- **Active cost**: ~$0.40/hour
- **Typical usage**: 10 min/day = $0.07/day = $2/month

**Optimization tips:**
- Use min_workers=0 for on-demand
- Set idle timeout to 60-120 seconds
- Choose smallest GPU that fits your model

## Updating the Deployment

**To update model or code:**

1. Make changes locally
2. Rebuild image with new tag:
   ```bash
   docker build -t $REGISTRY/runpod-ollama:v2 .
   docker push $REGISTRY/runpod-ollama:v2
   ```
3. Update endpoint in Runpod console:
   - Go to endpoint settings
   - Change docker image to `:v2`
   - Save

**To change model parameters:**

Edit `start.sh` → rebuild → redeploy.

## Monitoring

**View logs:**
1. Runpod console → Serverless → Your endpoint
2. Click "Logs" tab
3. Select a worker instance

**Metrics to watch:**
- Request count
- Average latency
- Error rate
- GPU utilization
- Cost per request

## Next Steps

- [ ] Set up monitoring/alerts
- [ ] Configure auto-scaling based on load
- [ ] Add authentication middleware (if public)
- [ ] Optimize model parameters for your use case
- [ ] Test with different models

## Support Resources

- Runpod Discord: https://discord.gg/runpod
- Runpod Docs: https://docs.runpod.io/
- Ollama GitHub: https://github.com/ollama/ollama
- Enchanted GitHub: https://github.com/AugustDev/enchanted

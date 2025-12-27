# Quick Start Guide

Get your Ollama model deployed on Runpod in 6 steps.

## Prerequisites

- ✅ Runpod account ([sign up](https://runpod.io/))
- ✅ Docker installed and running
- ✅ `jq` installed (`brew install jq` on macOS, `apt install jq` on Linux)
- ✅ GGUF model file (or download one in Step 1)

## Steps

### 1. Download Model

```bash
# Example: GLM-4 Vision (8GB)
wget https://huggingface.co/unsloth/GLM-4.6V-Flash-GGUF/resolve/main/GLM-4.6V-Flash.Q5_K_M.gguf

# More models: https://huggingface.co/models?library=gguf
```

### 2. Configure

```bash
# Copy and edit environment file
cp .env.example .env
vim .env  # Set REGISTRY=your-dockerhub-username

# Optional: Create custom Modelfile template for model parameters
# See docs/SCRIPTS.md for Modelfile template syntax
```

### 3. Build Image

```bash
# Build with automatic model extraction (cached for speed)
make build 
# This extracts the model and builds the Docker image (~5-10 min)
```

### 4. Test Locally (Optional)

```bash
# Run container locally
make run

# Test in another terminal
make test

# Stop when done
make stop
```

### 5. Push to Registry

```bash
# Login to Docker Hub (if not already)
docker login

# Push image
make push
```

### 6. Deploy to Runpod

1. Go to https://www.runpod.io/console/serverless
2. Click **"+ New Endpoint"**
3. Configure:
  - **Type**: **Load Balancer** ⚠️ (NOT Queue!)
  - **Environment Variables**: (defaults are PORT=11434, PORT_HEALTH=8080)
    ```
    PORT=11434        # Ollama API port (default, optional to set)
    PORT_HEALTH=8080  # Health check port (default, optional to set)
    ```
4. Click **Deploy** and wait 2-5 minutes

**Testing Your Deployment:**

```bash
# Set your endpoint details
export ENDPOINT_ID="your-endpoint-id"
export RUNPOD_API_KEY="your-api-key"

# Test with make command
make test-remote ENDPOINT_ID=$ENDPOINT_ID RUNPOD_API_KEY=$RUNPOD_API_KEY

# Or test manually
curl https://$ENDPOINT_ID.api.runpod.ai/api/tags \
  -H "Authorization: Bearer $RUNPOD_API_KEY"
```

**Done! 🎉** Your Ollama model is now running on Runpod.

## Common Issues

- **Build fails**: Verify GGUF file exists: `ls -lh *.gguf`
- **Push fails**: Login first: `docker login`
- **Unhealthy endpoint**: Check logs in Runpod console, verify container disk size
- **Connection errors**: Ensure endpoint type is **Load Balancer** (NOT Queue)

## Next Steps

- **Customize model behavior**: See [SCRIPTS.md](SCRIPTS.md) for Modelfile templates
- **Troubleshooting**: See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed help
- **Advanced usage**: See [SCRIPTS.md](SCRIPTS.md) for all available commands
- **API reference**: [Ollama API docs](https://github.com/ollama/ollama/blob/main/docs/api.md)

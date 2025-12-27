# Runpod Ollama Serverless Handler

Run custom LLM models via Ollama on Runpod Serverless Load Balancer.

## 📋 Overview

This project **creates a Docker image containing your custom LLM model** and deploys it on **Runpod Serverless** with a **Load Balancer** endpoint using **Ollama**.

### How It Works

1. **Build Phase**: Extracts your GGUF model into Ollama's native format and packages it into a Docker image
2. **Deploy Phase**: Pushes the image to a container registry and deploys on Runpod Serverless
3. **Runtime**: The containerized model starts in 5-15 seconds (no model download needed - it's already in the image!)

### Key Features

- 🎯 **Custom Models**: Use any GGUF model from Hugging Face or local files
- 📦 **Pre-packaged**: Model is embedded in Docker image for fast cold starts
- 🚀 **Serverless Deployment**: Pay only when active, scale to zero when idle
-  **Client Compatible**: Works with Enchanted, OllamaKit, and other Ollama clients
- 🎨 **Customizable**: Use Modelfile templates to configure chat formats and parameters

### What This Solves

- **Package custom models** into ready-to-deploy Docker images
- **Fast cold starts** - model is pre-loaded in the image (5-15s vs 60-90s runtime extraction)
- **Access via standard Ollama API** from any client application

## 🚀 Quick Start

```bash
# Download model, build image, test, and deploy
wget https://huggingface.co/unsloth/GLM-4.6V-Flash-GGUF/resolve/main/GLM-4.6V-Flash.Q5_K_M.gguf
make build MODEL_FILE=GLM-4.6V-Flash.Q5_K_M.gguf
make run && make test
make push
```

**New to this project?** See [docs/QUICKSTART.md](docs/QUICKSTART.md) for complete step-by-step guide.

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [QUICKSTART.md](docs/QUICKSTART.md) | Step-by-step deployment guide |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Detailed Runpod configuration & troubleshooting |
| [SCRIPTS.md](docs/SCRIPTS.md) | Makefile commands & build scripts reference |

## 🎯 Features

- ✅ Full Ollama API compatibility
- ✅ Drop-in replacement for Ollama server
- ✅ Low latency with Pre-generated Ollama model
- ✅ Modelfile templates for custom chat formats and parameters

## 🎨 Architecture

```
Ollama client → Runpod Load Balancer → [PORT 11434]  Ollama (Direct) → GGUF Model
                                      ↓
                   Health Checks →  [PORT 8080] Health Server (/ping)
```

**Dual-process architecture:**
- ✅ Ollama runs directly on PORT (11434) - handles all /api/* and HEAD / endpoints
- ✅ Health server on PORT_HEALTH (8080) - handles /ping for RunPod load balancing
- ✅ Streaming enabled with native Ollama support

## 📝 Requirements

- Docker
- Runpod account
- GGUF model file
- Container registry (Docker Hub, GitHub, etc.)

---

**Ready to get started?** → [Quick Start Guide](docs/QUICKSTART.md)

# Dockerfile for Runpod Ollama Serverless Handler
# This creates a container with Ollama and a FastAPI reverse proxy

FROM ollama/ollama:latest

# Copy pre-extracted ollama models
# These were extracted during build using extract-model.sh
# This contains the model blobs and manifests in Ollama's native format
# Copy it in advance to avoid time-consuming rebuild
ARG EXTRACTED_MODELS_PATH=""
COPY --chown=root:root $EXTRACTED_MODELS_PATH /root/.ollama/models

# Build arguments for model configuration
ARG MODEL_NAME="GLM-4.6V-Flash-GGUF"
ARG PORT=11434
ARG PORT_HEALTH=8080

# Install Python, pip, curl, and create virtual environment
RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-venv curl && \
    rm -rf /var/lib/apt/lists/*

# Create and activate virtual environment
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Environment variables for Ollama and model
ENV OLLAMA_HOST=0.0.0.0
ENV OLLAMA_MODELS=/root/.ollama/models
ENV CUSTOM_MODEL_NAME=$MODEL_NAME
ENV PORT=$PORT
ENV PORT_HEALTH=$PORT_HEALTH
ENV OLLAMA_BASE_URL=http://localhost:${PORT}
ENV PYTHONUNBUFFERED=1

# Create application directory
WORKDIR /usr/src/app

# Install Python dependencies
COPY src/requirements.txt /usr/src/app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY src/health_server.py /usr/src/app/health_server.py
COPY scripts/start.sh /usr/local/bin/start.sh

# Make startup script executable
RUN chmod +x /usr/local/bin/start.sh

# Expose Ollama API port and health check port
EXPOSE $PORT
EXPOSE $PORT_HEALTH

# Start the application
ENTRYPOINT ["/usr/local/bin/start.sh"]

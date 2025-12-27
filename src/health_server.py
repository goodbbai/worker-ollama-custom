"""
Minimal health server for RunPod Load Balancer health checks.
Runs on PORT_HEALTH (default 8080) and responds to /ping only.
HEAD / is handled by Ollama natively on PORT.
"""
import os
import logging
from fastapi import FastAPI
import httpx
import uvicorn

# Logging configuration
logging.basicConfig(
    level=logging.DEBUG if os.getenv("LOG_LEVEL") == "DEBUG" else logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
PORT_HEALTH = int(os.getenv("PORT_HEALTH", "8080"))
PORT = int(os.getenv("PORT", "80"))
OLLAMA_URL = f"http://localhost:{PORT}"

# FastAPI app
app = FastAPI(
    title="RunPod Health Server",
    description="Health check endpoint for RunPod Load Balancer",
    version="1.0.0"
)

# HTTP client for Ollama connectivity checks
client = httpx.AsyncClient(timeout=httpx.Timeout(2.0))

@app.on_event("startup")
async def startup_event():
    logger.info(f"Starting Health Server on port {PORT_HEALTH}")
    logger.info(f"Monitoring Ollama at {OLLAMA_URL}")

@app.on_event("shutdown")
async def shutdown_event():
    await client.aclose()
    logger.info("Health server shutdown complete")

@app.get("/ping")
async def health_check():
    """
    Health check endpoint required by RunPod Load Balancing.
    Returns 200 immediately to mark worker as healthy.
    Optionally verifies Ollama is reachable with a short timeout.
    """
    logger.debug("GET /ping - Health check request")

    try:
        # Try to reach Ollama with a short timeout
        response = await client.head(f"{OLLAMA_URL}/", timeout=2.0)

        if response.status_code == 200:
            logger.debug("Health check: Ollama reachable")
            return {"status": "healthy", "ollama": "reachable"}
        else:
            logger.warning(f"Health check: Ollama degraded (status {response.status_code})")
            return {"status": "healthy", "ollama": "degraded"}

    except Exception as e:
        logger.warning(f"Health check: Ollama not ready: {e}")
        return {"status": "healthy", "ollama": "initializing"}

if __name__ == "__main__":
    logger.info(f"Starting health server on 0.0.0.0:{PORT_HEALTH}")
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=PORT_HEALTH,
        log_level="info",
        access_log=True
    )
